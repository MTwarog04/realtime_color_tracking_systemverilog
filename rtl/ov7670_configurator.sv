
`timescale 1ns / 1ps


module ov7670_configurator (
    input  logic clk,
    input  logic rst_n,
    output logic sioc,
    inout  wire  siod,
    output logic done
);

    localparam logic [7:0] COM8_FASTAEC  = 8'h80;
    localparam logic [7:0] COM8_AECSTEP  = 8'h40;
    localparam logic [7:0] COM8_BFILT    = 8'h20;
    localparam logic [7:0] COM8_AGC      = 8'h04;
    localparam logic [7:0] COM8_AEC      = 8'h01;
    localparam logic [7:0] COM8_AEC_AGC_ON =
        COM8_FASTAEC | COM8_AECSTEP | COM8_BFILT | COM8_AGC | COM8_AEC;
    localparam logic [7:0] COM8_AEC_AGC_SETUP =
        COM8_FASTAEC | COM8_AECSTEP | COM8_BFILT;

    logic [15:0] init_rom [0:72];

    initial begin
        init_rom[0]  = 16'h1280;
        init_rom[1]  = 16'h1200;
        init_rom[2]  = 16'h1101;
        init_rom[3]  = 16'h0C00;
        init_rom[4]  = 16'h3E00;
        init_rom[5]  = 16'h8C00;
        init_rom[6]  = 16'h0400;
        init_rom[7]  = 16'h4000;
        init_rom[8]  = 16'h3A04;
        init_rom[9]  = 16'h1448;
        init_rom[10] = 16'h4f80;
        init_rom[11] = 16'h5080;
        init_rom[12] = 16'h5100;
        init_rom[13] = 16'h5222;
        init_rom[14] = 16'h535e;
        init_rom[15] = 16'h5480;
        init_rom[16] = 16'h589e;
        init_rom[17] = 16'h3d88;
        init_rom[18] = 16'h1101;
        init_rom[19] = 16'h1711;
        init_rom[20] = 16'h1861;
        init_rom[21] = 16'h32a4;
        init_rom[22] = 16'h1903;
        init_rom[23] = 16'h1a7b;
        init_rom[24] = 16'h030a;
        init_rom[25] = 16'h0e61;
        init_rom[26] = 16'h0f4b;
        init_rom[27] = 16'h1602;
        init_rom[28] = 16'h1e37;
        init_rom[29] = 16'h2102;
        init_rom[30] = 16'h2291;
        init_rom[31] = 16'h2907;
        init_rom[32] = 16'h330b;
        init_rom[33] = 16'h350b;
        init_rom[34] = 16'h371d;
        init_rom[35] = 16'h3871;
        init_rom[36] = 16'h392a;
        init_rom[37] = 16'h3c78;
        init_rom[38] = 16'h4d40;
        init_rom[39] = 16'h4e20;
        init_rom[40] = 16'h6900;
        init_rom[41] = 16'h6b4a;
        init_rom[42] = 16'h7410;
        init_rom[43] = 16'h8d4f;
        init_rom[44] = 16'h8e00;
        init_rom[45] = 16'h8f00;
        init_rom[46] = 16'h9000;
        init_rom[47] = 16'h9100;
        init_rom[48] = 16'h9600;
        init_rom[49] = 16'h9a00;
        init_rom[50] = 16'hb084;
        init_rom[51] = 16'hb10c;
        init_rom[52] = 16'hb20e;
        init_rom[53] = 16'hb382;
        init_rom[54] = 16'hb80a;
        init_rom[55] = {8'h13, COM8_AEC_AGC_SETUP};
        init_rom[56] = 16'h0000;
        init_rom[57] = 16'h0A00;
        init_rom[58] = 16'h0D40;
        init_rom[59] = 16'h2495;
        init_rom[60] = 16'h2533;
        init_rom[61] = 16'h26E3;
        init_rom[62] = 16'h9F78;
        init_rom[63] = 16'hA068;
        init_rom[64] = 16'hA103;
        init_rom[65] = 16'hA2D8;
        init_rom[66] = 16'hA3D8;
        init_rom[67] = 16'hA4F0;
        init_rom[68] = 16'hA690;
        init_rom[69] = 16'hA794;
        init_rom[70] = {8'h13, COM8_AEC_AGC_ON};
        init_rom[71] = 16'h1448;
        init_rom[72] = 16'hFFFF;
    end

    logic [7:0] clk_div;
    logic       tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div <= '0;
            tick <= 1'b0;
        end else if (clk_div == 8'd62) begin
            clk_div <= '0;
            tick <= 1'b1;
        end else begin
            clk_div <= clk_div + 1'b1;
            tick <= 1'b0;
        end
    end

    typedef enum logic [4:0] {
        IDLE,
        START_A, START_B, START_C, START_D,
        SEND_BIT_A, SEND_BIT_B, SEND_BIT_C, SEND_BIT_D,
        ACK_A, ACK_B, ACK_C, ACK_D,
        STOP_A, STOP_B, STOP_C, STOP_D,
        DELAY, DONE_STATE
    } state_t;

    state_t state;
    logic [7:0] reg_index;
    logic [23:0] shift_reg;
    logic [4:0] bit_cnt;
    logic [15:0] delay_cnt;
    logic [15:0] cmd_word;

    logic sda_out;
    logic sda_oe;
    logic scl_out;

    assign siod = sda_oe ? sda_out : 1'bz;
    assign sioc = scl_out;
    assign cmd_word = init_rom[reg_index];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            sda_out <= 1'b1;
            sda_oe <= 1'b1;
            scl_out <= 1'b1;
            reg_index <= '0;
            shift_reg <= '0;
            bit_cnt <= '0;
            delay_cnt <= '0;
        end else if (tick) begin
            case (state)
                IDLE: begin
                    if (cmd_word == 16'hFFFF) begin
                        state <= DONE_STATE;
                        done <= 1'b1;
                    end else begin
                        shift_reg <= {8'h42, cmd_word};
                        bit_cnt <= 5'd24;
                        state <= START_A;
                    end
                end

                START_A: begin
                    sda_oe <= 1'b1;
                    sda_out <= 1'b1;
                    scl_out <= 1'b1;
                    state <= START_B;
                end
                START_B: begin
                    sda_out <= 1'b0;
                    scl_out <= 1'b1;
                    state <= START_C;
                end
                START_C: begin
                    sda_out <= 1'b0;
                    scl_out <= 1'b0;
                    state <= START_D;
                end
                START_D: begin
                    state <= SEND_BIT_A;
                end

                SEND_BIT_A: begin
                    sda_oe <= 1'b1;
                    sda_out <= shift_reg[23];
                    scl_out <= 1'b0;
                    state <= SEND_BIT_B;
                end
                SEND_BIT_B: begin
                    scl_out <= 1'b1;
                    state <= SEND_BIT_C;
                end
                SEND_BIT_C: begin
                    scl_out <= 1'b1;
                    state <= SEND_BIT_D;
                end
                SEND_BIT_D: begin
                    scl_out <= 1'b0;
                    shift_reg <= {shift_reg[22:0], 1'b0};
                    bit_cnt <= bit_cnt - 1'b1;
                    if ((bit_cnt == 17) || (bit_cnt == 9) || (bit_cnt == 1)) begin
                        state <= ACK_A;
                    end else begin
                        state <= SEND_BIT_A;
                    end
                end

                ACK_A: begin
                    sda_oe <= 1'b0;
                    scl_out <= 1'b0;
                    state <= ACK_B;
                end
                ACK_B: begin
                    scl_out <= 1'b1;
                    state <= ACK_C;
                end
                ACK_C: begin
                    scl_out <= 1'b1;
                    state <= ACK_D;
                end
                ACK_D: begin
                    scl_out <= 1'b0;
                    if (bit_cnt == 0) begin
                        state <= STOP_A;
                    end else begin
                        state <= SEND_BIT_A;
                    end
                end

                STOP_A: begin
                    sda_oe <= 1'b1;
                    sda_out <= 1'b0;
                    scl_out <= 1'b0;
                    state <= STOP_B;
                end
                STOP_B: begin
                    sda_out <= 1'b0;
                    scl_out <= 1'b1;
                    state <= STOP_C;
                end
                STOP_C: begin
                    sda_out <= 1'b1;
                    scl_out <= 1'b1;
                    state <= STOP_D;
                end
                STOP_D: begin
                    delay_cnt <= '0;
                    state <= DELAY;
                end

                DELAY: begin
                    if (delay_cnt == 16'd1000) begin
                        reg_index <= reg_index + 1'b1;
                        state <= IDLE;
                    end else begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end
                end

                DONE_STATE: begin
                    done <= 1'b1;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
