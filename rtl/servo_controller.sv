/* Copyright (C) 2025 AGH University of Krakow */

`timescale 1ns / 1ps


module servo_controller #(
    parameter int CENTER_X = 160,
    parameter int CENTER_Y = 120,
    parameter int KP = 1,
    parameter int DUTY_SHIFT = 1,
    parameter int DEAD_BAND_X = 4,
    parameter int DEAD_BAND_Y = 4,
    parameter int VALID_FRAMES_TO_MOVE = 2,
    parameter int MAX_STEP = 4,
    parameter bit PAN_REVERSE = 1'b0,
    parameter bit TILT_REVERSE = 1'b0
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

    localparam int VALID_CNT_W = (VALID_FRAMES_TO_MOVE < 2) ?
                                 1 : $clog2(VALID_FRAMES_TO_MOVE + 1);

    logic signed [10:0] err_x;
    logic signed [9:0]  err_y;
    logic signed [31:0] p_pan;
    logic signed [31:0] p_tilt;
    logic signed [31:0] pan_command;
    logic signed [31:0] tilt_command;

    logic signed [8:0] pan_s;
    logic signed [8:0] tilt_s;
    logic [VALID_CNT_W-1:0] valid_streak;

    function automatic logic signed [8:0] clamp_duty(
        input logic signed [31:0] value
    );
        begin
            if (value > 32'sd127) begin
                clamp_duty = 9'sd127;
            end else if (value < -32'sd128) begin
                clamp_duty = -9'sd128;
            end else begin
                clamp_duty = value[8:0];
            end
        end
    endfunction

    function automatic logic signed [31:0] make_step(
        input logic signed [31:0] proportional,
        input logic               reverse
    );
        logic signed [31:0] magnitude;
        logic signed [31:0] step_magnitude;
        logic               positive_direction;
        begin
            positive_direction = (proportional >= 0);
            magnitude = positive_direction ? proportional : -proportional;
            step_magnitude = magnitude >>> DUTY_SHIFT;

            // Keep tracking responsive close to the dead band, but prevent a
            // large image error from producing an abrupt servo movement.
            if (step_magnitude < 32'sd1) begin
                step_magnitude = 32'sd1;
            end else if (step_magnitude > MAX_STEP) begin
                step_magnitude = MAX_STEP;
            end

            if (reverse) begin
                positive_direction = !positive_direction;
            end
            make_step = positive_direction ? step_magnitude : -step_magnitude;
        end
    endfunction

    always_comb begin
        err_x = $signed({1'b0, target_x}) - CENTER_X;
        err_y = $signed({2'b0, target_y}) - CENTER_Y;

        // The products are deliberately 32-bit so that multiplication cannot
        // wrap and reverse the requested servo direction.
        p_pan = err_x * KP;
        p_tilt = err_y * KP;
        pan_command = make_step(p_pan, PAN_REVERSE);
        tilt_command = make_step(p_tilt, TILT_REVERSE);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pan_s <= '0;
            tilt_s <= '0;
            valid_streak <= '0;
        end else if (frame_tick) begin
            if (!target_valid) begin
                // With no target both outputs retain the last valid position.
                valid_streak <= '0;
            end else begin
                if (valid_streak < VALID_FRAMES_TO_MOVE) begin
                    valid_streak <= valid_streak + 1'b1;
                end

                // A single false detection is not enough to move either servo.
                if ((VALID_FRAMES_TO_MOVE <= 1) ||
                    (valid_streak >= VALID_FRAMES_TO_MOVE - 1)) begin
                    if ((err_x > DEAD_BAND_X) || (err_x < -DEAD_BAND_X)) begin
                        pan_s <= clamp_duty($signed(pan_s) + pan_command);
                    end
                    if ((err_y > DEAD_BAND_Y) || (err_y < -DEAD_BAND_Y)) begin
                        tilt_s <= clamp_duty($signed(tilt_s) + tilt_command);
                    end
                end
            end
        end
    end

    assign pan_duty = pan_s[7:0];
    assign tilt_duty = tilt_s[7:0];

endmodule
