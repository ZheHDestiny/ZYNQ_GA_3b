# Export the deliverables after the manually invoked impl_1 Tcl completes.
# `launch_runs` is intentionally not used on this Windows host because its
# rundef.js child launcher depends on unavailable WMI permissions.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs v1_min_bd]
set proj_file [file join $run_dir ga3b_v1_min_bd.xpr]
set impl_dir [file join $run_dir ga3b_v1_min_bd.runs impl_1]
set routed_dcp [file join $impl_dir ga3b_system_wrapper_routed.dcp]
set routed_bit [file join $impl_dir ga3b_system_wrapper.bit]
set artifact_dir [file join $run_dir artifacts]

if {![file exists $routed_dcp]} { error "Missing routed checkpoint: $routed_dcp" }
if {![file exists $routed_bit]} { error "Missing bitstream: $routed_bit" }
file mkdir $artifact_dir

open_project $proj_file
open_checkpoint $routed_dcp
report_utilization -file [file join $artifact_dir post_route_utilization.rpt]
report_timing_summary -delay_type max -max_paths 20 -file [file join $artifact_dir post_route_timing_summary.rpt]
report_timing_summary -delay_type min -max_paths 20 -file [file join $artifact_dir post_route_hold_summary.rpt]
report_drc -file [file join $artifact_dir post_route_drc.rpt]
file copy -force $routed_bit [file join $artifact_dir ga3b_v1_min.bit]
write_hw_platform -fixed -include_bit -force -file [file join $artifact_dir ga3b_v1_min.xsa]
puts "GA3B_V1_MIN_BITSTREAM_DONE: [file join $artifact_dir ga3b_v1_min.bit]"
puts "GA3B_V1_MIN_XSA_DONE: [file join $artifact_dir ga3b_v1_min.xsa]"
close_project
