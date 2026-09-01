# Copyright (C) 2026 AGH University of Science and Technology
# MTM UEC2
#
# Description:
# Vivado build configuration for the UART/servo Basys 3 node.

set project_name tracking_servo
set top_module top_servo_basys3
set target xc7a35tcpg236-1
set build_dir build/servo

set xdc_files {
    constraints/top_servo_basys3.xdc
}

set sv_files {
    ../rtl/communication/tracking_uart_pkg.sv
    ../rtl/communication/tracking_uart_rx.sv
    ../rtl/servo/servo_controller.sv
    ../rtl/servo/pwm_generator.sv
    ../rtl/top/top_servo.sv
    rtl/top_servo_basys3.sv
}
