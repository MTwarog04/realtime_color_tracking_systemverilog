/* Autorzy: Mikołaj Twaróg, Maciej Nowak */
`timescale 1ns / 1ps

module ov7670_capture #(
    parameter int H_RES = 640,
    parameter int V_RES = 480,
    parameter int OUT_W = 320,
    parameter int OUT_H = 240
)(
    input  logic       pclk,
    input  logic       rst_n,
    input  logic       chroma_order,
    input  logic       vsync,
    input  logic       href,
    input  logic [7:0] d,
    output logic       pix_valid,
    output logic       frame_start,
    output logic       frame_end,
    output logic [8:0] pix_x,
    output logic [7:0] pix_y,
    output logic [7:0] pix_y_luma,
    output logic [7:0] pix_cb,
    output logic [7:0] pix_cr
);

    localparam int DOWNSAMPLE = 2;
    localparam int CROP_W = OUT_W * DOWNSAMPLE;
    localparam int CROP_H = OUT_H * DOWNSAMPLE;
    localparam int START_X = (H_RES - CROP_W) / 2;
    localparam int START_Y = (V_RES - CROP_H) / 2;

    logic [9:0] x_cnt;
    logic [9:0] y_cnt;
    logic [1:0] byte_idx;
    logic [7:0] y_a;
    logic [7:0] cb_val;
    logic       prev_href;
    logic       sof_pending;

    logic in_crop;
    logic emit_pixel;
    logic [9:0] pair_x;
    logic pair_in_crop;
    logic emit_pair_pixel;

    assign in_crop = (x_cnt >= START_X) && (x_cnt < START_X + CROP_W) &&
                     (y_cnt >= START_Y) && (y_cnt < START_Y + CROP_H);
    assign emit_pixel = in_crop && (x_cnt[0] == 1'b0) && (y_cnt[0] == 1'b0);

    assign pair_x = (x_cnt == 0) ? '0 : (x_cnt - 1'b1);
    assign pair_in_crop = (pair_x >= START_X) && (pair_x < START_X + CROP_W) &&
                          (y_cnt >= START_Y) && (y_cnt < START_Y + CROP_H);
    assign emit_pair_pixel = (x_cnt != 0) && pair_in_crop &&
                             (pair_x[0] == 1'b0) && (y_cnt[0] == 1'b0);

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            x_cnt <= '0;
            y_cnt <= '0;
            byte_idx <= '0;
            y_a <= '0;
            cb_val <= '0;
            prev_href <= 1'b0;
            sof_pending <= 1'b1;
            pix_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;
            pix_x <= '0;
            pix_y <= '0;
            pix_y_luma <= '0;
            pix_cb <= '0;
            pix_cr <= '0;
        end else begin
            prev_href <= href;

            pix_valid <= 1'b0;
            frame_start <= 1'b0;
            frame_end <= 1'b0;

            if (vsync) begin
                x_cnt <= '0;
                y_cnt <= '0;
                byte_idx <= '0;
                sof_pending <= 1'b1;
            end else begin
                if (href && !prev_href) begin
                    byte_idx <= '0;
                    x_cnt <= '0;
                end

                if (href) begin
                    if (chroma_order == 1'b0) begin
                        case (byte_idx)
                            2'd0: y_a <= d;
                            2'd1: cb_val <= d;
                            2'd2: begin
                                x_cnt <= x_cnt + 1'b1;
                            end
                            2'd3: begin
                                if (emit_pair_pixel) begin
                                    pix_valid <= 1'b1;
                                    pix_y_luma <= y_a;
                                    pix_cb <= cb_val;
                                    pix_cr <= d;
                                    pix_x <= (pair_x - START_X) >> 1;
                                    pix_y <= (y_cnt - START_Y) >> 1;

                                    if (sof_pending) begin
                                        frame_start <= 1'b1;
                                        sof_pending <= 1'b0;
                                    end

                                    if ((pair_x == START_X + CROP_W - DOWNSAMPLE) &&
                                        (y_cnt == START_Y + CROP_H - DOWNSAMPLE)) begin
                                        frame_end <= 1'b1;
                                    end
                                end
                                x_cnt <= x_cnt + 1'b1;
                            end
                        endcase
                    end else begin
                        case (byte_idx)
                            2'd0: cb_val <= d;
                            2'd1: y_a <= d;
                            2'd2: begin
                                if (emit_pixel) begin
                                    pix_valid <= 1'b1;
                                    pix_y_luma <= y_a;
                                    pix_cb <= cb_val;
                                    pix_cr <= d;
                                    pix_x <= (x_cnt - START_X) >> 1;
                                    pix_y <= (y_cnt - START_Y) >> 1;

                                    if (sof_pending) begin
                                        frame_start <= 1'b1;
                                        sof_pending <= 1'b0;
                                    end

                                    if ((x_cnt == START_X + CROP_W - DOWNSAMPLE) &&
                                        (y_cnt == START_Y + CROP_H - DOWNSAMPLE)) begin
                                        frame_end <= 1'b1;
                                    end
                                end
                                x_cnt <= x_cnt + 1'b1;
                            end
                            2'd3: begin
                                x_cnt <= x_cnt + 1'b1;
                            end
                        endcase
                    end

                    if (byte_idx == 2'd3) begin
                        byte_idx <= '0;
                    end else begin
                        byte_idx <= byte_idx + 1'b1;
                    end
                end

                if (!href && prev_href) begin
                    y_cnt <= y_cnt + 1'b1;
                end
            end
        end
    end

endmodule
