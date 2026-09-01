// Autorzy: Mikołaj Twaróg, Maciej Nowak
/**
 * Basys 3 top level for the camera / tracking node.
 *
 * The board captures and processes the OV7670 stream, displays the local VGA
 * preview, and sends one tracking packet per frame through uart_tx.
 */
module top_camera_basys3 (
    input  wire        clk,
    input  wire        btnC,
    output wire [15:0] led,
    input  wire [15:0] sw,
    output wire        uart_tx,
    output wire        ov7670_sioc,
    inout  wire        ov7670_siod,
    input  wire        ov7670_vsync,
    input  wire        ov7670_href,
    input  wire        ov7670_pclk,
    output wire        ov7670_xclk,
    input  wire [7:0]  ov7670_data,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue,
    output wire        Hsync,
    output wire        Vsync
);

    timeunit 1ns;
    timeprecision 1ps;

    wire clk_in;
    wire clk_fb_raw;
    wire clk_fb;
    wire clk_65mhz_raw;
    wire clk_40mhz_raw;
    wire locked;
    wire clk_65mhz;
    wire clk_40mhz;

    IBUF clk_ibuf (
        .I(clk),
        .O(clk_in)
    );

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.000),
        .DIVCLK_DIVIDE(5),
        .CLKFBOUT_MULT_F(52.000),
        .CLKOUT0_DIVIDE_F(16.000),
        .CLKOUT1_DIVIDE(26)
    ) clk_in_mmcme2 (
        .CLKIN1(clk_in),
        .CLKOUT0(clk_65mhz_raw),
        .CLKOUT0B(),
        .CLKOUT1(clk_40mhz_raw),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clk_fb_raw),
        .CLKFBOUTB(),
        .CLKFBIN(clk_fb),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFG clk_fb_bufg (
        .I(clk_fb_raw),
        .O(clk_fb)
    );

    BUFG clk_65mhz_bufg (
        .I(clk_65mhz_raw),
        .O(clk_65mhz)
    );

    BUFG clk_40mhz_bufg (
        .I(clk_40mhz_raw),
        .O(clk_40mhz)
    );

    top_camera u_top_camera (
        .clk(clk_65mhz),
        .camera_ref_clk(clk_40mhz),
        .rst(btnC | ~locked),
        .led(led),
        .sw(sw),
        .uart_tx(uart_tx),
        .ov7670_sioc(ov7670_sioc),
        .ov7670_siod(ov7670_siod),
        .ov7670_vsync(ov7670_vsync),
        .ov7670_href(ov7670_href),
        .ov7670_pclk(ov7670_pclk),
        .ov7670_xclk(ov7670_xclk),
        .ov7670_data(ov7670_data),
        .vs(Vsync),
        .hs(Hsync),
        .r(vgaRed),
        .g(vgaGreen),
        .b(vgaBlue)
    );

endmodule
