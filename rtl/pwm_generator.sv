/* Copyright (C) 2025 AGH University of Krakow */
`timescale 1ns / 1ps

module pwm_generator #(
    parameter int CLK_HZ = 40_000_000,
    parameter int SERVO_HZ = 50
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] duty,
    output logic       pwm_out,
    output logic       dir_out
);

    localparam int PERIOD_CYCLES = CLK_HZ / SERVO_HZ;
    localparam int CENTER_CYCLES = (CLK_HZ / 1000) * 3 / 2;
    localparam int HALF_RANGE    = CLK_HZ / 2000;
    localparam int MIN_CYCLES    = CENTER_CYCLES - HALF_RANGE;
    localparam int MAX_CYCLES    = CENTER_CYCLES + HALF_RANGE;
    localparam int CNT_W         = $clog2(PERIOD_CYCLES + 1);

    logic [CNT_W-1:0] counter;
    logic [CNT_W-1:0] pulse_limit;
    logic signed [31:0] pulse_s;

    assign dir_out = duty[7];

    always_comb begin
        pulse_s = CENTER_CYCLES + ($signed(duty) * HALF_RANGE) / 32'sd128;
        if (pulse_s < MIN_CYCLES) begin
            pulse_limit = MIN_CYCLES;
        end else if (pulse_s > MAX_CYCLES) begin
            pulse_limit = MAX_CYCLES;
        end else begin
            pulse_limit = pulse_s[CNT_W-1:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= '0;
            pwm_out <= 1'b0;
        end else begin
            if (counter >= PERIOD_CYCLES - 1) begin
                counter <= '0;
            end else begin
                counter <= counter + 1'b1;
            end
            pwm_out <= (counter < pulse_limit);
        end
    end

endmodule
