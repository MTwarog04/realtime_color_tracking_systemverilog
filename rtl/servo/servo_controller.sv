/* Autorzy: Mikołaj Twaróg, Maciej Nowak */
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
    parameter int PAN_HOME_OFFSET = 0,
    parameter int TILT_STARTUP_POSITION = 0,
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

    /* The camera dimensions and servo limits are parameters, but the */
    /* reciprocal factors are calculated during elaboration.  This keeps the */
    /* coordinate mapping out of the slow, inferred hardware divider. */
    localparam int RECIP_SHIFT = 16;
    localparam logic [16:0] PAN_SCALE =
        ((PAN_POSITION_LIMIT * (1 << RECIP_SHIFT)) + CENTER_X - 1) /
        CENTER_X;
    localparam logic [16:0] TILT_SCALE =
        ((TILT_POSITION_LIMIT * (1 << RECIP_SHIFT)) + CENTER_Y - 1) /
        CENTER_Y;

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

    function automatic logic signed [31:0] scale_position(
        input logic signed [10:0] value,
        input logic        [16:0] scale
    );
        logic        negative;
        logic [10:0] magnitude;
        logic [27:0] product;
        logic [11:0] quotient;
        begin
            negative = (value < 0);
            magnitude = negative ? $unsigned(-value) : $unsigned(value);
            product = magnitude * scale;
            quotient = product >> RECIP_SHIFT;

            /* Signed division truncates toward zero.  Shift the magnitude */
            /* first and restore the sign to retain that behaviour. */
            if (negative) begin
                scale_position = -$signed({1'b0, quotient});
            end else begin
                scale_position = $signed({1'b0, quotient});
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

        /* The camera is fixed, so every image coordinate maps directly to one */
        /* servo position. MAX_STEP only limits how fast that position changes. */
        if ((err_x <= DEAD_BAND_X) && (err_x >= -DEAD_BAND_X)) begin
            pan_target = 32'sd0;
        end else begin
            pan_target = scale_position(err_x, PAN_SCALE);
        end

        if ((err_y <= DEAD_BAND_Y) && (err_y >= -DEAD_BAND_Y)) begin
            tilt_target = 32'sd0;
        end else begin
            tilt_target = scale_position({err_y[9], err_y}, TILT_SCALE);
        end

        if (PAN_REVERSE) begin
            pan_target = -pan_target;
        end
        /* Permanent mechanical alignment of the laser relative to the camera. */
        /* It is applied to every target, not only while the board resets. */
        pan_target = pan_target + PAN_HOME_OFFSET;
        if (TILT_REVERSE) begin
            tilt_target = -tilt_target;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pan_s <= clamp_position(PAN_HOME_OFFSET, PAN_POSITION_LIMIT);
            tilt_s <= clamp_position(TILT_STARTUP_POSITION, TILT_POSITION_LIMIT);
            valid_streak <= '0;
        end else if (frame_tick) begin
            if (!target_valid) begin
                /* With no target both outputs retain the last valid position. */
                valid_streak <= '0;
            end else begin
                if (valid_streak < VALID_FRAMES_TO_MOVE) begin
                    valid_streak <= valid_streak + 1'b1;
                end

                /* A single false detection is not enough to move either servo. */
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
