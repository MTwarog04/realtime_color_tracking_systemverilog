// Autor: Mikolaj Twarog
`timescale 1ns / 1ps

module image_processing_tb;

    localparam int IMG_W = 320;
    localparam int IMG_H = 240;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [7:0] y = '0;
    logic [7:0] cb = '0;
    logic [7:0] cr = '0;
    logic line_valid = 1'b0;
    logic [4:0] cb_adjust = '0;
    logic [4:0] luma_adjust = '0;
    logic mask;

    logic pix_valid = 1'b0;
    logic frame_start = 1'b0;
    logic frame_end = 1'b0;
    logic [8:0] pix_x = '0;
    logic [7:0] pix_y = '0;
    logic [8:0] centroid_x;
    logic [7:0] centroid_y;
    logic centroid_valid;
    logic [16:0] mask_pixel_count;

    logic tracker_frame_tick = 1'b0;
    logic [2:0] smoothing_control = 3'd0;
    logic [8:0] smooth_x;
    logic [7:0] smooth_y;
    integer errors = 0;

    always #5 clk = ~clk;

    ycbcr_classifier classifier (
        .y,
        .cb,
        .cr,
        .line_valid,
        .cb_adjust,
        .luma_adjust,
        .mask
    );

    centroid_accumulator #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .TOP_IGNORE_LINES(0),
        .MIN_DIAMETER(4),
        .MAX_BLOBS(4),
        .CONNECT_GAP(1)
    ) centroid_dut (
        .clk,
        .rst_n,
        .pix_valid,
        .frame_start,
        .frame_end,
        .mask,
        .pix_x,
        .pix_y,
        .centroid_x,
        .centroid_y,
        .centroid_valid,
        .mask_pixel_count
    );

    smooth_tracker #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H)
    ) tracker_dut (
        .clk,
        .rst_n,
        .frame_tick(tracker_frame_tick),
        .measurement_valid(centroid_valid),
        .measured_x(centroid_x),
        .measured_y(centroid_y),
        .smoothing_control,
        .smooth_x,
        .smooth_y
    );

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("%s", message);
            errors = errors + 1;
        end
    endtask

    task automatic pulse_frame_start;
        begin
            @(negedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            #1;
            frame_start = 1'b0;
        end
    endtask

    task automatic pulse_frame_end;
        begin
            @(negedge clk);
            frame_end = 1'b1;
            @(posedge clk);
            #1;
            frame_end = 1'b0;
        end
    endtask

    task automatic send_blue_pixel(input integer x_pos, input integer y_pos);
        begin
            @(negedge clk);
            pix_x = x_pos;
            pix_y = y_pos;
            y = 8'd100;
            cb = 8'd80;
            cr = 8'd100;
            line_valid = 1'b1;
            pix_valid = 1'b1;
            @(posedge clk);
            #1;
            pix_valid = 1'b0;
        end
    endtask

    task automatic wait_for_evaluation;
        integer timeout;
        begin
            timeout = 0;
            while (centroid_dut.evaluation_active && timeout < 20) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(timeout < 20, "centroid evaluation timeout");
        end
    endtask

    integer x_pos;
    integer y_pos;

    initial begin
        // Direct classifier cases: disabled input, valid blue and rejection.
        y = 8'd100;
        cb = 8'd80;
        cr = 8'd100;
        line_valid = 1'b0;
        #1;
        check(!mask, "classifier ignored line_valid");

        line_valid = 1'b1;
        #1;
        check(mask, "typical blue pixel was rejected");

        cb = 8'd140;
        #1;
        check(!mask, "out-of-range chroma was accepted");

        cb = 8'd80;
        luma_adjust = 5'd31;
        #1;
        check(!mask, "luma adjustment did not raise threshold");
        luma_adjust = '0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check(smooth_x == IMG_W / 2 && smooth_y == IMG_H / 2,
              "smooth tracker reset position is incorrect");

        // A 5x5 compact object is accepted and its centroid is calculated.
        pulse_frame_start();
        for (y_pos = 8; y_pos <= 12; y_pos = y_pos + 1) begin
            for (x_pos = 10; x_pos <= 14; x_pos = x_pos + 1) begin
                send_blue_pixel(x_pos, y_pos);
            end
        end
        pix_valid = 1'b0;
        pulse_frame_end();
        wait_for_evaluation();
        check(centroid_valid, "valid compact object was rejected");
        check(centroid_x == 9'd12 && centroid_y == 8'd10,
              "centroid coordinates are incorrect");
        check(mask_pixel_count == 17'd25,
              "centroid pixel count is incorrect");

        // Smoothing control 0 means a 1/4 step toward the measurement.
        @(negedge clk);
        tracker_frame_tick = 1'b1;
        @(posedge clk);
        #1;
        tracker_frame_tick = 1'b0;
        check(smooth_x == 9'd123 && smooth_y == 8'd92,
              "smooth tracker step is incorrect");

        if (errors == 0) begin
            $display("image_processing_tb PASSED");
        end else begin
            $fatal(1, "image_processing_tb FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
