
`timescale 1ns / 1ps


module centroid_accumulator #(    parameter int IMG_W = 320,
    parameter int IMG_H = 240,
    parameter int TOP_IGNORE_LINES = 30
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        pix_valid,
    input  logic        frame_start,
    input  logic        mask,
    input  logic [8:0]  pix_x,
    input  logic [7:0]  pix_y,
    input  logic [4:0]  min_blob_sw,
    output logic [8:0]  centroid_x,
    output logic [7:0]  centroid_y,
    output logic        centroid_valid,
    output logic [16:0] mask_pixel_count
);

    localparam int SUM_X_W = $clog2(IMG_W * IMG_H * (IMG_W - 1)) + 1;
    localparam int SUM_Y_W = $clog2(IMG_W * IMG_H * (IMG_H - 1)) + 1;
    localparam int CNT_W = $clog2(IMG_W * IMG_H + 1);

    logic [SUM_X_W-1:0] sum_x;
    logic [SUM_Y_W-1:0] sum_y;
    logic [CNT_W-1:0]   pixel_count;

    logic [SUM_X_W-1:0] sum_x_nxt;
    logic [SUM_Y_W-1:0] sum_y_nxt;
    logic [CNT_W-1:0]   pixel_count_nxt;

    logic [CNT_W-1:0]   min_blob_pixels;
    logic [CNT_W-1:0]   locked_pixel_count;
    logic               in_valid_band;

    assign min_blob_pixels = 10'd96 + {min_blob_sw, 3'b0};
    assign in_valid_band = pix_y >= TOP_IGNORE_LINES;

    always_comb begin
        sum_x_nxt = sum_x;
        sum_y_nxt = sum_y;
        pixel_count_nxt = pixel_count;

        if (frame_start) begin
            sum_x_nxt = '0;
            sum_y_nxt = '0;
            pixel_count_nxt = '0;
        end else if (pix_valid && mask && in_valid_band) begin
            sum_x_nxt = sum_x + pix_x;
            sum_y_nxt = sum_y + pix_y;
            pixel_count_nxt = pixel_count + 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_x <= '0;
            sum_y <= '0;
            pixel_count <= '0;
            centroid_x <= IMG_W / 2;
            centroid_y <= IMG_H / 2;
            centroid_valid <= 1'b0;
            locked_pixel_count <= '0;
        end else begin
            sum_x <= sum_x_nxt;
            sum_y <= sum_y_nxt;
            pixel_count <= pixel_count_nxt;

            if (frame_start) begin
                if (pixel_count >= min_blob_pixels[CNT_W-1:0]) begin
                    centroid_x <= sum_x / pixel_count;
                    centroid_y <= sum_y / pixel_count;
                    centroid_valid <= 1'b1;
                    locked_pixel_count <= pixel_count;
                end else begin
                    centroid_valid <= 1'b0;
                    locked_pixel_count <= '0;
                end
            end
        end
    end

    assign mask_pixel_count = locked_pixel_count[16:0];

endmodule
