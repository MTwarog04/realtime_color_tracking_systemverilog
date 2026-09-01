#!/bin/bash
#
# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# This script runs simulations outside Vivado, making them faster.
# For usage details run the script with no arguments.
# For more information see: AMD Xilinx UG 900:
# https://docs.xilinx.com/r/en-US/ug900-vivado-logic-simulation/Simulating-in-Batch-or-Scripted-Mode-in-Vivado-Simulator
# To work properly, a git repository in the project directory is required.
# Run from the project root directory.

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

function usage {
    echo "usage: $(basename "$0") [options]"
    echo "  options:"
    echo "    -l         list available tests"
    echo "    -t <test>  run the specified <test>"
    echo "    -g         show gui (use with -t)"
    echo "    -a         run all available tests (does not work with gui)"
    exit 1
}

function list_available_tests {
    ls -1 --ignore 'build' --ignore 'common' --ignore '*.*' .
    exit 0
}

function configure_simulator {
    if command -v xelab >/dev/null 2>&1; then
        XELAB_CMD=(xelab)
        XSIM_CMD=(xsim)
        WINDOWS_SIMULATOR=''
        return 0
    fi

    if command -v xelab.bat >/dev/null 2>&1; then
        XELAB_CMD=(xelab.bat)
        XSIM_CMD=(xsim.bat)
        WINDOWS_SIMULATOR=''
        return 0
    fi

    windows_bin=${VIVADO_WINDOWS_BIN:-}
    if [[ -z ${windows_bin} ]]; then
        vivado_alias=$(alias vivado 2>/dev/null || true)
        vivado_batch=${vivado_alias#*\"}
        vivado_batch=${vivado_batch%%\"*}
        if [[ ${vivado_batch} == *.bat ]]; then
            windows_bin=${vivado_batch%\\vivado.bat}
        fi
    fi

    if [[ -n ${windows_bin} ]] &&
       [[ -f $(wslpath -u "${windows_bin}\\xelab.bat") ]]; then
        XELAB_CMD=(cmd.exe /C "${windows_bin}\\xelab.bat")
        XSIM_CMD=(cmd.exe /C "${windows_bin}\\xsim.bat")
        WINDOWS_SIMULATOR=1
        return 0
    fi

    echo "ERROR: xelab was not found. Source env.sh or add Vivado to PATH."
    return 1
}

function execute_test {
    # Remove untracked files
    git clean -fXd .

    mkdir -p build
    cd build

    test_name=$1

    if ! configure_simulator; then
        cd ..
        return 1
    fi

    project_file=${ROOT_DIR}/sim/${test_name}/${test_name}.prj
    if [[ ${WINDOWS_SIMULATOR} ]]; then
        project_file=$(wslpath -w "${project_file}")
    fi

    # Elaboration and simulation options
    if [[ $(grep 'glbl.v' -oc  ${ROOT_DIR}/sim/${test_name}/${test_name}.prj) -gt 0 ]]; then
        COMPILE_GLBL='work.glbl'
    else
        COMPILE_GLBL=''
    fi

    XELAB_OPTS="work.${test_name}_tb
                ${COMPILE_GLBL}
                -snapshot ${test_name}_tb
                -prj ${project_file}
                -timescale 1ns/1ps
                -L unisims_ver"

    # Run simulation
    if [[ ${show_gui} ]]; then
        "${XELAB_CMD[@]}" ${XELAB_OPTS} -debug typical || return 1
        sim_script=${ROOT_DIR}/tools/sim_cmd.tcl
        if [[ ${WINDOWS_SIMULATOR} ]]; then
            sim_script=$(wslpath -w "${sim_script}")
        fi
        "${XSIM_CMD[@]}" ${test_name}_tb -gui -t "${sim_script}"
    else
        simulation_output=$("${XELAB_CMD[@]}" ${XELAB_OPTS} \
                            -standalone -runall 2>&1)
        simulator_status=$?

        if [[ ${simulator_status} -ne 0 ]]; then
            echo "${simulation_output}"
        else
            echo "${simulation_output}" |
                grep -Eie 'PASSED|^fatal:|^error:|critical|warning:' \
                     --color=always || true
        fi

        if [[ ${simulator_status} -ne 0 ]] ||
           echo "${simulation_output}" | grep -Eiq '^fatal:|^error:'; then
            cd ..
            return 1
        fi
    fi

    cd ..
}

# Run all available simulations
function run_all {
    failed_tests=0
    for test in $(list_available_tests); do
        echo -en "${test}:\t"
        if execute_test ${test}; then
            echo -e "\033[1;32m PASSED\033[0;39m"
        else
            echo -e "\033[1;31m FAILED\033[0;39m"
            failed_tests=$((failed_tests + 1))
        fi
    done
    exit ${failed_tests}
}

# ------------------------------------------------------------------------------
# Arguments parsing and checking
# ------------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
    usage
fi

cd sim

while getopts aglrs:t: option; do
    case ${option} in
        g) show_gui=1;;
        l) list_available_tests;;
        t) test_name=${OPTARG};;
        a) run_all;;
        *) usage;;
    esac
done

if [[ ${test_name} ]]; then
    execute_test ${test_name}
fi
