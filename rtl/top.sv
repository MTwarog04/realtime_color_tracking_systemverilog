
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
    localparam int TOP_NOISE_LINES = 0;
    localparam int MAX_BLOB_PIXELS = 7680;
    localparam int SYS_CLK_HZ      = 40_000_000;
    localparam int BALL_ASPECT_NUM = 2;
    localparam int BALL_ASPECT_DEN = 3;
    localparam int BALL_MIN_FILL_PERCENT = 40;
    localparam int BALL_MAX_FILL_PERCENT = 95;
    localparam int BALL_SMALL_OBJECT_LIMIT = 16;
    localparam int BALL_SMALL_ASPECT_NUM = 1;
    localparam int BALL_SMALL_ASPECT_DEN = 2;
    localparam int BALL_SMALL_MIN_FILL_PERCENT = 20;
    localparam int BALL_SMALL_MAX_FILL_PERCENT = 100;
    localparam int BALL_MIN_DIAMETER = 8;
    localparam int BALL_MAX_BLOBS = 16;
    localparam int BALL_CONNECT_GAP = 3;
    localparam int BALL_ROUND_FILL_PERCENT = 79;
    localparam int BALL_TRACK_MAX_DISTANCE = 80;

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
    logic       display_mask;
    logic       in_noise_band;
    logic [7:0] frame_pixel;
    logic [7:0] diag_pixel;
    logic [7:0] cb_disp;
    logic [7:0] cr_disp;
    logic [7:0] chroma_mag;

    logic [8:0] centroid_x;
    logic [7:0] centroid_y;
    logic       centroid_valid;
    logic [16:0] mask_pixel_count;
    logic [16:0] blob_count_sync1;
    logic [16:0] blob_count_sync2;

    logic [16:0] min_blob_pixels;
    logic [3:0]  blob_bar_level;
    logic [7:0]  blob_led_bar;

    logic [8:0] smooth_x;
    logic [7:0] smooth_y;
    logic       smooth_tick_pclk;

    logic [8:0] smooth_x_sync1;
    logic [8:0] smooth_x_sync2;
    logic [7:0] smooth_y_sync1;
    logic [7:0] smooth_y_sync2;
    logic       centroid_valid_sync1;
    logic       centroid_valid_sync2;

    logic [7:0] frame_start_stretch;
    logic       frame_start_extended;
    logic       frame_start_sync1;
    logic       frame_start_sync2;
    logic       frame_tick;

    logic [7:0] pan_duty;
    logic [7:0] tilt_duty;
    logic       pan_dir;
    logic       tilt_dir;

    logic [8:0] centroid_x_sync1;
    logic [8:0] centroid_x_sync2;
    logic [7:0] centroid_y_sync1;
    logic [7:0] centroid_y_sync2;

    logic [$clog2(IMG_W * IMG_H)-1:0] cam_wr_addr;

    assign in_noise_band = pix_y < TOP_NOISE_LINES;
    assign min_blob_pixels = 17'd200 + ({12'b0, sw[9:5]} * 17'd58);

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

    assign frame_pixel = diag_enable ? diag_pixel : (display_mask ? 8'hff : pix_y_luma);

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

    mask_despeckle_filter #(
        .IMG_W(IMG_W)
    ) u_mask_despeckle_filter (
        .clk(ov7670_pclk),
        .rst_n(rst_n),
        .pix_valid(pix_valid),
        .pix_x(pix_x),
        .pix_y(pix_y),
        .mask_in(color_mask),
        .mask_out(display_mask)
    );

    centroid_accumulator #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .TOP_IGNORE_LINES(TOP_NOISE_LINES),
        .ASPECT_NUM(BALL_ASPECT_NUM),
        .ASPECT_DEN(BALL_ASPECT_DEN),
        .MIN_FILL_PERCENT(BALL_MIN_FILL_PERCENT),
        .MAX_FILL_PERCENT(BALL_MAX_FILL_PERCENT),
        .SMALL_OBJECT_LIMIT(BALL_SMALL_OBJECT_LIMIT),
        .SMALL_ASPECT_NUM(BALL_SMALL_ASPECT_NUM),
        .SMALL_ASPECT_DEN(BALL_SMALL_ASPECT_DEN),
        .SMALL_MIN_FILL_PERCENT(BALL_SMALL_MIN_FILL_PERCENT),
        .SMALL_MAX_FILL_PERCENT(BALL_SMALL_MAX_FILL_PERCENT),
        .MIN_DIAMETER(BALL_MIN_DIAMETER),
        .MAX_BLOBS(BALL_MAX_BLOBS),
        .CONNECT_GAP(BALL_CONNECT_GAP),
        .ROUND_FILL_PERCENT(BALL_ROUND_FILL_PERCENT),
        .TRACK_MAX_DISTANCE(BALL_TRACK_MAX_DISTANCE)
    ) u_centroid (
        .clk(ov7670_pclk),
        .rst_n(rst_n),
        .pix_valid(pix_valid),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .mask(color_mask),
        .pix_x(pix_x),
        .pix_y(pix_y),
        .centroid_x(centroid_x),
        .centroid_y(centroid_y),
        .centroid_valid(centroid_valid),
        .mask_pixel_count(mask_pixel_count)
    );

    always_ff @(posedge ov7670_pclk or negedge rst_n) begin
        if (!rst_n) begin
            smooth_tick_pclk <= 1'b0;
        end else begin
            smooth_tick_pclk <= frame_start;
        end
    end

    smooth_tracker #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H)
    ) u_smooth_tracker (
        .clk(ov7670_pclk),
        .rst_n(rst_n),
        .frame_tick(smooth_tick_pclk),
        .measurement_valid(centroid_valid),
        .measured_x(centroid_x),
        .measured_y(centroid_y),
        .sw(sw),
        .smooth_x(smooth_x),
        .smooth_y(smooth_y)
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

    always_ff @(posedge ov7670_pclk or negedge rst_n) begin
        if (!rst_n) begin
            frame_start_stretch <= '0;
        end else if (frame_start) begin
            frame_start_stretch <= 8'hff;
        end else if (frame_start_stretch != '0) begin
            frame_start_stretch <= frame_start_stretch - 1'b1;
        end
    end

    assign frame_start_extended = |frame_start_stretch;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            smooth_x_sync1 <= IMG_W / 2;
            smooth_x_sync2 <= IMG_W / 2;
            smooth_y_sync1 <= IMG_H / 2;
            smooth_y_sync2 <= IMG_H / 2;
            centroid_valid_sync1 <= 1'b0;
            centroid_valid_sync2 <= 1'b0;
            blob_count_sync1 <= '0;
            blob_count_sync2 <= '0;
            frame_start_sync1 <= 1'b0;
            frame_start_sync2 <= 1'b0;
            centroid_x_sync1 <= IMG_W / 2;
            centroid_x_sync2 <= IMG_W / 2;
            centroid_y_sync1 <= IMG_H / 2;
            centroid_y_sync2 <= IMG_H / 2;
        end else begin
            smooth_x_sync1 <= smooth_x;
            smooth_x_sync2 <= smooth_x_sync1;
            smooth_y_sync1 <= smooth_y;
            smooth_y_sync2 <= smooth_y_sync1;
            centroid_x_sync1 <= centroid_x;
            centroid_x_sync2 <= centroid_x_sync1;
            centroid_y_sync1 <= centroid_y;
            centroid_y_sync2 <= centroid_y_sync1;
            centroid_valid_sync1 <= centroid_valid;
            centroid_valid_sync2 <= centroid_valid_sync1;
            blob_count_sync1 <= mask_pixel_count;
            blob_count_sync2 <= blob_count_sync1;
            frame_start_sync1 <= frame_start_extended;
            frame_start_sync2 <= frame_start_sync1;
        end
    end

    assign frame_tick = frame_start_sync1 & ~frame_start_sync2;

    servo_controller #(
        .CENTER_X(IMG_W / 2),
        .CENTER_Y(IMG_H / 2),
        .DEAD_BAND_X(2),
        .DEAD_BAND_Y(2),
        .VALID_FRAMES_TO_MOVE(2),
        .PAN_MAX_STEP(12),
        .TILT_MAX_STEP(8),
        .PAN_POSITION_LIMIT(127),
        .TILT_POSITION_LIMIT(60),
        .PAN_REVERSE(1'b0),
        .TILT_REVERSE(1'b0)
    ) u_servo_controller (
        .clk(clk),
        .rst_n(rst_n),
        .frame_tick(frame_tick),
        .target_valid(centroid_valid_sync2),
        .target_x(centroid_x_sync2),
        .target_y(centroid_y_sync2),
        .pan_duty(pan_duty),
        .tilt_duty(tilt_duty)
    );

    pwm_generator #(
        .CLK_HZ(SYS_CLK_HZ)
    ) u_pwm_pan (
        .clk(clk),
        .rst_n(rst_n),
        .duty(pan_duty),
        .pwm_out(servo_pan_pwm),
        .dir_out(pan_dir)
    );

    pwm_generator #(
        .CLK_HZ(SYS_CLK_HZ)
    ) u_pwm_tilt (
        .clk(clk),
        .rst_n(rst_n),
        .duty(tilt_duty),
        .pwm_out(servo_tilt_pwm),
        .dir_out(tilt_dir)
    );

    always_comb begin
        blob_bar_level = 4'd0;
        blob_led_bar = 8'b0;

        if (centroid_valid_sync2) begin
            if (blob_count_sync2 >= MAX_BLOB_PIXELS) begin
                blob_bar_level = 4'd8;
            end else if (blob_count_sync2 <= min_blob_pixels) begin
                blob_bar_level = 4'd1;
            end else begin
                blob_bar_level = 4'd1 + (
                    ((blob_count_sync2 - min_blob_pixels) * 17'd7) /
                    (MAX_BLOB_PIXELS - min_blob_pixels)
                );
            end
            blob_led_bar = 8'hff >> (8 - blob_bar_level);
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
        .track_valid(centroid_valid_sync2),
        .target_x(smooth_x_sync2),
        .target_y(smooth_y_sync2),
        .vs(vs),
        .hs(hs),
        .r(r),
        .g(g),
        .b(b)
    );

    assign led[0] = camera_config_done;
    assign led[1] = diag_enable;
    assign led[3:2] = diag_enable ? diag_channel : 2'b00;
    assign led[4] = chroma_order;
    assign led[5] = centroid_valid_sync2;
    assign led[6] = display_mask;
    assign led[7] = pix_valid;
    assign led[15:8] = blob_led_bar;

endmodule
