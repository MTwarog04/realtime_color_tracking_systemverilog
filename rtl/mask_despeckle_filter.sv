// Autor: Maciej Nowak
`timescale 1ns / 1ps

module mask_despeckle_filter #(
    parameter int IMG_W = 320
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       pix_valid,
    input  logic [8:0] pix_x,
    input  logic [7:0] pix_y,
    input  logic       mask_in,
    output logic       mask_out
);

    // Two one-bit line buffers and six shift registers form a causal 3x3
    // neighbourhood. Using only already received pixels avoids adding latency
    // to the luminance and coordinates used by the frame buffer.
    logic [IMG_W-1:0] previous_line_1;
    logic [IMG_W-1:0] previous_line_2;

    logic current_left_1;
    logic current_left_2;
    logic line_1_left_1;
    logic line_1_left_2;
    logic line_2_left_1;
    logic line_2_left_2;

    logic line_1_current;
    logic line_2_current;
    logic [3:0] neighbour_count;

    always_comb begin
        line_1_current = (pix_y >= 1) ? previous_line_1[pix_x] : 1'b0;
        line_2_current = (pix_y >= 2) ? previous_line_2[pix_x] : 1'b0;

        neighbour_count = 4'd0;

        if (pix_x >= 1) begin
            neighbour_count = neighbour_count + current_left_1;
            if (pix_y >= 1) neighbour_count = neighbour_count + line_1_left_1;
            if (pix_y >= 2) neighbour_count = neighbour_count + line_2_left_1;
        end
        if (pix_x >= 2) begin
            neighbour_count = neighbour_count + current_left_2;
            if (pix_y >= 1) neighbour_count = neighbour_count + line_1_left_2;
            if (pix_y >= 2) neighbour_count = neighbour_count + line_2_left_2;
        end
        if (pix_y >= 1) neighbour_count = neighbour_count + line_1_current;
        if (pix_y >= 2) neighbour_count = neighbour_count + line_2_current;

        // Suppress only a fully isolated pixel. A pair or a larger group is
        // retained, which protects the visual footprint of a distant ball.
        mask_out = pix_valid && mask_in && (neighbour_count != 0);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_line_1 <= '0;
            previous_line_2 <= '0;
            current_left_1 <= 1'b0;
            current_left_2 <= 1'b0;
            line_1_left_1 <= 1'b0;
            line_1_left_2 <= 1'b0;
            line_2_left_1 <= 1'b0;
            line_2_left_2 <= 1'b0;
        end else if (pix_valid) begin
            previous_line_2[pix_x] <= previous_line_1[pix_x];
            previous_line_1[pix_x] <= mask_in;

            if (pix_x == 0) begin
                current_left_1 <= mask_in;
                current_left_2 <= 1'b0;
                line_1_left_1 <= line_1_current;
                line_1_left_2 <= 1'b0;
                line_2_left_1 <= line_2_current;
                line_2_left_2 <= 1'b0;
            end else begin
                current_left_2 <= current_left_1;
                current_left_1 <= mask_in;
                line_1_left_2 <= line_1_left_1;
                line_1_left_1 <= line_1_current;
                line_2_left_2 <= line_2_left_1;
                line_2_left_1 <= line_2_current;
            end
        end
    end

endmodule
