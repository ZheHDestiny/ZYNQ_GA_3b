# Vivado batch implementation for the additional pure3 resource-fit RTL.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs pure3_resource_fit]
file mkdir $run_dir
cd $run_dir

set part xc7z020clg400-2
read_verilog [file join $repo_root rtl ga_core ga3b_rng_xorshift32.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_fitness_lane.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_ga_core.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_accel_top.v]

synth_design -top ga3b_pure3_rf_accel_top -part $part
create_clock -period 10.000 -name aclk [get_ports aclk]
report_utilization -file post_synth_util.rpt
report_timing_summary -file post_synth_timing.rpt
write_checkpoint -force post_synth.dcp

opt_design
place_design
report_utilization -file post_place_util.rpt
report_timing_summary -file post_place_timing.rpt
write_checkpoint -force post_place.dcp

route_design
report_utilization -file post_route_util.rpt
report_timing_summary -file post_route_timing.rpt
write_checkpoint -force post_route.dcp
write_bitstream -force ga3b_pure3_rf_accel_top.bit
