# Non-project synthesis for GA3B v1.0 minimal custom RTL top.
# This avoids Vivado project-run child process issues and validates the custom
# AXI-Lite/AXI-Stream shell plus pure3 accelerator hierarchy.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs v1_min_accel_synth]
file mkdir $run_dir
cd $run_dir

set part xc7z020clg400-2
read_verilog [file join $repo_root rtl ga_core ga3b_rng_xorshift32.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_fitness_lane.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_ga_core.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_accel_top.v]
read_verilog [file join $repo_root rtl top ga3b_v1_min_accel_top.v]
synth_design -top ga3b_v1_min_accel_top -part $part
create_clock -period 10.000 -name aclk [get_ports aclk]
report_utilization -file post_synth_util.rpt
report_timing_summary -file post_synth_timing.rpt
write_checkpoint -force post_synth.dcp
puts "GA3B_V1_MIN_ACCEL_SYNTH_DONE: $run_dir"