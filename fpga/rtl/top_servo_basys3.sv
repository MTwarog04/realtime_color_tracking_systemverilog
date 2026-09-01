/**
 * Basys 3 top level for the servo node.
 *
 * The board receives tracking packets through uart_rx and creates the two
 * 50 Hz PWM outputs used by the pan and tilt servos.
 */
module top_servo_basys3 (
    input  wire       clk,
    input  wire       btnC,
    input  wire       uart_rx,
    output wire [3:0] led,
    output wire       servo_pan_pwm,
    output wire       servo_tilt_pwm
);

    timeunit 1ns;
    timeprecision 1ps;

    wire clk_in;
    wire clk_fb;
    wire clk_ss;
    wire clk_out;
    wire locked;
    wire clk_40mhz;

    (* KEEP = "TRUE" *)
    (* ASYNC_REG = "TRUE" *)
    logic [7:0] safe_start = '0;

    IBUF clk_ibuf (
        .I(clk),
        .O(clk_in)
    );

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.000),
        .CLKFBOUT_MULT_F(10.000),
        .CLKOUT0_DIVIDE_F(25.000)
    ) clk_in_mmcme2 (
        .CLKIN1(clk_in),
        .CLKOUT0(clk_out),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clk_fb),
        .CLKFBOUTB(),
        .CLKFBIN(clk_fb),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFH clk_out_bufh (
        .I(clk_out),
        .O(clk_ss)
    );

    always_ff @(posedge clk_ss) begin
        safe_start <= {safe_start[6:0], locked};
    end

    BUFGCE #(
        .SIM_DEVICE("7SERIES")
    ) clk_out_bufgce (
        .I(clk_out),
        .CE(safe_start[7]),
        .O(clk_40mhz)
    );

    top_servo u_top_servo (
        .clk(clk_40mhz),
        // Keep the servo controller in reset until the generated clock is
        // stable, so TILT_STARTUP_POSITION is applied after every power-up.
        .rst(btnC | ~locked),
        .uart_rx(uart_rx),
        .led(led),
        .servo_pan_pwm(servo_pan_pwm),
        .servo_tilt_pwm(servo_tilt_pwm)
    );

endmodule
