
`timescale 1ns / 1ps


module top (
    input  logic       clk,
    input  logic       rst,
    output logic [15:0] led,
    input  logic [15:0] sw,
    output logic       servo_pan_pwm,
    output logic       servo_tilt_pwm,
    output logic       ov7670_sioc,
    inout  wire       ov7670_siod,
    input  logic       ov7670_vsync,
    input  logic       ov7670_href,
    input  logic       ov7670_pclk,
    output logic       ov7670_xclk,
    input  logic [7:0] ov7670_data,
    output logic       vs,
    output logic       hs,
    output logic [3:0] r,
    output logic [3:0] g,
    output logic [3:0] b
);

    localparam int IMG_W = 320;
    localparam int IMG_H = 240;
    localparam int TOP_NOISE_LINES = 30;

    localparam logic [1:0] CH_Y   = 2'b00;
    localparam logic [1:0] CH_CB  = 2'b01;
    localparam logic [1:0] CH_CR  = 2'b10;
    localparam logic [1:0] CH_CHR = 2'b11;

    logic rst_n;
    assign rst_n = ~rst;

    logic       diag_enable;
    logic [1:0] diag_channel;
    logic       chroma_order;

    assign diag_enable = sw[15];
    assign diag_channel = sw[14:13];
    assign chroma_order = sw[12];

    logic [1:0] clk_div;
    logic       clk_25mhz;
    logic       camera_config_done;

    logic       pix_valid;
    logic       frame_start;
    logic       frame_end;
    logic [8:0] pix_x;
    logic [7:0] pix_y;
    logic [7:0] pix_y_luma;
    logic [7:0] pix_cb;
    logic [7:0] pix_cr;

    logic       color_mask;
    logic       in_noise_band;
    logic [7:0] frame_pixel;
    logic [7:0] diag_pixel;
    logic [7:0] cb_disp;
    logic [7:0] cr_disp;
    logic [7:0] chroma_mag;

    logic [$clog2(IMG_W * IMG_H)-1:0] cam_wr_addr;

    assign in_noise_band = pix_y < TOP_NOISE_LINES;
    assign servo_pan_pwm = 1'b0;
    assign servo_tilt_pwm = 1'b0;

    assign cb_disp = (pix_cb >= 8'd128) ? ((pix_cb - 8'd128) << 1) : ((8'd128 - pix_cb) << 1);
    assign cr_disp = (pix_cr >= 8'd128) ? ((pix_cr - 8'd128) << 1) : ((8'd128 - pix_cr) << 1);
    assign chroma_mag = (cb_disp >> 1) + (cr_disp >> 1);

    always_comb begin
        case (diag_channel)
            CH_CB: diag_pixel = in_noise_band ? 8'h0 : cb_disp;
            CH_CR: diag_pixel = in_noise_band ? 8'h0 : cr_disp;
            CH_CHR: diag_pixel = in_noise_band ? 8'h0 : chroma_mag;
            default: diag_pixel = in_noise_band ? 8'h0 : pix_y_luma;
        endcase
    end

    assign frame_pixel = diag_enable ? diag_pixel : (color_mask ? 8'hff : pix_y_luma);

    always_ff @(posedge clk) begin
        clk_div <= clk_div + 1'b1;
    end

    assign clk_25mhz = clk_div[1];
    assign ov7670_xclk = clk_25mhz;

    ov7670_configurator u_configurator (
        .clk(clk_25mhz),
        .rst_n(rst_n),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .done(camera_config_done)
    );

    ov7670_capture #(
        .H_RES(640),
        .V_RES(480),
        .OUT_W(IMG_W),
        .OUT_H(IMG_H)
    ) u_capture (
        .pclk(ov7670_pclk),
        .rst_n(rst_n),
        .chroma_order(chroma_order),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .pix_valid(pix_valid),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .pix_x(pix_x),
        .pix_y(pix_y),
        .pix_y_luma(pix_y_luma),
        .pix_cb(pix_cb),
        .pix_cr(pix_cr)
    );

    ycbcr_classifier #(
        .TOP_IGNORE_LINES(TOP_NOISE_LINES)
    ) u_classifier (
        .y(pix_y_luma),
        .cb(pix_cb),
        .cr(pix_cr),
        .pix_y(pix_y),
        .sw(sw),
        .mask(color_mask)
    );

    always_ff @(posedge ov7670_pclk or negedge rst_n) begin
        if (!rst_n) begin
            cam_wr_addr <= '0;
        end else if (pix_valid) begin
            if (frame_start) begin
                cam_wr_addr <= '0;
            end else begin
                cam_wr_addr <= cam_wr_addr + 1'b1;
            end
        end
    end

    top_vga u_top_vga (
        .clk(clk),
        .rst_n(rst_n),
        .frame_wr_clk(ov7670_pclk),
        .frame_wr_en(pix_valid),
        .frame_wr_bank(1'b0),
        .frame_wr_addr(cam_wr_addr),
        .frame_wr_data(frame_pixel),
        .frame_rd_bank(1'b0),
        .frame_valid(camera_config_done),
        .diag_enable(diag_enable),
        .diag_channel(diag_channel),
        .status_word(sw),
        .track_valid(1'b0),
        .target_x(IMG_W / 2),
        .target_y(IMG_H / 2),
        .vs(vs),
        .hs(hs),
        .r(r),
        .g(g),
        .b(b)
    );

    assign led[0] = camera_config_done;
    assign led[1] = diag_enable;
    assign led[3:2] = diag_channel;
    assign led[4] = chroma_order;
    assign led[6] = color_mask;
    assign led[7] = pix_valid;
    assign led[15:8] = 8'b0;

endmodule
