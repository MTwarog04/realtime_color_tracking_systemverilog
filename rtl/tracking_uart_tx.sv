/*
 * UART transmitter for one camera-tracking result per frame.
 *
 * The source inputs and frame_tick must be synchronous to clk.  At the
 * default 40 MHz / 100 kbaud settings a seven-byte packet lasts 700 us, so a
 * normal camera frame period leaves a large margin.  A frame_tick received
 * while busy is deliberately not queued: frame_dropped pulses for one clk so
 * the integration layer can expose that condition if desired.
 */

`timescale 1ns / 1ps

module tracking_uart_tx #(
    parameter int unsigned CLK_HZ    = 40_000_000,
    parameter int unsigned BAUD_RATE = 100_000
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       frame_tick,
    input  logic       target_valid,
    input  logic [8:0] target_x,
    input  logic [7:0] target_y,
    output logic       tx,
    output logic       busy,
    output logic       frame_dropped
);

    import tracking_uart_pkg::*;

    // Rounded division keeps the module reusable with baud rates that do not
    // divide CLK_HZ exactly.  40 MHz / 100 kbaud is exactly 400 clocks/bit.
    localparam int unsigned CLKS_PER_BIT =
        (CLK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam int unsigned BAUD_COUNTER_W =
        (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    typedef enum logic {TX_IDLE, TX_SEND} tx_state_t;

    tx_state_t tx_state;
    logic [BAUD_COUNTER_W-1:0] baud_counter;
    logic [3:0]                bit_index;
    logic [2:0]                byte_index;
    logic [9:0]                tx_word;

    logic [7:0] packet_sequence;
    logic [7:0] packet_x_low;
    logic [7:0] packet_flags;
    logic [7:0] packet_y;
    logic [7:0] packet_crc;
    logic [7:0] next_sequence;

    function automatic logic [7:0] packet_byte(
        input logic [2:0] index,
        input logic [7:0] seq_num,
        input logic [7:0] x_low,
        input logic [7:0] flags,
        input logic [7:0] y,
        input logic [7:0] crc
    );
        begin
            unique case (index)
                3'd0:   packet_byte = TRACKING_UART_SOF0;
                3'd1:   packet_byte = TRACKING_UART_SOF1;
                3'd2:   packet_byte = seq_num;
                3'd3:   packet_byte = x_low;
                3'd4:   packet_byte = flags;
                3'd5:   packet_byte = y;
                default: packet_byte = crc;
            endcase
        end
    endfunction

    // tx_word[0] is the start bit, [8:1] are data bits LSB first, and [9] is
    // the stop bit.  This maps directly onto the UART wire ordering.
    assign tx   = (tx_state == TX_SEND) ? tx_word[bit_index] : 1'b1;
    assign busy = (tx_state == TX_SEND);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state       <= TX_IDLE;
            baud_counter   <= '0;
            bit_index      <= '0;
            byte_index     <= '0;
            tx_word        <= 10'h3ff;
            packet_sequence <= '0;
            packet_x_low   <= '0;
            packet_flags   <= '0;
            packet_y       <= '0;
            packet_crc     <= '0;
            next_sequence  <= '0;
            frame_dropped  <= 1'b0;
        end else begin
            frame_dropped <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    baud_counter <= '0;
                    bit_index    <= '0;
                    byte_index   <= '0;

                    if (frame_tick) begin
                        packet_sequence <= next_sequence;
                        packet_x_low    <= target_x[7:0];
                        packet_flags    <= {6'b0, target_valid, target_x[8]};
                        packet_y        <= target_y;
                        packet_crc      <= tracking_uart_packet_crc8(
                            next_sequence,
                            target_x[7:0],
                            {6'b0, target_valid, target_x[8]},
                            target_y
                        );
                        next_sequence <= next_sequence + 1'b1;

                        tx_word  <= {1'b1, TRACKING_UART_SOF0, 1'b0};
                        tx_state <= TX_SEND;
                    end
                end

                TX_SEND: begin
                    if (frame_tick) begin
                        frame_dropped <= 1'b1;
                    end

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= '0;

                        if (bit_index == 4'd9) begin
                            bit_index <= '0;

                            if (byte_index == TRACKING_UART_PACKET_BYTES - 1) begin
                                byte_index <= '0;
                                tx_state   <= TX_IDLE;
                            end else begin
                                byte_index <= byte_index + 1'b1;
                                tx_word <= {
                                    1'b1,
                                    packet_byte(
                                        byte_index + 1'b1,
                                        packet_sequence,
                                        packet_x_low,
                                        packet_flags,
                                        packet_y,
                                        packet_crc
                                    ),
                                    1'b0
                                };
                            end
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                default: begin
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end

endmodule
