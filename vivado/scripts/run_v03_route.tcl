set root_dir [file normalize [file join [file dirname [info script]] ../..]]
set run_dir  [file normalize [file join $root_dir vivado/runs/v03_route]]
file mkdir $run_dir
cd $run_dir

set part_name xc7z020clg400-2
set top_name ga3b_heng_era_accel_top

read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_rng_xorshift32.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_sun3_integrator.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_test_planet_integrator.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_heng_era_metric_accumulator.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_pure3_fallback_fitness_lane.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_heng_era_fitness_lane.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_fitness_lane.v]
read_verilog -sv [file join $root_dir rtl/ga_core/ga3b_ga_core.v]
read_verilog -sv [file join $root_dir rtl/top/ga3b_heng_era_accel_top.v]

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt
create_clock -period 10.000 -name aclk [get_ports aclk]
write_checkpoint -force [file join $run_dir post_synth.dcp]
report_utilization -file [file join $run_dir post_synth_util.rpt]
report_timing_summary -file [file join $run_dir post_synth_timing.rpt]

opt_design
place_design
write_checkpoint -force [file join $run_dir post_place.dcp]
report_utilization -file [file join $run_dir post_place_util.rpt]
report_timing_summary -file [file join $run_dir post_place_timing.rpt]

route_design
write_checkpoint -force [file join $run_dir post_route.dcp]
report_utilization -file [file join $run_dir post_route_util.rpt]
report_timing_summary -file [file join $run_dir post_route_timing.rpt]
report_route_status -file [file join $run_dir post_route_status.rpt]

puts "GA3B_IMPL_DONE run_dir=$run_dir"
