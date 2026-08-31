/*
 * Transport format shared by the two Basys 3 bitstreams.
 *
 * One UART packet is seven 8-N-1 bytes, sent in this order:
 *
 *   A5 5A SEQ X_LO FLAGS Y CRC8
 *
 * FLAGS[0] is target_x[8], FLAGS[1] is target_valid, and FLAGS[7:2]
 * are reserved and must be zero.  CRC8 is CRC-8/ATM (polynomial 0x07,
 * initial value 0x00, no reflection or final xor) over the first six bytes.
 * The two SOF bytes let the receiver find packet boundaries again after a
 * line error; the CRC prevents a false boundary from updating the servos.
 */

`timescale 1ns / 1ps

package tracking_uart_pkg;

    localparam logic [7:0] TRACKING_UART_SOF0 = 8'hA5;
    localparam logic [7:0] TRACKING_UART_SOF1 = 8'h5A;
    localparam int unsigned TRACKING_UART_PACKET_BYTES = 7;

    function automatic logic [7:0] tracking_uart_crc8_next(
        input logic [7:0] crc,
        input logic [7:0] data
    );
        logic [7:0] value;
        int unsigned bit_no;
        begin
            value = crc ^ data;
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                if (value[7]) begin
                    value = (value << 1) ^ 8'h07;
                end else begin
                    value = value << 1;
                end
            end
            tracking_uart_crc8_next = value;
        end
    endfunction

    function automatic logic [7:0] tracking_uart_packet_crc8(
        input logic [7:0] seq_num,
        input logic [7:0] x_low,
        input logic [7:0] flags,
        input logic [7:0] y
    );
        logic [7:0] crc;
        begin
            crc = 8'h00;
            crc = tracking_uart_crc8_next(crc, TRACKING_UART_SOF0);
            crc = tracking_uart_crc8_next(crc, TRACKING_UART_SOF1);
            crc = tracking_uart_crc8_next(crc, seq_num);
            crc = tracking_uart_crc8_next(crc, x_low);
            crc = tracking_uart_crc8_next(crc, flags);
            crc = tracking_uart_crc8_next(crc, y);
            tracking_uart_packet_crc8 = crc;
        end
    endfunction

endpackage
