// Autor: Maciej Nowak
`timescale 1ns / 1ps

/**
 * Servo-side application top.
 *
 * A valid UART packet becomes frame_tick for the existing servo controller,
 * so the two-board setup preserves the single-board controller behaviour.
 */
module top_servo (
    input  logic       clk,
    input  logic       rst,
    input  logic       uart_rx,
    output logic [3:0] led,
    output logic       servo_pan_pwm,
    output logic       servo_tilt_pwm
);

    localparam int SYS_CLK_HZ = 40_000_000;

    logic rst_n;
    logic packet_strobe;
    logic target_valid;
    logic [8:0] target_x;
    logic [7:0] target_y;
    logic link_alive;
    logic packet_error;
    logic packet_error_seen;
    logic [7:0] pan_duty;
    logic [7:0] tilt_duty;
    logic pan_dir;
    logic tilt_dir;

    assign rst_n = ~rst;

    tracking_uart_rx #(
        .CLK_HZ(SYS_CLK_HZ),
        .BAUD_RATE(100_000)
    ) u_tracking_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .packet_strobe(packet_strobe),
        .target_valid(target_valid),
        .target_x(target_x),
        .target_y(target_y),
        .link_alive(link_alive),
        .packet_error(packet_error)
    );

    servo_controller #(
        .CENTER_X(160),
        .CENTER_Y(120),
        .DEAD_BAND_X(2),
        .DEAD_BAND_Y(2),
        .VALID_FRAMES_TO_MOVE(2),
        .PAN_MAX_STEP(12),
        .TILT_MAX_STEP(8),
        // 9 cm camera-to-laser offset, calibrated for roughly 1 m distance.
        .PAN_HOME_OFFSET(-7),
        // Startup calibration goes to the second JXADC signal pin (L3).
        .TILT_STARTUP_POSITION(-60),
        .PAN_POSITION_LIMIT(127),
        .TILT_POSITION_LIMIT(60),
        .PAN_REVERSE(1'b0),
        .TILT_REVERSE(1'b0)
    ) u_servo_controller (
        .clk(clk),
        .rst_n(rst_n),
        .frame_tick(packet_strobe),
        .target_valid(target_valid),
        .target_x(target_x),
        .target_y(target_y),
        .pan_duty(pan_duty),
        .tilt_duty(tilt_duty)
    );

    pwm_generator #(
        .CLK_HZ(SYS_CLK_HZ)
    ) u_pwm_pan (
        .clk(clk),
        .rst_n(rst_n),
        .duty(pan_duty),
        .pwm_out(servo_pan_pwm),
        .dir_out(pan_dir)
    );

    pwm_generator #(
        .CLK_HZ(SYS_CLK_HZ)
    ) u_pwm_tilt (
        .clk(clk),
        .rst_n(rst_n),
        .duty(tilt_duty),
        .pwm_out(servo_tilt_pwm),
        .dir_out(tilt_dir)
    );

    // LED0: at least one valid packet arrived recently.
    // LED1: a complete packet with bad CRC/flags was observed since reset.
    // LED2: the last received tracking result contains a valid target.
    // LED3: UART receiver is currently idle-high (basic wiring indication).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            packet_error_seen <= 1'b0;
        end else if (packet_error) begin
            packet_error_seen <= 1'b1;
        end
    end

    assign led[0] = link_alive;
    assign led[1] = packet_error_seen;
    assign led[2] = target_valid;
    assign led[3] = uart_rx;

endmodule
