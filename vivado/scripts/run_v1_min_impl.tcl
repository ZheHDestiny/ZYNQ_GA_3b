# Build the GA3B v1-min PS+DMA+PL BD without launch_runs.
# Direct commands avoid the Windows rundef.js/WMI child-process failure.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir   [file join $repo_root vivado runs v1_min_bd]
set proj_file [file join $run_dir ga3b_v1_min_bd.xpr]
set artifact_dir [file join $run_dir artifacts]
set part xc7z020clg400-2

if {![file exists $proj_file]} {
    error "Project is missing: $proj_file. Run create_v1_min_bd.tcl first."
}
file mkdir $artifact_dir
open_project $proj_file
set_property top ga3b_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# Synthesize the BD child IPs in-process first. This produces the OOC checkpoints
# normally launched by project runs, but avoids rundef.js/WMI on this Windows host.
synth_ip -force [get_ips]
# Run all implementation stages in this Vivado process.  Do not use launch_runs:
# its generated rundef.js requires WMI permissions unavailable on this host.
synth_design -top ga3b_system_wrapper -part $part
write_checkpoint -force [file join $artifact_dir post_synth.dcp]
report_utilization -file [file join $artifact_dir post_synth_utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 -file [file join $artifact_dir post_synth_timing_summary.rpt]

opt_design
place_design
phys_opt_design
route_design
phys_opt_design -directive Explore
write_checkpoint -force [file join $artifact_dir post_route.dcp]
report_utilization -file [file join $artifact_dir post_route_utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 -file [file join $artifact_dir post_route_timing_summary.rpt]
report_timing_summary -delay_type min -max_paths 10 -file [file join $artifact_dir post_route_hold_summary.rpt]
report_drc -file [file join $artifact_dir post_route_drc.rpt]

set bit_file [file join $artifact_dir ga3b_v1_min.bit]
write_bitstream -force -bin_file $bit_file
if {![file exists $bit_file]} {
    error "Bitstream was not generated: $bit_file"
}
# Include the bitstream and the BD handoff in an XSA for the standalone PS app.
write_hw_platform -fixed -include_bit -force -file [file join $artifact_dir ga3b_v1_min.xsa]
puts "GA3B_V1_MIN_BITSTREAM_DONE: $bit_file"
puts "GA3B_V1_MIN_XSA_DONE: [file join $artifact_dir ga3b_v1_min.xsa]"
close_project