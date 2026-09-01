# Copyright (C) 2026 AGH University of Science and Technology
# MTM UEC2
#
# Description:
# Vivado build configuration for the camera/tracking Basys 3 node.

set project_name tracking_camera
set top_module top_camera_basys3
set target xc7a35tcpg236-1
set build_dir build/camera

set xdc_files {
    ../constraints/top_camera_basys3.xdc
}

set sv_files {
    ../rtl/display/vga_pkg.sv
    ../rtl/camera/ycbcr_classifier.sv
    ../rtl/camera/mask_despeckle_filter.sv
    ../rtl/camera/centroid_accumulator.sv
    ../rtl/camera/smooth_tracker.sv
    ../rtl/camera/ov7670_capture.sv
    ../rtl/camera/ov7670_configurator.sv
    ../rtl/display/vga_timing.sv
    ../rtl/display/video_framebuffer.sv
    ../rtl/display/vga_frame_renderer.sv
    ../rtl/display/top_vga.sv
    ../rtl/communication/tracking_uart_pkg.sv
    ../rtl/communication/tracking_uart_tx.sv
    ../rtl/top/top_camera.sv
    rtl/top_camera_basys3.sv
}
