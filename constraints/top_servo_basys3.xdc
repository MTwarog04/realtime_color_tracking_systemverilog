## Basys 3 servo node.
## UART wiring from the camera node: JA1 (uart_tx) -> JA1 (uart_rx), plus GND.

set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

set_property PACKAGE_PIN U18 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

## JA1. The pull-up keeps the UART idle-high if the camera board is unplugged.
set_property PACKAGE_PIN J1 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PULLUP TRUE [get_ports uart_rx]

## MG90S PWM outputs: XA1_P / XA2_P on the JXADC header.
set_property PACKAGE_PIN J3 [get_ports servo_pan_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports servo_pan_pwm]
set_property PACKAGE_PIN L3 [get_ports servo_tilt_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports servo_tilt_pwm]

## Four diagnostic LEDs.
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
