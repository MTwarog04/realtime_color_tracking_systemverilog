# Two-Basys-3 tracking system

The repository now contains two additional FPGA targets alongside the original
single-board design.  The original `top.sv`, `top_basys3.sv`, constraint file,
and batch-build setup remain unchanged.

```text
Camera Basys 3                                      Servo Basys 3
--------------                                      -------------
OV7670 -> image tracking -> UART TX  --- JA1 --->   UART RX -> servo controller -> PWM
                                  GND --- GND --->
```

The camera board sends the same data that the legacy single-board servo
controller used: a frame update, target-valid flag, 9-bit X coordinate, and
8-bit Y coordinate.  It does not send the video image.

## Hardware connection

Connect the two boards with exactly these two connections:

1. Camera board `JA1` -> servo board `JA1`.
2. A Pmod `GND` pin -> a Pmod `GND` pin (pin 5 or pin 11 on each header).

Do not join the two boards' 3.3 V / VCC pins.  The servos still need their own
stable 5 V supply, with that supply's ground connected to the servo-board
ground.

The UART runs at 100,000 baud.  This value is deliberate: the 40 MHz internal
clock divides into it exactly (400 clocks per bit).  A seven-byte tracking
packet takes 700 microseconds, far less than one camera frame.

## New source files

| Role | Files |
| --- | --- |
| Shared transport | `rtl/tracking_uart_pkg.sv`, `rtl/tracking_uart_tx.sv`, `rtl/tracking_uart_rx.sv` |
| Camera application | `rtl/top_camera.sv`, `fpga/rtl/top_camera_basys3.sv`, `fpga/constraints/top_camera_basys3.xdc` |
| Servo application | `rtl/top_servo.sv`, `fpga/rtl/top_servo_basys3.sv`, `fpga/constraints/top_servo_basys3.xdc` |

`top_camera` retains the camera, tracking, and VGA path, but replaces the
local PWM output with UART TX.  `top_servo` receives a validated packet and
feeds its one-cycle packet strobe into the unchanged `servo_controller` and
`pwm_generator` modules.

The protocol is:

```text
A5 5A SEQ X_LO FLAGS Y CRC8
```

`FLAGS[0]` is `X[8]`, `FLAGS[1]` is `target_valid`, and the CRC is CRC-8/ATM.
The receiver updates the servo only after a complete, CRC-correct packet.  If
no valid packet arrives for 0.5 seconds, it clears `target_valid` and marks
the link inactive.

## Building in Vivado GUI (no new shell scripts)

Create two Vivado RTL projects outside `fpga/`, for example:

```text
vivado_projects/camera/basys_camera.xpr
vivado_projects/servo/basys_servo.xpr
```

When adding sources, clear Vivado's **Copy sources into project** option so
both projects refer to this one repository.

### Camera project

Use `top_camera_basys3` as the top module and add
`fpga/constraints/top_camera_basys3.xdc` as the constraint file.

Add these design sources, in this order:

```text
rtl/vga_pkg.sv
rtl/ycbcr_classifier.sv
rtl/mask_despeckle_filter.sv
rtl/centroid_accumulator.sv
rtl/smooth_tracker.sv
rtl/ov7670_capture.sv
rtl/ov7670_configurator.sv
rtl/vga_timing.sv
rtl/video_framebuffer.sv
rtl/vga_frame_renderer.sv
rtl/top_vga.sv
rtl/tracking_uart_pkg.sv
rtl/tracking_uart_tx.sv
rtl/top_camera.sv
fpga/rtl/top_camera_basys3.sv
```

Choose **Generate Bitstream**.  Program the result into the Basys 3 connected
to the camera.

### Servo project

Use `top_servo_basys3` as the top module and add
`fpga/constraints/top_servo_basys3.xdc` as the constraint file.

Add:

```text
rtl/tracking_uart_pkg.sv
rtl/tracking_uart_rx.sv
rtl/servo_controller.sv
rtl/pwm_generator.sv
rtl/top_servo.sv
fpga/rtl/top_servo_basys3.sv
```

Choose **Generate Bitstream**.  Program this result into the Basys 3 connected
to the servos.

The existing `tools/generate_bitstream.sh` deliberately remains the legacy
single-board build and should not be used for the two new GUI targets.  It
cleans `fpga/` and assumes there is only one output bitstream.

## Servo-node LEDs

| LED | Meaning |
| --- | --- |
| LD0 | A valid packet was received during the last 0.5 seconds |
| LD1 | A malformed packet was seen since reset |
| LD2 | The most recent valid packet reported a detected target |
| LD3 | Current level of the UART RX wire (normally high while idle) |
