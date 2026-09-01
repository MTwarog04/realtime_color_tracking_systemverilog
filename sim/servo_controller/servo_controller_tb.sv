// Autor: Mikolaj Twarog
`timescale 1ns / 1ps

module servo_controller_tb;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic frame_tick = 1'b0;
    logic target_valid = 1'b0;
    logic [8:0] target_x = '0;
    logic [7:0] target_y = '0;
    logic [7:0] pan_duty;
    logic [7:0] tilt_duty;
    integer errors = 0;

    always #5 clk = ~clk;

    servo_controller #(
        .CENTER_X(160),
        .CENTER_Y(120),
        .DEAD_BAND_X(4),
        .DEAD_BAND_Y(4),
        .VALID_FRAMES_TO_MOVE(2),
        .PAN_MAX_STEP(4),
        .TILT_MAX_STEP(3),
        .PAN_HOME_OFFSET(5),
        .TILT_STARTUP_POSITION(-3),
        .PAN_POSITION_LIMIT(127),
        .TILT_POSITION_LIMIT(127)
    ) dut (
        .clk,
        .rst_n,
        .frame_tick,
        .target_valid,
        .target_x,
        .target_y,
        .pan_duty,
        .tilt_duty
    );

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("%s", message);
            errors = errors + 1;
        end
    endtask

    task automatic send_frame(
        input logic valid,
        input logic [8:0] x,
        input logic [7:0] y
    );
        begin
            @(negedge clk);
            target_valid = valid;
            target_x = x;
            target_y = y;
            frame_tick = 1'b1;
            @(posedge clk);
            #1;
            frame_tick = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;
        check($signed(pan_duty) == 5, "wrong pan startup position");
        check($signed(tilt_duty) == -3, "wrong tilt startup position");
        rst_n = 1'b1;

        // One detection is deliberately insufficient to move the servos.
        send_frame(1'b1, 9'd320, 8'd240);
        check($signed(pan_duty) == 5, "pan moved after one valid frame");
        check($signed(tilt_duty) == -3, "tilt moved after one valid frame");

        send_frame(1'b1, 9'd320, 8'd240);
        check($signed(pan_duty) == 9, "pan slew limit is incorrect");
        check($signed(tilt_duty) == 0, "tilt slew limit is incorrect");

        // Missing target holds position and clears the valid streak.
        send_frame(1'b0, 9'd0, 8'd0);
        check($signed(pan_duty) == 9, "pan did not hold without target");
        check($signed(tilt_duty) == 0, "tilt did not hold without target");

        // A centred target returns to the mechanical alignment positions.
        send_frame(1'b1, 9'd160, 8'd120);
        check($signed(pan_duty) == 9, "valid streak was not reset");
        send_frame(1'b1, 9'd160, 8'd120);
        check($signed(pan_duty) == 5, "pan did not return to home offset");
        check($signed(tilt_duty) == 0, "tilt centre is incorrect");

        // Repeated extreme coordinates must stop at configured limits.
        repeat (50) send_frame(1'b1, 9'd0, 8'd0);
        check($signed(pan_duty) == -122,
              "pan target or mechanical offset is incorrect at the limit");
        check($signed(tilt_duty) == -127,
              "tilt did not clamp at the negative limit");

        if (errors == 0) begin
            $display("servo_controller_tb PASSED");
        end else begin
            $fatal(1, "servo_controller_tb FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
