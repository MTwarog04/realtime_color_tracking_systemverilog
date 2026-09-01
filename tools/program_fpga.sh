#!/bin/bash
#
# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# Load one of the two generated bitstreams to a Xilinx FPGA using Vivado.
# Usage: program_fpga.sh camera|servo|path/to/file.bit

set -euo pipefail

case "${1:-}" in
    camera)
        bitstream_file=results/top_camera_basys3.bit
        ;;
    servo)
        bitstream_file=results/top_servo_basys3.bit
        ;;
    *.bit)
        bitstream_file=$1
        ;;
    *)
        echo "usage: $(basename "$0") camera|servo|path/to/file.bit" >&2
        exit 1
        ;;
esac

if [[ ! -f "${bitstream_file}" ]]; then
    echo "ERROR: bitstream does not exist: ${bitstream_file}" >&2
    exit 1
fi

vivado -mode tcl -source fpga/scripts/program_fpga.tcl \
    -tclargs "${bitstream_file}"
