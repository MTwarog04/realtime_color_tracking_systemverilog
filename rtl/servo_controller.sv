/* Copyright (C) 2025 AGH University of Krakow */

`timescale 1ns / 1ps


module servo_controller #(
    parameter int CENTER_X = 160,
    parameter int CENTER_Y = 120,
    parameter int DEAD_BAND_X = 4,
    parameter int DEAD_BAND_Y = 4,
    parameter int VALID_FRAMES_TO_MOVE = 2,
    parameter int PAN_MAX_STEP = 4,
    parameter int TILT_MAX_STEP = 4,
    parameter int PAN_POSITION_LIMIT = 127,
    parameter int TILT_POSITION_LIMIT = 127,
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
    logic signed [31:0] pan_target;
    logic signed [31:0] tilt_target;

    logic signed [8:0] pan_s;
    logic signed [8:0] tilt_s;
    logic [VALID_CNT_W-1:0] valid_streak;

    function automatic logic signed [8:0] clamp_position(
        input logic signed [31:0] value,
        input int                   position_limit
    );
        begin
            if (value > position_limit) begin
                clamp_position = position_limit;
            end else if (value < -position_limit) begin
                clamp_position = -position_limit;
            end else begin
                clamp_position = value[8:0];
            end
        end
    endfunction

    function automatic logic signed [8:0] slew_position(
        input logic signed [8:0]  current_position,
        input logic signed [31:0] target_position,
        input int                   max_step,
        input int                   position_limit
    );
        logic signed [31:0] current_wide;
        logic signed [31:0] limited_target;
        logic signed [31:0] next_position;
        begin
            current_wide = current_position;

            if (target_position > position_limit) begin
                limited_target = position_limit;
            end else if (target_position < -position_limit) begin
                limited_target = -position_limit;
            end else begin
                limited_target = target_position;
            end

            if (limited_target > (current_wide + max_step)) begin
                next_position = current_wide + max_step;
            end else if (limited_target < (current_wide - max_step)) begin
                next_position = current_wide - max_step;
            end else begin
                next_position = limited_target;
            end

            slew_position = clamp_position(next_position, position_limit);
        end
    endfunction

    always_comb begin
        err_x = $signed({1'b0, target_x}) - CENTER_X;
        err_y = $signed({2'b0, target_y}) - CENTER_Y;

        // The camera is fixed, so every image coordinate maps directly to one
        // servo position. MAX_STEP only limits how fast that position changes.
        if ((err_x <= DEAD_BAND_X) && (err_x >= -DEAD_BAND_X)) begin
            pan_target = 32'sd0;
        end else begin
            pan_target = (err_x * PAN_POSITION_LIMIT) / CENTER_X;
        end

        if ((err_y <= DEAD_BAND_Y) && (err_y >= -DEAD_BAND_Y)) begin
            tilt_target = 32'sd0;
        end else begin
            tilt_target = (err_y * TILT_POSITION_LIMIT) / CENTER_Y;
        end

        if (PAN_REVERSE) pan_target = -pan_target;
        if (TILT_REVERSE) tilt_target = -tilt_target;
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
                    pan_s <= slew_position(
                        pan_s, pan_target, PAN_MAX_STEP, PAN_POSITION_LIMIT
                    );
                    tilt_s <= slew_position(
                        tilt_s, tilt_target, TILT_MAX_STEP, TILT_POSITION_LIMIT
                    );
                end
            end
        end
    end

    assign pan_duty = pan_s[7:0];
    assign tilt_duty = tilt_s[7:0];

endmodule
