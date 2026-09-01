// Autor: Mikolaj Twarog
`timescale 1ns / 1ps

module pwm_generator_tb;

    localparam int CLK_HZ = 100_000;
    localparam int SERVO_HZ = 100;
    localparam int PERIOD_CYCLES = CLK_HZ / SERVO_HZ;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [7:0] duty = 8'h00;
    logic pwm_out;
    logic dir_out;
    integer errors = 0;

    always #5 clk = ~clk;

    pwm_generator #(
        .CLK_HZ(CLK_HZ),
        .SERVO_HZ(SERVO_HZ)
    ) dut (
        .clk,
        .rst_n,
        .duty,
        .pwm_out,
        .dir_out
    );

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("%s", message);
            errors = errors + 1;
        end
    endtask

    task automatic measure_pulse(
        input logic [7:0] requested_duty,
        input integer expected_high_cycles,
        input logic expected_direction
    );
        integer high_cycles;
        begin
            duty = requested_duty;

            // Duty is applied at a PWM period boundary.
            @(posedge clk);
            while (dut.counter != 0) @(posedge clk);
            #1;

            high_cycles = 0;
            repeat (PERIOD_CYCLES) begin
                if (pwm_out) high_cycles = high_cycles + 1;
                @(posedge clk);
                #1;
            end

            check(high_cycles == expected_high_cycles,
                  $sformatf("duty=%0d: pulse has %0d cycles, expected %0d",
                            $signed(requested_duty), high_cycles,
                            expected_high_cycles));
            check(dir_out == expected_direction,
                  $sformatf("duty=%0d: wrong direction output",
                            $signed(requested_duty)));
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // At 100 kHz: centre=150 cycles, range=100..200 cycles.
        measure_pulse(8'sd0,  150, 1'b0);
        measure_pulse(8'sd64, 175, 1'b0);
        measure_pulse(8'h80,  100, 1'b1);
        measure_pulse(8'h7f,  199, 1'b0);

        if (errors == 0) begin
            $display("pwm_generator_tb PASSED");
        end else begin
            $fatal(1, "pwm_generator_tb FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
