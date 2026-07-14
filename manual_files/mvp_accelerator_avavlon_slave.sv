module mvp_accelerator_avalon_slave (
    input  logic [1:0]  address,
    input  logic        clock,
    input  logic        resetn,
    input  logic        read,
    input  logic        write,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

// ------------------------------------------------------------
// DCT coefficients in Q14 fixed point
// real coefficient = DCT_C / 16384
// ------------------------------------------------------------
localparam logic signed [15:0] DCT_C [7:0][7:0] = '{
    '{ 16'sd11585,  16'sd11585,  16'sd11585,  16'sd11585,  16'sd11585,  16'sd11585,  16'sd11585,  16'sd11585 },
    '{ 16'sd16069,  16'sd13623,  16'sd9102,   16'sd3196,  -16'sd3196,  -16'sd9102,  -16'sd13623, -16'sd16069 },
    '{ 16'sd15137,  16'sd6270,  -16'sd6270,  -16'sd15137, -16'sd15137, -16'sd6270,   16'sd6270,   16'sd15137 },
    '{ 16'sd13623, -16'sd3196,  -16'sd16069, -16'sd9102,   16'sd9102,   16'sd16069,  16'sd3196,  -16'sd13623 },
    '{ 16'sd11585, -16'sd11585, -16'sd11585,  16'sd11585,  16'sd11585, -16'sd11585, -16'sd11585,  16'sd11585 },
    '{ 16'sd9102,  -16'sd16069,  16'sd3196,   16'sd13623, -16'sd13623, -16'sd3196,   16'sd16069, -16'sd9102 },
    '{ 16'sd6270,  -16'sd15137,  16'sd15137, -16'sd6270,  -16'sd6270,   16'sd15137, -16'sd15137,  16'sd6270 },
    '{ 16'sd3196,  -16'sd9102,   16'sd13623, -16'sd16069,  16'sd16069, -16'sd13623,  16'sd9102,  -16'sd3196 }
};

// ------------------------------------------------------------
// FIFO-style register map
//
// address 0 = REG_IN_FIFO
// address 1 = OP_CALC
// address 2 = REG_OUT_FIFO
// address 3 = DEBUG_REG / STATUS
// ------------------------------------------------------------
localparam logic [1:0] REG_IN_FIFO  = 2'd0;
localparam logic [1:0] OP_CALC      = 2'd1;
localparam logic [1:0] REG_OUT_FIFO = 2'd2;
localparam logic [1:0] DEBUG_REG    = 2'd3;

// ------------------------------------------------------------
// Internal storage
// ------------------------------------------------------------
logic signed [7:0] pixels  [7:0][7:0];
logic signed [7:0] dct_out [7:0][7:0];

logic [4:0] in_count;
logic [4:0] out_count;

logic calc_busy;
logic done;

logic input_full;
logic output_valid;

logic [2:0] in_row;
logic       in_half;

logic [2:0] out_row;
logic       out_half;

logic [3:0] calc_count;
logic [2:0] calc_u;
logic       calc_half;
logic [2:0] calc_v_base;

logic signed [63:0] calc_acc_comb [3:0];

logic [31:0] debug_reg;

assign input_full   = (in_count == 5'd16);
assign output_valid = done && (out_count < 5'd16);

assign in_row   = in_count[3:1];
assign in_half  = in_count[0];

assign out_row  = out_count[3:1];
assign out_half = out_count[0];

assign calc_u      = calc_count[3:1];
assign calc_half   = calc_count[0];
assign calc_v_base = {calc_half, 2'b00};   // 0 or 4

// ------------------------------------------------------------
// Saturate 64-bit signed value to signed 8-bit
// ------------------------------------------------------------
function automatic logic signed [7:0] sat8;
    input logic signed [63:0] value;

    begin
        if (value > 64'sd127) begin
            sat8 = 8'sd127;
        end else if (value < -64'sd128) begin
            sat8 = -8'sd128;
        end else begin
            sat8 = value[7:0];
        end
    end
endfunction

// ------------------------------------------------------------
// Combinational engine for only 4 DCT outputs
//
// In each calculation cycle, this computes:
//
// dct_out[calc_u][calc_v_base + 0]
// dct_out[calc_u][calc_v_base + 1]
// dct_out[calc_u][calc_v_base + 2]
// dct_out[calc_u][calc_v_base + 3]
//
// This is much smaller than the fully parallel 64-output version.
// ------------------------------------------------------------
always_comb begin
    logic signed [31:0] mult1;
    logic signed [63:0] mult2;

    for (int k = 0; k < 4; k++) begin
        calc_acc_comb[k] = 64'sd0;
    end

    for (int k = 0; k < 4; k++) begin
        for (int x = 0; x < 8; x++) begin
            for (int y = 0; y < 8; y++) begin
                mult1 = $signed(DCT_C[calc_u][x]) *
                        $signed(pixels[x][y]);

                mult2 = $signed(mult1) *
                        $signed(DCT_C[calc_v_base + k][y]);

                calc_acc_comb[k] = calc_acc_comb[k] + mult2;
            end
        end
    end
end

// ------------------------------------------------------------
// Sequential logic
// ------------------------------------------------------------
always_ff @(posedge clock or negedge resetn) begin
    if (!resetn) begin

        for (int r = 0; r < 8; r++) begin
            for (int c = 0; c < 8; c++) begin
                pixels[r][c]  <= 8'sd0;
                dct_out[r][c] <= 8'sd0;
            end
        end

        calc_busy <= 1'b0;
        done      <= 1'b0;

        in_count   <= 5'd0;
        out_count  <= 5'd0;
        calc_count <= 4'd0;

        debug_reg <= 32'd0;

    end else begin

        // --------------------------------------------------------
        // Input FIFO write
        //
        // Only accept new input when not calculating and when old
        // output was already fully consumed.
        // --------------------------------------------------------
        if (write &&
            address == REG_IN_FIFO &&
            !calc_busy &&
            !done &&
            in_count < 5'd16) begin

            if (!in_half) begin
                pixels[in_row][0] <= write_data[7:0];
                pixels[in_row][1] <= write_data[15:8];
                pixels[in_row][2] <= write_data[23:16];
                pixels[in_row][3] <= write_data[31:24];
            end else begin
                pixels[in_row][4] <= write_data[7:0];
                pixels[in_row][5] <= write_data[15:8];
                pixels[in_row][6] <= write_data[23:16];
                pixels[in_row][7] <= write_data[31:24];
            end

            in_count <= in_count + 5'd1;
        end

        // --------------------------------------------------------
        // Debug register write
        // --------------------------------------------------------
        if (write && address == DEBUG_REG) begin
            debug_reg <= write_data;
        end

        // --------------------------------------------------------
        // Start calculation
        //
        // Requires exactly 16 input FIFO writes.
        // --------------------------------------------------------
        if (write &&
            address == OP_CALC &&
            input_full &&
            !calc_busy &&
            !done) begin

            calc_busy  <= 1'b1;
            done       <= 1'b0;
            calc_count <= 4'd0;
            out_count  <= 5'd0;

            // allow next input block only after output is consumed
            in_count <= 5'd0;
        end

        // --------------------------------------------------------
        // Calculation engine
        //
        // Stores 4 DCT outputs per clock.
        // Total latency: 16 clocks after OP_CALC.
        // --------------------------------------------------------
        if (calc_busy) begin

            dct_out[calc_u][calc_v_base + 3'd0] <= sat8(calc_acc_comb[0] >>> 30);
            dct_out[calc_u][calc_v_base + 3'd1] <= sat8(calc_acc_comb[1] >>> 30);
            dct_out[calc_u][calc_v_base + 3'd2] <= sat8(calc_acc_comb[2] >>> 30);
            dct_out[calc_u][calc_v_base + 3'd3] <= sat8(calc_acc_comb[3] >>> 30);

            if (calc_count == 4'd15) begin
                calc_busy <= 1'b0;
                done      <= 1'b1;
            end else begin
                calc_count <= calc_count + 4'd1;
            end
        end

        // --------------------------------------------------------
        // Output FIFO read pointer increment
        // --------------------------------------------------------
        if (read && address == REG_OUT_FIFO && output_valid) begin
            if (out_count == 5'd15) begin
                out_count <= 5'd16;
                done      <= 1'b0;
            end else begin
                out_count <= out_count + 5'd1;
            end
        end

    end
end

// ------------------------------------------------------------
// Read logic
// ------------------------------------------------------------
always_comb begin
    read_data = 32'd0;

    if (read && address == REG_OUT_FIFO) begin

        if (output_valid) begin
            if (!out_half) begin
                read_data = {
                    dct_out[out_row][3],
                    dct_out[out_row][2],
                    dct_out[out_row][1],
                    dct_out[out_row][0]
                };
            end else begin
                read_data = {
                    dct_out[out_row][7],
                    dct_out[out_row][6],
                    dct_out[out_row][5],
                    dct_out[out_row][4]
                };
            end
        end else begin
            read_data = 32'd0;
        end

    end else if (read && address == DEBUG_REG) begin

        // Status/debug layout:
        //
        // bit 0  = calc_busy
        // bit 1  = done
        // bit 2  = input_full
        // bit 3  = output_valid
        // bits 8:4   = in_count
        // bits 13:9  = out_count
        // bits 17:14 = calc_count
        //
        read_data = {
            debug_reg[31:18],
            calc_count,
            out_count,
            in_count,
            output_valid,
            input_full,
            done,
            calc_busy
        };

    end else begin
        read_data = 32'd0;
    end
end

endmodule