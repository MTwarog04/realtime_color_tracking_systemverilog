## Basys 3 camera/tracking node.
## UART wiring to the servo node: JA1 (uart_tx) -> JA1 (uart_rx), plus GND.

set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

set_property PACKAGE_PIN U18 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
set_property PACKAGE_PIN W15 [get_ports {sw[4]}]
set_property PACKAGE_PIN V15 [get_ports {sw[5]}]
set_property PACKAGE_PIN W14 [get_ports {sw[6]}]
set_property PACKAGE_PIN W13 [get_ports {sw[7]}]
set_property PACKAGE_PIN V2  [get_ports {sw[8]}]
set_property PACKAGE_PIN T3  [get_ports {sw[9]}]
set_property PACKAGE_PIN T2  [get_ports {sw[10]}]
set_property PACKAGE_PIN R3  [get_ports {sw[11]}]
set_property PACKAGE_PIN W2  [get_ports {sw[12]}]
set_property PACKAGE_PIN U1  [get_ports {sw[13]}]
set_property PACKAGE_PIN T1  [get_ports {sw[14]}]
set_property PACKAGE_PIN R2  [get_ports {sw[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property PACKAGE_PIN W18 [get_ports {led[4]}]
set_property PACKAGE_PIN U15 [get_ports {led[5]}]
set_property PACKAGE_PIN U14 [get_ports {led[6]}]
set_property PACKAGE_PIN V14 [get_ports {led[7]}]
set_property PACKAGE_PIN V13 [get_ports {led[8]}]
set_property PACKAGE_PIN V3  [get_ports {led[9]}]
set_property PACKAGE_PIN W3  [get_ports {led[10]}]
set_property PACKAGE_PIN U3  [get_ports {led[11]}]
set_property PACKAGE_PIN P3  [get_ports {led[12]}]
set_property PACKAGE_PIN N3  [get_ports {led[13]}]
set_property PACKAGE_PIN P1  [get_ports {led[14]}]
set_property PACKAGE_PIN L1  [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## JA1: asynchronous UART TX, 3.3 V LVCMOS.
set_property PACKAGE_PIN J1 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## VGA connector.
set_property PACKAGE_PIN G19 [get_ports {vgaRed[0]}]
set_property PACKAGE_PIN H19 [get_ports {vgaRed[1]}]
set_property PACKAGE_PIN J19 [get_ports {vgaRed[2]}]
set_property PACKAGE_PIN N19 [get_ports {vgaRed[3]}]
set_property PACKAGE_PIN N18 [get_ports {vgaBlue[0]}]
set_property PACKAGE_PIN L18 [get_ports {vgaBlue[1]}]
set_property PACKAGE_PIN K18 [get_ports {vgaBlue[2]}]
set_property PACKAGE_PIN J18 [get_ports {vgaBlue[3]}]
set_property PACKAGE_PIN J17 [get_ports {vgaGreen[0]}]
set_property PACKAGE_PIN H17 [get_ports {vgaGreen[1]}]
set_property PACKAGE_PIN G17 [get_ports {vgaGreen[2]}]
set_property PACKAGE_PIN D17 [get_ports {vgaGreen[3]}]
set_property PACKAGE_PIN P19 [get_ports Hsync]
set_property PACKAGE_PIN R19 [get_ports Vsync]
set_property IOSTANDARD LVCMOS33 [get_ports {vgaRed[*] vgaGreen[*] vgaBlue[*] Hsync Vsync}]

## OV7670 data bus on JB.
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[0]}]
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[1]}]
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[2]}]
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[3]}]
set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[4]}]
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[5]}]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[6]}]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {ov7670_data[7]}]

## OV7670 control and clock signals on JC.
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports ov7670_sioc]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports ov7670_siod]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports ov7670_vsync]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports ov7670_href]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports ov7670_pclk]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports ov7670_xclk]

# clk_div[1] divides the 40 MHz MMCM output by four. It clocks the camera
# configurator and drives the 10 MHz XCLK output, so keep it related to the
# MMCM clocks instead of treating it as an asynchronous clock.
create_generated_clock -name ov7670_xclk_int -divide_by 4 \
    -source [get_pins u_top_camera/clk_div_reg[1]/C] \
    [get_pins u_top_camera/clk_div_reg[1]/Q]

# The 40 MHz camera reference clock is divided by four in top_camera, giving
# the sensor a 10 MHz XCLK. OV7670 register CLKRC=0x01 divides it by two and
# COM14=0x00 leaves PCLK undivided, so the capture clock is 5 MHz (200 ns).
create_clock -add -name ov7670_pclk_in -period 200.000 \
    -waveform {0.000 100.000} [get_ports ov7670_pclk]

# PCLK is regenerated inside the external camera and has no guaranteed phase
# relationship to the MMCM clocks on the FPGA. The design crosses this boundary
# through explicit synchronization and the dual-clock frame buffer.
set_clock_groups -asynchronous \
    -group [get_clocks ov7670_pclk_in] \
    -group [get_clocks -include_generated_clocks sys_clk_pin]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets ov7670_pclk]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
