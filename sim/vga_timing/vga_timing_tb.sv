// Autor: Mikolaj Twarog
`timescale 1ns / 1ps

module vga_timing_tb;

    import vga_pkg::*;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [10:0] vcount;
    logic vsync;
    logic vblnk;
    logic [10:0] hcount;
    logic hsync;
    logic hblnk;
    integer errors = 0;
    integer exp_h;
    integer exp_v;
    integer cycle_no;

    always #5 clk = ~clk;

    vga_timing dut (
        .clk,
        .rst_n,
        .vcount,
        .vsync,
        .vblnk,
        .hcount,
        .hsync,
        .hblnk
    );

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            if (errors < 20) $error("%s", message);
            errors = errors + 1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        #1;
        check(hcount == 0 && vcount == 0, "VGA counters did not reset");
        check(hsync == ~HSYNC_POLARITY && vsync == ~VSYNC_POLARITY,
              "VGA sync reset polarity is incorrect");

        @(negedge clk);
        rst_n = 1'b1;
        exp_h = 0;
        exp_v = 0;

        // Check every pixel clock across one complete 1024x768 frame.
        for (cycle_no = 0;
             cycle_no < HOR_TOTAL_TIME * VER_TOTAL_TIME;
             cycle_no = cycle_no + 1) begin
            @(posedge clk);
            #1;

            if (exp_h == HOR_TOTAL_TIME - 1) begin
                exp_h = 0;
                if (exp_v == VER_TOTAL_TIME - 1) exp_v = 0;
                else exp_v = exp_v + 1;
            end else begin
                exp_h = exp_h + 1;
            end

            check(hcount == exp_h && vcount == exp_v,
                  $sformatf("counter mismatch at cycle %0d", cycle_no));
            check(hblnk == ((exp_h >= HOR_BLANK_START) &&
                            (exp_h < HOR_BLANK_START + HOR_BLANK_TIME)),
                  $sformatf("horizontal blank mismatch at h=%0d", exp_h));
            check(hsync == (((exp_h >= HOR_SYNC_START) &&
                             (exp_h < HOR_SYNC_START + HOR_SYNC_TIME)) ?
                            HSYNC_POLARITY : ~HSYNC_POLARITY),
                  $sformatf("horizontal sync mismatch at h=%0d", exp_h));
            check(vblnk == ((exp_v >= VER_BLANK_START) &&
                            (exp_v < VER_BLANK_START + VER_BLANK_TIME)),
                  $sformatf("vertical blank mismatch at v=%0d", exp_v));
            check(vsync == (((exp_v >= VER_SYNC_START) &&
                             (exp_v < VER_SYNC_START + VER_SYNC_TIME)) ?
                            VSYNC_POLARITY : ~VSYNC_POLARITY),
                  $sformatf("vertical sync mismatch at v=%0d", exp_v));
        end

        check(hcount == 0 && vcount == 0,
              "VGA counters did not wrap after complete frame");

        if (errors == 0) begin
            $display("vga_timing_tb PASSED");
        end else begin
            $fatal(1, "vga_timing_tb FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
