# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# tcl script being sourced to Vivado to build a project from sources and generate a bitstream.
# Project details and paths to the source files are read from a configuration
# file passed as the first Tcl argument. With no argument, the legacy
# project_details.tcl configuration is used.


# Source the project details file. It must provide project_name, top_module,
# target and paths to all design sources. build_dir is optional for legacy
# configurations.
if {$argc > 1} {
    error "usage: generate_bitstream.tcl ?project_details_file?"
}

if {$argc == 1} {
    set project_details_file [lindex $argv 0]
} else {
    set project_details_file scripts/project_details.tcl
}

if {![file exists $project_details_file]} {
    error "project details file does not exist: $project_details_file"
}

source $project_details_file

foreach required_variable {project_name top_module target} {
    if {![info exists $required_variable]} {
        error "$project_details_file does not define $required_variable"
    }
}

if {![info exists build_dir]} {
    set build_dir build
}

# Create project
proc create_new_project {project_name build_dir target top_module} {
    file mkdir ${build_dir}
    create_project ${project_name} ${build_dir} -part ${target} -force

    # read files from the variables provided by the project_details.tcl
    if {[info exists ::xdc_files]}     {read_xdc ${::xdc_files}}
    if {[info exists ::sv_files]}      {read_verilog -sv ${::sv_files}}
    if {[info exists ::verilog_files]} {read_verilog ${::verilog_files}}
    if {[info exists ::vhdl_files]}    {read_vhdl ${::vhdl_files}}
    if {[info exists ::mem_files]}     {read_mem ${::mem_files}}

    set_property top ${top_module} [current_fileset]
    update_compile_order -fileset sources_1
}


# Generate bitstream
proc require_completed_run {run_name} {
    set run_status [get_property STATUS [get_runs ${run_name}]]
    if {![string match "*Complete*" ${run_status}]} {
        error "Vivado run ${run_name} did not complete successfully: ${run_status}"
    }
}

proc generate_bitstream {build_dir top_module} {
    # Run synthesis
    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    require_completed_run synth_1

    # Run implemenatation up to bitstream generation
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    require_completed_run impl_1

    open_run impl_1
    report_timing_summary -file [file join ${build_dir} ${top_module}_timing_summary.rpt]
    report_utilization -file [file join ${build_dir} ${top_module}_utilization.rpt]
}


# MAIN
create_new_project $project_name $build_dir $target $top_module
generate_bitstream $build_dir $top_module
exit
