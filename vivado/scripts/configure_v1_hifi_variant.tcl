# Configure the existing, board-verified PS+DMA block design for one high-
# fidelity integrator variant without changing the vendor PS7 preset.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir [file join $repo_root vivado runs v1_min_bd]
set proj_file [file join $run_dir ga3b_v1_min_bd.xpr]
set mode [expr {[llength $argv] > 0 ? [lindex $argv 0] : 0}]
set variant [expr {$mode == 0 ? "symplectic" : "leapfrog_cached"}]

open_project $proj_file
foreach f [list \
    [file join $repo_root rtl pure3_core ga3b_pure3_inv_r3_lut.v] \
    [file join $repo_root rtl pure3_core ga3b_pure3_hifi_force_pair.v] \
    [file join $repo_root rtl pure3_core ga3b_pure3_hifi_fitness_lane.v]] {
    if {[llength [get_files -quiet $f]] == 0} { add_files -norecurse $f }
}
update_compile_order -fileset sources_1
open_bd_design [file join $run_dir ga3b_v1_min_bd.srcs sources_1 bd ga3b_system ga3b_system.bd]
# The original module-reference metadata intentionally remains interface-
# compatible with the deployed design.  The generated synthesis wrapper is
# parameterized by scripts/run/set_v1_hifi_generated_variant.ps1 after target
# generation; this avoids disturbing the board-verified BD wiring/preset.
validate_bd_design
save_bd_design
generate_target all [get_files ga3b_system.bd]
set custom_run ga3b_system_ga3b_accel_0_0_synth_1
reset_run $custom_run
launch_runs $custom_run -scripts_only
reset_run synth_1
reset_run impl_1
puts "GA3B_HIFI_BD_CONFIGURED variant=$variant mode=$mode"
close_project
