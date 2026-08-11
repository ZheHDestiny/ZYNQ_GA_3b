# Generate (but do not launch) the project implementation Tcl.
# The generated Tcl consumes synth_1/ga3b_system_wrapper.dcp and the completed
# OOC IP checkpoints.  It avoids Vivado's Windows rundef.js/WMI launcher.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs v1_min_bd]
set proj_file [file join $run_dir ga3b_v1_min_bd.xpr]
set synth_dcp [file join $run_dir ga3b_v1_min_bd.runs synth_1 ga3b_system_wrapper.dcp]

if {![file exists $synth_dcp]} {
    error "Top synthesis checkpoint is missing: $synth_dcp"
}
open_project $proj_file
set_property top ga3b_system_wrapper [get_filesets sources_1]
# A manually terminated generated run leaves the project status at "Running".
# Always reset only impl_1 here; synth_1 is the verified input checkpoint and
# must be preserved for deterministic resume.
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -scripts_only
puts "GA3B_V1_MIN_IMPL_SCRIPT: [file join $run_dir ga3b_v1_min_bd.runs impl_1 ga3b_system_wrapper.tcl]"
close_project
