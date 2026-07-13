# Generate standard project run Tcl without invoking rundef.js.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs v1_min_bd]
set proj_file [file join $run_dir ga3b_v1_min_bd.xpr]
open_project $proj_file
set_property top ga3b_system_wrapper [get_filesets sources_1]
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -scripts_only
puts "GA3B_V1_MIN_SYNTH_SCRIPT: [file join $run_dir ga3b_v1_min_bd.runs synth_1 ga3b_system_wrapper.tcl]"
close_project