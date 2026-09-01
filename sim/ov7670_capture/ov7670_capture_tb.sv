// Autor: Mikolaj Twarog
`timescale 1ns / 1ps

module ov7670_capture_tb;

    localparam int H_RES = 8;
    localparam int V_RES = 4;
    localparam int OUT_W = 4;
    localparam int OUT_H = 2;

    logic pclk = 1'b0;
    logic rst_n = 1'b0;
    logic chroma_order = 1'b0;
    logic vsync = 1'b0;
    logic href = 1'b0;
    logic [7:0] d = '0;
    logic pix_valid;
    logic frame_start;
    logic frame_end;
    logic [8:0] pix_x;
    logic [7:0] pix_y;
    logic [7:0] pix_y_luma;
    logic [7:0] pix_cb;
    logic [7:0] pix_cr;

    integer errors = 0;
    integer output_count = 0;
    integer frame_start_count = 0;
    integer frame_end_count = 0;
    integer test_base = 0;
    logic monitor_enable = 1'b0;

    always #5 pclk = ~pclk;

    ov7670_capture #(
        .H_RES(H_RES),
        .V_RES(V_RES),
        .OUT_W(OUT_W),
        .OUT_H(OUT_H)
    ) dut (
        .pclk,
        .rst_n,
        .chroma_order,
        .vsync,
        .href,
        .d,
        .pix_valid,
        .frame_start,
        .frame_end,
        .pix_x,
        .pix_y,
        .pix_y_luma,
        .pix_cb,
        .pix_cr
    );

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("%s", message);
            errors = errors + 1;
        end
    endtask

    always @(posedge pclk) begin
        #1;
        if (monitor_enable && pix_valid) begin
            check(pix_x == output_count % OUT_W,
                  $sformatf("wrong camera X for output %0d", output_count));
            check(pix_y == output_count / OUT_W,
                  $sformatf("wrong camera Y for output %0d", output_count));
            check(pix_y_luma == test_base +
                  ((output_count / OUT_W) * 40) +
                  ((output_count % OUT_W) * 2),
                  $sformatf("wrong luma for output %0d", output_count));
            check(pix_cb == 8'h60, "wrong Cb value from camera stream");
            check(pix_cr == 8'h90, "wrong Cr value from camera stream");
            if (frame_start) frame_start_count = frame_start_count + 1;
            if (frame_end) frame_end_count = frame_end_count + 1;
            output_count = output_count + 1;
        end
    end

    task automatic send_byte(input logic [7:0] value);
        begin
            d = value;
            @(posedge pclk);
            #1;
        end
    endtask

    task automatic send_line(input integer row, input integer base_value);
        integer pair_no;
        integer y0_value;
        begin
            @(negedge pclk);
            href = 1'b1;
            for (pair_no = 0; pair_no < H_RES / 2;
                 pair_no = pair_no + 1) begin
                y0_value = base_value + row * 20 + pair_no * 2;
                if (!chroma_order) begin
                    send_byte(y0_value);
                    send_byte(8'h60);
                    send_byte(y0_value + 1);
                    send_byte(8'h90);
                end else begin
                    send_byte(8'h60);
                    send_byte(y0_value);
                    send_byte(8'h90);
                    send_byte(y0_value + 1);
                end
            end
            @(negedge pclk);
            href = 1'b0;
            repeat (2) @(posedge pclk);
        end
    endtask

    task automatic run_frame(input logic order, input integer base_value);
        integer row;
        begin
            rst_n = 1'b0;
            href = 1'b0;
            vsync = 1'b0;
            repeat (3) @(posedge pclk);
            chroma_order = order;
            rst_n = 1'b1;
            test_base = base_value;
            output_count = 0;
            frame_start_count = 0;
            frame_end_count = 0;
            monitor_enable = 1'b1;

            // VSYNC arms the start-of-frame marker and resets coordinates.
            @(negedge pclk);
            vsync = 1'b1;
            repeat (2) @(posedge pclk);
            @(negedge pclk);
            vsync = 1'b0;

            for (row = 0; row < V_RES; row = row + 1) begin
                send_line(row, base_value);
            end
            repeat (3) @(posedge pclk);
            monitor_enable = 1'b0;

            check(output_count == OUT_W * OUT_H,
                  $sformatf("order=%0d: wrong output pixel count", order));
            check(frame_start_count == 1,
                  $sformatf("order=%0d: frame_start count is not one", order));
            check(frame_end_count == 1,
                  $sformatf("order=%0d: frame_end count is not one", order));
        end
    endtask

    initial begin
        run_frame(1'b0, 20);
        run_frame(1'b1, 80);

        if (errors == 0) begin
            $display("ov7670_capture_tb PASSED");
        end else begin
            $fatal(1, "ov7670_capture_tb FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
