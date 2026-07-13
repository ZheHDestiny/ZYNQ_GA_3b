set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs pure3_resource_fit]
open_checkpoint [file join $run_dir post_route.dcp]
reset_timing
create_clock -period 12.500 -name aclk [get_ports aclk]
report_timing_summary -file [file join $run_dir post_route_timing_80mhz.rpt]
report_utilization -file [file join $run_dir post_route_util_80mhz.rpt]
close_design