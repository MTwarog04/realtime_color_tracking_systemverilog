/* Copyright (C) 2025 AGH University of Krakow */
`timescale 1ns / 1ps

module servo_controller #(
    parameter int CENTER_X   = 160,
    parameter int CENTER_Y   = 120,
    parameter int KP         = 16,
    parameter int DUTY_SHIFT = 1
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        frame_tick,
    input  logic        target_valid,
    input  logic [8:0]  target_x,
    input  logic [7:0]  target_y,
    output logic [7:0]  pan_duty,
    output logic [7:0]  tilt_duty
);

    logic signed [10:0] err_x;
    logic signed [9:0]  err_y;
    logic signed [10:0] p_pan;
    logic signed [9:0]  p_tilt;

    logic signed [8:0] pan_s;
    logic signed [8:0] tilt_s;

    function automatic logic signed [8:0] clamp_duty(input logic signed [10:0] value);
        begin
            if (value > 11'sd127) begin
                clamp_duty = 9'sd127;
            end else if (value < -11'sd128) begin
                clamp_duty = -9'sd128;
            end else begin
                clamp_duty = value[8:0];
            end
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pan_s <= '0;
            tilt_s <= '0;
        end else if (frame_tick && target_valid) begin
            err_x = $signed({1'b0, target_x}) - CENTER_X;
            err_y = $signed({2'b0, target_y}) - CENTER_Y;
            p_pan = err_x * KP;
            p_tilt = err_y * KP;
            pan_s <= clamp_duty(p_pan >>> DUTY_SHIFT);
            tilt_s <= clamp_duty(p_tilt >>> DUTY_SHIFT);
        end
    end

    assign pan_duty = pan_s[7:0];
    assign tilt_duty = tilt_s[7:0];

endmodule
