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
    wire clk_fb;
    wire clk_ss;
    wire clk_out;
    wire locked;
    wire clk_40mhz;

    (* KEEP = "TRUE" *)
    (* ASYNC_REG = "TRUE" *)
    logic [7:0] safe_start = '0;

    IBUF clk_ibuf (
        .I(clk),
        .O(clk_in)
    );

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.000),
        .CLKFBOUT_MULT_F(10.000),
        .CLKOUT0_DIVIDE_F(25.000)
    ) clk_in_mmcme2 (
        .CLKIN1(clk_in),
        .CLKOUT0(clk_out),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clk_fb),
        .CLKFBOUTB(),
        .CLKFBIN(clk_fb),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFH clk_out_bufh (
        .I(clk_out),
        .O(clk_ss)
    );

    always_ff @(posedge clk_ss) begin
        safe_start <= {safe_start[6:0], locked};
    end

    BUFGCE #(
        .SIM_DEVICE("7SERIES")
    ) clk_out_bufgce (
        .I(clk_out),
        .CE(safe_start[7]),
        .O(clk_40mhz)
    );

    top_camera u_top_camera (
        .clk(clk_40mhz),
        .rst(btnC),
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
