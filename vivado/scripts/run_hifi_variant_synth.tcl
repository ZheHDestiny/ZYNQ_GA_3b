# Non-project synthesis comparison for the two GA3B high-fidelity integrators.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set mode [expr {[llength $argv] > 0 ? [lindex $argv 0] : 0}]
set variant [expr {$mode == 0 ? "symplectic" : "leapfrog_cached"}]
set run_dir [file join $repo_root vivado runs hifi_${variant}_synth]
file mkdir $run_dir
cd $run_dir

set part xc7z020clg400-2
read_verilog [file join $repo_root rtl ga_core ga3b_rng_xorshift32.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_inv_r3_lut.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_hifi_force_pair.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_hifi_fitness_lane.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_fitness_lane.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_ga_core.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_accel_top.v]
read_verilog [file join $repo_root rtl top ga3b_v1_min_accel_top.v]
synth_design -top ga3b_v1_min_accel_top -part $part \
    -generic HIFI_ENABLE=1 -generic INTEGRATOR_MODE=$mode
create_clock -period 10.000 -name aclk [get_ports aclk]
report_utilization -hierarchical -file post_synth_util_hier.rpt
report_utilization -file post_synth_util.rpt
report_timing_summary -file post_synth_timing.rpt
write_checkpoint -force post_synth.dcp
puts "GA3B_HIFI_SYNTH_DONE variant=$variant mode=$mode run_dir=$run_dir"
