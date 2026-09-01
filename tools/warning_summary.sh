#!/bin/bash
#
# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# This script extracts warnings and errors from the synthesis
# and implementation logs to a single log file.
# Run from the project root directory.

LOG_FILE=results/warning_summary.log

SYNTH_IGNORE='\[Constraints[[:space:]]18-5210\]|\[Netlist[[:space:]]29-345\]'
IMPL_IGNORE='replace_with_codes_to_be_ignored_only_when_justified'

printf '%b\n' 'Warnings, critical warnings and errors from synthesis and implementation\n' > $LOG_FILE
printf '%b\n\n' "Created: $(date '+%F %T')" >> $LOG_FILE

summarize_stage() {
    local heading=$1
    local log_pattern=$2
    local ignore_pattern=$3
    local log_file
    local messages
    local found_log=0
    local found_message=0

    printf '%s\n' "${heading}" >> "${LOG_FILE}"

    while IFS= read -r log_file; do
        found_log=1
        messages=$(grep -Ev "${ignore_pattern}" "${log_file}" \
            | grep -E 'CRITICAL|WARNING|ERROR' || true)
        if [[ -n "${messages}" ]]; then
            found_message=1
            printf '%s\n' "${messages}" >> "${LOG_FILE}"
        fi
    done < <(compgen -G "${log_pattern}" || true)

    if [[ ${found_log} -eq 0 ]]; then
        printf 'No log file found!\n' >> "${LOG_FILE}"
    elif [[ ${found_message} -eq 0 ]]; then
        printf 'CLEAR :)\n' >> "${LOG_FILE}"
    fi
}

for target_name in camera servo; do
    project_path="fpga/build/${target_name}"
    printf '\n======== %s ========\n' "${target_name^^}" >> "${LOG_FILE}"
    summarize_stage '----SYNTHESIS----' \
        "${project_path}/*.runs/synth_1/runme.log" "${SYNTH_IGNORE}"
    summarize_stage '----IMPLEMENTATION----' \
        "${project_path}/*.runs/impl_1/runme.log" "${IMPL_IGNORE}"
done

sed -i -r "s/\/home\/([a-zA-Z0-9_]*\/)*$(basename "$PWD")\///" "${LOG_FILE}"
