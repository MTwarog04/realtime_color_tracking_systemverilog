#!/bin/bash -e
#
# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# Initialize enviorment for working with the project.

export ROOT_DIR=$(pwd)
export PATH=tools:${PATH}

# Native Linux installation.
vivado_executable=$(type -P vivado 2>/dev/null || true)
if [[ -n ${vivado_executable} ]]; then
    export VIVADO_DIR=$(dirname "$(dirname "${vivado_executable}")")
fi

# WSL may expose Windows Vivado through a bash alias, for example:
# alias vivado='cmd.exe /C "E:\Xilinx\Vivado\2024.2\bin\vivado.bat"'
vivado_alias=$(alias vivado 2>/dev/null || true)
if [[ -z ${VIVADO_DIR} && -n ${vivado_alias} ]]; then
    vivado_batch=${vivado_alias#*\"}
    vivado_batch=${vivado_batch%%\"*}
    if [[ ${vivado_batch} == *.bat ]]; then
        export VIVADO_WINDOWS_BIN=${vivado_batch%\\vivado.bat}
        vivado_bin_wsl=$(wslpath -u "${VIVADO_WINDOWS_BIN}")
        export VIVADO_DIR=${vivado_bin_wsl%/bin}
    fi
fi

# Create local git repository - required for scripts
if [[ ! -d .git ]]; then
    git init
    git add .
fi

mkdir -p results

# Copy glbl.v from Vivado instalation dir - required for IP simulation
if [[ -n ${VIVADO_DIR} && ! -e sim/common/glbl.v ]]; then
    mkdir -p sim/common
    cp ${VIVADO_DIR}/data/verilog/src/glbl.v sim/common/glbl.v
fi
