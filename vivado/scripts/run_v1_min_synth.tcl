# Compatibility wrapper: use the verified single-process custom RTL synthesis.
# Full BD generation is handled by create_v1_min_bd.tcl; this script checks the
# synthesizable GA3B v1.0 accelerator shell without Vivado project-run spawning.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir run_v1_min_accel_synth.tcl]