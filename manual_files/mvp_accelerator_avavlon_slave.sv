module mvp_accelerator_avalon_slave (
    input  logic        clock,
    input  logic        resetn,
    input  logic        read,
    input  logic        write,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

    logic [31:0] result_reg;

    // Compute & store result ONLY on write
    always_ff @(posedge clock) begin
        if (!resetn) begin
            result_reg <= 32'd0;
        end
        else if (write) begin
            // Layout: [ A1 | A0 | B1 | B0 ]  (MSB -> LSB)
            result_reg <= (write_data[31:24] * write_data[15:8]) +
                          (write_data[23:16] * write_data[7:0]);
        end
    end

    // Return last computed result
    always_comb begin
        if (read)
            read_data = result_reg;
        else
            read_data = 32'd0;
    end

endmodule
