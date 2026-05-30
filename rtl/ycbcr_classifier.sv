
`timescale 1ns / 1ps

module ycbcr_classifier #(
    parameter int TOP_IGNORE_LINES = 30
)(
    input  logic [7:0] y,
    input  logic [7:0] cb,
    input  logic [7:0] cr,
    input  logic [7:0] pix_y,
    input  logic [15:0] sw,
    output logic       mask
);

    localparam logic [7:0] CR_MAX = 8'd152;

    logic [7:0] cb_min_dist;
    logic [7:0] y_min;
    logic [7:0] blue_dist;
    logic       in_valid_band;

    assign cb_min_dist = (sw[4:0] >= 5'd30) ? 8'd2 : (8'd32 - {3'b0, sw[4:0]});
    assign y_min = 8'd16 + {sw[14:10], 2'b00};
    assign in_valid_band = pix_y >= TOP_IGNORE_LINES;
    assign blue_dist = (cb <= 8'd128) ? (8'd128 - cb) : 8'd0;

    always_comb begin
        mask = 1'b0;
        if (in_valid_band &&
            (blue_dist >= cb_min_dist) &&
            (cr <= CR_MAX) &&
            (y >= y_min)) begin
            mask = 1'b1;
        end
    end

endmodule
