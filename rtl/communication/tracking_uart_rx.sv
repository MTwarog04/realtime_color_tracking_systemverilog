/* Autor: Maciej Nowak */
/*
 * UART receiver and packet validator for tracking_uart_tx.
 *
 * rx is asynchronous to clk and is passed through a two-flop synchronizer.
 * packet_strobe is a one-clk pulse issued only after both SOF bytes, all data
 * bytes, reserved flags, and CRC-8 have been validated.  target_* therefore
 * remain at their last known-good values across line noise or a bad packet.
 *
 * link_alive becomes high after the first valid packet and returns low if no
 * valid packet arrives within LINK_TIMEOUT_CLKS.  A timeout also clears
 * target_valid.  Set LINK_TIMEOUT_CLKS to zero to disable timeout ageing.
 */

`timescale 1ns / 1ps

module tracking_uart_rx
    import tracking_uart_pkg::*;
#(
    parameter int unsigned CLK_HZ            = 40_000_000,
    parameter int unsigned BAUD_RATE         = 100_000,
    parameter int unsigned LINK_TIMEOUT_CLKS = CLK_HZ / 2
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic       packet_strobe,
    output logic       target_valid,
    output logic [8:0] target_x,
    output logic [7:0] target_y,
    output logic       link_alive,
    output logic       packet_error
);

    localparam int unsigned CLKS_PER_BIT =
        (CLK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
    localparam int unsigned START_SAMPLE_CLKS =
        (CLKS_PER_BIT < 2) ? 1 : (CLKS_PER_BIT / 2);
    localparam int unsigned BAUD_COUNTER_W =
        (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
    localparam int unsigned LINK_TIMEOUT_LIMIT =
        (LINK_TIMEOUT_CLKS == 0) ? 1 : LINK_TIMEOUT_CLKS;
    localparam int unsigned LINK_COUNTER_W =
        (LINK_TIMEOUT_LIMIT <= 1) ? 1 : $clog2(LINK_TIMEOUT_LIMIT);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    typedef enum logic [2:0] {
        PARSE_SOF0,
        PARSE_SOF1,
        PARSE_SEQUENCE,
        PARSE_X_LOW,
        PARSE_FLAGS,
        PARSE_Y,
        PARSE_CRC
    } parse_state_t;

    (* ASYNC_REG = "TRUE" *) logic rx_meta;
    (* ASYNC_REG = "TRUE" *) logic rx_sync;

    rx_state_t    rx_state;
    parse_state_t parse_state;
    logic [BAUD_COUNTER_W-1:0] baud_counter;
    logic [2:0]                bit_index;
    logic [7:0]                rx_byte;
    logic [7:0]                received_byte;
    logic                      received_byte_strobe;

    logic [7:0] parser_crc;
    logic [7:0] parsed_x_low;
    logic       parsed_x_msb;
    logic       parsed_target_valid;
    logic       parsed_flags_ok;
    logic [7:0] parsed_y;
    logic [LINK_COUNTER_W-1:0] link_timeout_counter;

    logic valid_packet;

    /* A received byte is made visible to the packet parser one clk after its */
    /* stop bit.  At that point all sampled data bits are stable in rx_byte. */
    assign valid_packet = received_byte_strobe &&
                          (parse_state == PARSE_CRC) &&
                          (received_byte == parser_crc) &&
                          parsed_flags_ok;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    /* Physical 8-N-1 UART receiver.  Start and every data bit are sampled in */
    /* their centre.  Each start bit re-synchronizes sampling, so the two Basys */
    /* boards need no shared clock. */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state             <= RX_IDLE;
            baud_counter         <= '0;
            bit_index            <= '0;
            rx_byte              <= '0;
            received_byte        <= '0;
            received_byte_strobe <= 1'b0;
        end else begin
            received_byte_strobe <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    baud_counter <= '0;
                    if (!rx_sync) begin
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (baud_counter == START_SAMPLE_CLKS - 1) begin
                        baud_counter <= '0;
                        if (!rx_sync) begin
                            bit_index <= '0;
                            rx_state  <= RX_DATA;
                        end else begin
                            /* A short low glitch was not a UART start bit. */
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                RX_DATA: begin
                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter       <= '0;
                        rx_byte[bit_index] <= rx_sync;

                        if (bit_index == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                RX_STOP: begin
                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= '0;
                        rx_state     <= RX_IDLE;

                        if (rx_sync) begin
                            received_byte        <= rx_byte;
                            received_byte_strobe <= 1'b1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                default: begin
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

    /* Packet parser and link watchdog.  The parser writes target outputs only */
    /* on a complete, CRC-correct packet, preventing a corrupted UART byte from */
    /* creating an unintended servo update. */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_state         <= PARSE_SOF0;
            parser_crc          <= '0;
            parsed_x_low        <= '0;
            parsed_x_msb        <= 1'b0;
            parsed_target_valid <= 1'b0;
            parsed_flags_ok     <= 1'b0;
            parsed_y            <= '0;
            target_x            <= '0;
            target_y            <= '0;
            target_valid        <= 1'b0;
            packet_strobe       <= 1'b0;
            packet_error        <= 1'b0;
            link_alive          <= 1'b0;
            link_timeout_counter <= '0;
        end else begin
            packet_strobe <= 1'b0;
            packet_error  <= 1'b0;

            if (valid_packet) begin
                link_alive          <= 1'b1;
                link_timeout_counter <= '0;
            end else if (LINK_TIMEOUT_CLKS != 0) begin
                if (link_alive) begin
                    if (link_timeout_counter == LINK_TIMEOUT_LIMIT - 1) begin
                        link_alive   <= 1'b0;
                        target_valid <= 1'b0;
                    end else begin
                        link_timeout_counter <= link_timeout_counter + 1'b1;
                    end
                end
            end

            if (received_byte_strobe) begin
                unique case (parse_state)
                    PARSE_SOF0: begin
                        if (received_byte == TRACKING_UART_SOF0) begin
                            parser_crc  <= tracking_uart_crc8_next(
                                8'h00, TRACKING_UART_SOF0
                            );
                            parse_state <= PARSE_SOF1;
                        end
                    end

                    PARSE_SOF1: begin
                        if (received_byte == TRACKING_UART_SOF1) begin
                            parser_crc <= tracking_uart_crc8_next(
                                parser_crc, TRACKING_UART_SOF1
                            );
                            parse_state <= PARSE_SEQUENCE;
                        end else if (received_byte == TRACKING_UART_SOF0) begin
                            /* Let A5 A5 5A still lock onto the second A5. */
                            parser_crc <= tracking_uart_crc8_next(
                                8'h00, TRACKING_UART_SOF0
                            );
                        end else begin
                            parse_state <= PARSE_SOF0;
                        end
                    end

                    PARSE_SEQUENCE: begin
                        parser_crc <= tracking_uart_crc8_next(
                            parser_crc, received_byte
                        );
                        parse_state <= PARSE_X_LOW;
                    end

                    PARSE_X_LOW: begin
                        parsed_x_low <= received_byte;
                        parser_crc <= tracking_uart_crc8_next(
                            parser_crc, received_byte
                        );
                        parse_state <= PARSE_FLAGS;
                    end

                    PARSE_FLAGS: begin
                        parsed_x_msb        <= received_byte[0];
                        parsed_target_valid <= received_byte[1];
                        parsed_flags_ok     <= ~|received_byte[7:2];
                        parser_crc <= tracking_uart_crc8_next(
                            parser_crc, received_byte
                        );
                        parse_state <= PARSE_Y;
                    end

                    PARSE_Y: begin
                        parsed_y <= received_byte;
                        parser_crc <= tracking_uart_crc8_next(
                            parser_crc, received_byte
                        );
                        parse_state <= PARSE_CRC;
                    end

                    PARSE_CRC: begin
                        if (valid_packet) begin
                            target_x      <= {parsed_x_msb, parsed_x_low};
                            target_y      <= parsed_y;
                            target_valid  <= parsed_target_valid;
                            packet_strobe <= 1'b1;
                        end else begin
                            packet_error <= 1'b1;
                        end
                        parse_state <= PARSE_SOF0;
                    end

                    default: begin
                        parse_state <= PARSE_SOF0;
                    end
                endcase
            end
        end
    end

endmodule
