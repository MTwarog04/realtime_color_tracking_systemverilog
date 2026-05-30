
`timescale 1ns / 1ps


module smooth_tracker #(    parameter int IMG_W = 320,
    parameter int IMG_H = 240
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        frame_tick,
    input  logic        measurement_valid,
    input  logic [8:0]  measured_x,
    input  logic [7:0]  measured_y,
    input  logic [15:0] sw,
    output logic [8:0]  smooth_x,
    output logic [7:0]  smooth_y
);

    logic [2:0] shift_amt;
    logic signed [10:0] smooth_x_s;
    logic signed [9:0]  smooth_y_s;
    logic signed [10:0] delta_x;
    logic signed [9:0]  delta_y;

    assign shift_amt = 3'd2 + sw[7:5];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            smooth_x_s <= IMG_W / 2;
            smooth_y_s <= IMG_H / 2;
        end else if (frame_tick && measurement_valid) begin
            delta_x = $signed({1'b0, measured_x}) - smooth_x_s;
            delta_y = $signed({2'b0, measured_y}) - smooth_y_s;
            smooth_x_s <= smooth_x_s + (delta_x >>> shift_amt);
            smooth_y_s <= smooth_y_s + (delta_y >>> shift_amt);
        end
    end

    assign smooth_x = smooth_x_s[8:0];
    assign smooth_y = smooth_y_s[7:0];

endmodule
