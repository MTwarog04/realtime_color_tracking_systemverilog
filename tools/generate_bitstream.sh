#!/bin/bash
#
# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# Build the camera and servo Basys 3 targets, copy both bitstreams to results,
# and create a combined warning summary.

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${PROJECT_ROOT}"

# Clean only the two generated projects owned by this script. Do not use
# git clean here: fpga/build is ignored as a whole, so Git would also remove
# the unrelated legacy single-board project.
rm -rf -- fpga/build/camera fpga/build/servo
mkdir -p results fpga/build/camera fpga/build/servo
rm -f results/top_camera_basys3.bit results/top_servo_basys3.bit

build_target() {
    local target_name=$1

    (
        cd fpga
        vivado \
            -mode batch \
            -log "build/${target_name}/vivado.log" \
            -journal "build/${target_name}/vivado.jou" \
            -source scripts/generate_bitstream.tcl \
            -tclargs "scripts/project_${target_name}_details.tcl"
    )
}

copy_bitstream() {
    local target_name=$1
    local top_module=$2
    local bitstream_file

    bitstream_file=$(find "fpga/build/${target_name}" \
        -type f -path "*/impl_1/${top_module}.bit" -print -quit)

    if [[ -z "${bitstream_file}" ]]; then
        echo "ERROR: no bitstream found for ${target_name} (${top_module})" >&2
        exit 1
    fi

    cp "${bitstream_file}" "results/${top_module}.bit"
}

build_target camera
build_target servo

copy_bitstream camera top_camera_basys3
copy_bitstream servo top_servo_basys3

./tools/warning_summary.sh

echo "Generated bitstreams:"
echo "  results/top_camera_basys3.bit"
echo "  results/top_servo_basys3.bit"
