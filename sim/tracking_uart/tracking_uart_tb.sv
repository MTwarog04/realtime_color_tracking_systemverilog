// Autor: Mikolaj Twarog
`timescale 1ns / 1ps

module tracking_uart_tb;

    import tracking_uart_pkg::*;

    localparam int CLK_HZ = 1_000_000;
    localparam int BAUD_RATE = 100_000;
    localparam int CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam int LINK_TIMEOUT_CLKS = 120;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic frame_tick = 1'b0;
    logic tx_target_valid = 1'b0;
    logic [8:0] tx_target_x = '0;
    logic [7:0] tx_target_y = '0;
    logic tx;
    logic busy;
    logic frame_dropped;

    logic manual_mode = 1'b0;
    logic manual_rx = 1'b1;
    logic packet_strobe;
    logic rx_target_valid;
    logic [8:0] rx_target_x;
    logic [7:0] rx_target_y;
    logic link_alive;
    logic packet_error;
    logic packet_error_seen = 1'b0;
    wire uart_line = manual_mode ? manual_rx : tx;
    integer errors = 0;

    always #5 clk = ~clk;

    tracking_uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) tx_dut (
        .clk,
        .rst_n,
        .frame_tick,
        .target_valid(tx_target_valid),
        .target_x(tx_target_x),
        .target_y(tx_target_y),
        .tx,
        .busy,
        .frame_dropped
    );

    tracking_uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD_RATE(BAUD_RATE),
        .LINK_TIMEOUT_CLKS(LINK_TIMEOUT_CLKS)
    ) rx_dut (
        .clk,
        .rst_n,
        .rx(uart_line),
        .packet_strobe,
        .target_valid(rx_target_valid),
        .target_x(rx_target_x),
        .target_y(rx_target_y),
        .link_alive,
        .packet_error
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) packet_error_seen <= 1'b0;
        else if (packet_error) packet_error_seen <= 1'b1;
    end

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("%s", message);
            errors = errors + 1;
        end
    endtask

    task automatic pulse_frame;
        begin
            @(negedge clk);
            frame_tick = 1'b1;
            @(posedge clk);
            #1;
            frame_tick = 1'b0;
        end
    endtask

    task automatic wait_for_packet;
        integer timeout;
        begin
            timeout = 0;
            while (!packet_strobe && timeout < 1000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            check(packet_strobe, "timeout waiting for UART packet");
        end
    endtask

    task automatic send_uart_bit(input logic value);
        begin
            manual_rx = value;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task automatic send_uart_byte(input logic [7:0] value);
        integer bit_no;
        begin
            send_uart_bit(1'b0);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                send_uart_bit(value[bit_no]);
            end
            send_uart_bit(1'b1);
        end
    endtask

    task automatic send_manual_packet(
        input logic [7:0] seq_num,
        input logic [8:0] x,
        input logic valid,
        input logic [7:0] y,
        input logic corrupt_crc
    );
        logic [7:0] flags;
        logic [7:0] crc;
        begin
            flags = {6'b0, valid, x[8]};
            crc = tracking_uart_packet_crc8(seq_num, x[7:0], flags, y);
            send_uart_byte(TRACKING_UART_SOF0);
            send_uart_byte(TRACKING_UART_SOF1);
            send_uart_byte(seq_num);
            send_uart_byte(x[7:0]);
            send_uart_byte(flags);
            send_uart_byte(y);
            send_uart_byte(corrupt_crc ? (crc ^ 8'h01) : crc);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Complete TX -> RX packet, including 9-bit X and valid flag.
        tx_target_valid = 1'b1;
        tx_target_x = 9'd421;
        tx_target_y = 8'd77;
        pulse_frame();

        // A new frame while TX is busy must be reported as dropped.
        repeat (8) @(posedge clk);
        pulse_frame();
        check(frame_dropped, "busy transmitter did not report dropped frame");

        wait_for_packet();
        check(rx_target_valid, "target_valid was lost in UART loopback");
        check(rx_target_x == 9'd421, "wrong X received over UART");
        check(rx_target_y == 8'd77, "wrong Y received over UART");
        check(link_alive, "link did not become active after valid packet");

        // Watchdog clears stale link state and target validity.
        while (link_alive) begin
            @(posedge clk);
            #1;
        end
        check(!rx_target_valid, "timeout did not clear target_valid");

        // Bad CRC must be reported and must not change the last good result.
        manual_mode = 1'b1;
        manual_rx = 1'b1;
        repeat (5) @(posedge clk);
        send_manual_packet(8'h31, 9'd123, 1'b1, 8'd45, 1'b1);
        repeat (20) @(posedge clk);
        check(packet_error_seen, "bad CRC was not reported");
        check(rx_target_x == 9'd421, "bad packet changed target X");
        check(rx_target_y == 8'd77, "bad packet changed target Y");

        if (errors == 0) begin
            $display("tracking_uart_tb PASSED");
        end else begin
            $fatal(1, "tracking_uart_tb FAILED: %0d errors", errors);
        end
        $finish;
    end

endmodule
