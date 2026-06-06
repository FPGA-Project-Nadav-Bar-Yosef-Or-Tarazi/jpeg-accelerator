module mvp_accelerator_avalon_slave (
    input  logic [31:0] address,
    input  logic        clock,
    input  logic        resetn,
    input  logic        read,
    input  logic        write,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

    // ------------------------------------------------------------
    // Address decoding
    //
    // If C uses:
    //   IOWR_32DIRECT(BASE, 4 * op, data)
    // then opcode should usually be address[7:2].
    //
    // If your Platform Designer component already gives word offsets,
    // change this to:
    //   assign opcode = address[5:0];
    // ------------------------------------------------------------
    logic [5:0] opcode;
    assign opcode = address[5:0];

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
    // Register map
    //
    // Write:
    //   0..15 -> input pixels, four signed 8-bit pixels per write
    //   16    -> OP_CALC
    //
    // Read:
    //   0..15 -> output DCT coefficients, four signed 8-bit values per read
    //   16    -> OP_STATUS
    // ------------------------------------------------------------
    localparam logic [5:0] OP_ROW0_FIRST4 = 6'd0;
    localparam logic [5:0] OP_ROW0_LAST4  = 6'd1;

    localparam logic [5:0] OP_ROW1_FIRST4 = 6'd2;
    localparam logic [5:0] OP_ROW1_LAST4  = 6'd3;

    localparam logic [5:0] OP_ROW2_FIRST4 = 6'd4;
    localparam logic [5:0] OP_ROW2_LAST4  = 6'd5;

    localparam logic [5:0] OP_ROW3_FIRST4 = 6'd6;
    localparam logic [5:0] OP_ROW3_LAST4  = 6'd7;

    localparam logic [5:0] OP_ROW4_FIRST4 = 6'd8;
    localparam logic [5:0] OP_ROW4_LAST4  = 6'd9;

    localparam logic [5:0] OP_ROW5_FIRST4 = 6'd10;
    localparam logic [5:0] OP_ROW5_LAST4  = 6'd11;

    localparam logic [5:0] OP_ROW6_FIRST4 = 6'd12;
    localparam logic [5:0] OP_ROW6_LAST4  = 6'd13;

    localparam logic [5:0] OP_ROW7_FIRST4 = 6'd14;
    localparam logic [5:0] OP_ROW7_LAST4  = 6'd15;

    // Same numeric opcode:
    //   write to 16 -> calculate
    //   read  from 16 -> status
    localparam logic [5:0] OP_CALC   = 6'd16;
    localparam logic [5:0] OP_STATUS = 6'd16;

    // ------------------------------------------------------------
    // Internal storage
    // ------------------------------------------------------------

    // Software sends already-centered pixels:
    //   pixel - 128
    //
    // Range:
    //   -128 to +127
    logic signed [7:0] pixels [7:0][7:0];

    // Full-precision Q28 accumulators
    logic signed [63:0] dct_acc_comb [7:0][7:0];

    // Final registered DCT output.
    // 8-bit lets us read four values per 32-bit read.
    logic signed [7:0] dct_out [7:0][7:0];

    logic busy;
    logic done;

    // ------------------------------------------------------------
    // Saturate 64-bit signed value to signed 8-bit
    // ------------------------------------------------------------
    function automatic logic signed [7:0] sat8;
        input logic signed [63:0] value;

        begin
            if (value > 64'sd127) begin
                sat8 = 8'sd127;
            end else if (value < -64'sd128) begin
                sat8 = 8'sh80;   // -128 in signed 8-bit
            end else begin
                sat8 = value[7:0];
            end
        end
    endfunction

    // ------------------------------------------------------------
    // One DCT term:
    //
    // DCT_C[u][x] * pixels[x][y] * DCT_C[v][y]
    //
    // DCT_C is Q14.
    // pixels are signed integer.
    // term is Q28.
    // ------------------------------------------------------------
    function automatic logic signed [63:0] dct_term;
        input logic [2:0] u;
        input logic [2:0] v;
        input logic [2:0] x;
        input logic [2:0] y;

        logic signed [31:0] mult1;
        logic signed [63:0] mult2;

        begin
            mult1 = $signed(DCT_C[u][x]) * $signed(pixels[x][y]);
            mult2 = $signed(mult1)       * $signed(DCT_C[v][y]);

            dct_term = mult2;
        end
    endfunction

    // ------------------------------------------------------------
    // One full DCT coefficient:
    //
    // sum over x,y:
    //   DCT_C[u][x] * pixels[x][y] * DCT_C[v][y]
    // ------------------------------------------------------------
    function automatic logic signed [63:0] dct_coeff_sum;
        input logic [2:0] u;
        input logic [2:0] v;

        logic signed [63:0] sum;

        begin
            sum = 64'sd0;

            for (int x = 0; x < 8; x++) begin
                for (int y = 0; y < 8; y++) begin
                    sum = sum + dct_term(u, v, x[2:0], y[2:0]);
                end
            end

            dct_coeff_sum = sum;
        end
    endfunction

    // ------------------------------------------------------------
    // Fully parallel combinational DCT.
    //
    // Creates all 64 DCT coefficient sums in parallel.
    // ------------------------------------------------------------
    always_comb begin
        for (int u = 0; u < 8; u++) begin
            for (int v = 0; v < 8; v++) begin
                dct_acc_comb[u][v] = dct_coeff_sum(u[2:0], v[2:0]);
            end
        end
    end

    // ------------------------------------------------------------
    // Sequential logic:
    // - write centered pixels
    // - capture all DCT outputs on OP_CALC
    // ------------------------------------------------------------
    always_ff @(posedge clock or negedge resetn) begin
        if (!resetn) begin

            for (int r = 0; r < 8; r++) begin
                for (int c = 0; c < 8; c++) begin
                    pixels[r][c]  <= 8'sd0;
                    dct_out[r][c] <= 8'sd0;
                end
            end

            busy <= 1'b0;
            done <= 1'b0;

        end else begin

            busy <= 1'b0;

            if (write) begin
                case (opcode)

                    OP_ROW0_FIRST4: begin
                        pixels[0][0] <= write_data[7:0];
                        pixels[0][1] <= write_data[15:8];
                        pixels[0][2] <= write_data[23:16];
                        pixels[0][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW0_LAST4: begin
                        pixels[0][4] <= write_data[7:0];
                        pixels[0][5] <= write_data[15:8];
                        pixels[0][6] <= write_data[23:16];
                        pixels[0][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW1_FIRST4: begin
                        pixels[1][0] <= write_data[7:0];
                        pixels[1][1] <= write_data[15:8];
                        pixels[1][2] <= write_data[23:16];
                        pixels[1][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW1_LAST4: begin
                        pixels[1][4] <= write_data[7:0];
                        pixels[1][5] <= write_data[15:8];
                        pixels[1][6] <= write_data[23:16];
                        pixels[1][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW2_FIRST4: begin
                        pixels[2][0] <= write_data[7:0];
                        pixels[2][1] <= write_data[15:8];
                        pixels[2][2] <= write_data[23:16];
                        pixels[2][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW2_LAST4: begin
                        pixels[2][4] <= write_data[7:0];
                        pixels[2][5] <= write_data[15:8];
                        pixels[2][6] <= write_data[23:16];
                        pixels[2][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW3_FIRST4: begin
                        pixels[3][0] <= write_data[7:0];
                        pixels[3][1] <= write_data[15:8];
                        pixels[3][2] <= write_data[23:16];
                        pixels[3][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW3_LAST4: begin
                        pixels[3][4] <= write_data[7:0];
                        pixels[3][5] <= write_data[15:8];
                        pixels[3][6] <= write_data[23:16];
                        pixels[3][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW4_FIRST4: begin
                        pixels[4][0] <= write_data[7:0];
                        pixels[4][1] <= write_data[15:8];
                        pixels[4][2] <= write_data[23:16];
                        pixels[4][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW4_LAST4: begin
                        pixels[4][4] <= write_data[7:0];
                        pixels[4][5] <= write_data[15:8];
                        pixels[4][6] <= write_data[23:16];
                        pixels[4][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW5_FIRST4: begin
                        pixels[5][0] <= write_data[7:0];
                        pixels[5][1] <= write_data[15:8];
                        pixels[5][2] <= write_data[23:16];
                        pixels[5][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW5_LAST4: begin
                        pixels[5][4] <= write_data[7:0];
                        pixels[5][5] <= write_data[15:8];
                        pixels[5][6] <= write_data[23:16];
                        pixels[5][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW6_FIRST4: begin
                        pixels[6][0] <= write_data[7:0];
                        pixels[6][1] <= write_data[15:8];
                        pixels[6][2] <= write_data[23:16];
                        pixels[6][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW6_LAST4: begin
                        pixels[6][4] <= write_data[7:0];
                        pixels[6][5] <= write_data[15:8];
                        pixels[6][6] <= write_data[23:16];
                        pixels[6][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW7_FIRST4: begin
                        pixels[7][0] <= write_data[7:0];
                        pixels[7][1] <= write_data[15:8];
                        pixels[7][2] <= write_data[23:16];
                        pixels[7][3] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_ROW7_LAST4: begin
                        pixels[7][4] <= write_data[7:0];
                        pixels[7][5] <= write_data[15:8];
                        pixels[7][6] <= write_data[23:16];
                        pixels[7][7] <= write_data[31:24];
                        done <= 1'b0;
                    end

                    OP_CALC: begin
                        busy <= 1'b1;
                        done <= 1'b1;

                        // dct_acc_comb is Q28.
                        //
                        // >>> 28 gives DCT(image - 128).
                        // >>> 36 gives DCT((image - 128) / 256).
                        //
                        // Since dct_out is only 8-bit, this version uses >>> 36
                        // and then saturates to signed 8-bit.
                        for (int u = 0; u < 8; u++) begin
                            for (int v = 0; v < 8; v++) begin
                                dct_out[u][v] <= sat8(dct_acc_comb[u][v] >>> 36);
                            end
                        end
                    end

                    default: begin
                        // do nothing
                    end

                endcase
            end
        end
    end

    // ------------------------------------------------------------
    // Read logic:
    //
    // Only readable:
    //   opcode 0..15 -> dct_out, four signed 8-bit values per read
    //   opcode 16    -> status
    //
    // Read packing matches input-write packing:
    //
    // opcode 0:
    //   read_data[7:0]   = dct_out[0][0]
    //   read_data[15:8]  = dct_out[0][1]
    //   read_data[23:16] = dct_out[0][2]
    //   read_data[31:24] = dct_out[0][3]
    //
    // opcode 1:
    //   read_data[7:0]   = dct_out[0][4]
    //   read_data[15:8]  = dct_out[0][5]
    //   read_data[23:16] = dct_out[0][6]
    //   read_data[31:24] = dct_out[0][7]
    // ------------------------------------------------------------
    always_comb begin
        read_data = 32'd0;

        if (read) begin
            case (opcode)

                OP_ROW0_FIRST4: begin
                    read_data = {
                        dct_out[0][3],
                        dct_out[0][2],
                        dct_out[0][1],
                        dct_out[0][0]
                    };
                end

                OP_ROW0_LAST4: begin
                    read_data = {
                        dct_out[0][7],
                        dct_out[0][6],
                        dct_out[0][5],
                        dct_out[0][4]
                    };
                end

                OP_ROW1_FIRST4: begin
                    read_data = {
                        dct_out[1][3],
                        dct_out[1][2],
                        dct_out[1][1],
                        dct_out[1][0]
                    };
                end

                OP_ROW1_LAST4: begin
                    read_data = {
                        dct_out[1][7],
                        dct_out[1][6],
                        dct_out[1][5],
                        dct_out[1][4]
                    };
                end

                OP_ROW2_FIRST4: begin
                    read_data = {
                        dct_out[2][3],
                        dct_out[2][2],
                        dct_out[2][1],
                        dct_out[2][0]
                    };
                end

                OP_ROW2_LAST4: begin
                    read_data = {
                        dct_out[2][7],
                        dct_out[2][6],
                        dct_out[2][5],
                        dct_out[2][4]
                    };
                end

                OP_ROW3_FIRST4: begin
                    read_data = {
                        dct_out[3][3],
                        dct_out[3][2],
                        dct_out[3][1],
                        dct_out[3][0]
                    };
                end

                OP_ROW3_LAST4: begin
                    read_data = {
                        dct_out[3][7],
                        dct_out[3][6],
                        dct_out[3][5],
                        dct_out[3][4]
                    };
                end

                OP_ROW4_FIRST4: begin
                    read_data = {
                        dct_out[4][3],
                        dct_out[4][2],
                        dct_out[4][1],
                        dct_out[4][0]
                    };
                end

                OP_ROW4_LAST4: begin
                    read_data = {
                        dct_out[4][7],
                        dct_out[4][6],
                        dct_out[4][5],
                        dct_out[4][4]
                    };
                end

                OP_ROW5_FIRST4: begin
                    read_data = {
                        dct_out[5][3],
                        dct_out[5][2],
                        dct_out[5][1],
                        dct_out[5][0]
                    };
                end

                OP_ROW5_LAST4: begin
                    read_data = {
                        dct_out[5][7],
                        dct_out[5][6],
                        dct_out[5][5],
                        dct_out[5][4]
                    };
                end

                OP_ROW6_FIRST4: begin
                    read_data = {
                        dct_out[6][3],
                        dct_out[6][2],
                        dct_out[6][1],
                        dct_out[6][0]
                    };
                end

                OP_ROW6_LAST4: begin
                    read_data = {
                        dct_out[6][7],
                        dct_out[6][6],
                        dct_out[6][5],
                        dct_out[6][4]
                    };
                end

                OP_ROW7_FIRST4: begin
                    read_data = {
                        dct_out[7][3],
                        dct_out[7][2],
                        dct_out[7][1],
                        dct_out[7][0]
                    };
                end

                OP_ROW7_LAST4: begin
                    read_data = {
                        dct_out[7][7],
                        dct_out[7][6],
                        dct_out[7][5],
                        dct_out[7][4]
                    };
                end

                OP_STATUS: begin
                    read_data = {30'd0, done, busy};
                end

                default: begin
                    read_data = 32'd0;
                end

            endcase
        end
    end

endmodule