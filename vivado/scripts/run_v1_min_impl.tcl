# Compatibility entry point for the v1-min implementation deliverables.
#
# Do not call synth_ip here: IP Integrator OOC children must be synthesized by
# their generated run Tcl files, otherwise Vivado raises [Vivado 12-3424].
# The Windows WMI/rundef.js restriction is handled by the PowerShell launchers:
#   1. prepare_v1_min_project_runs.tcl + run_v1_min_ooc_ip_synth.ps1
#   2. synth_1/ga3b_system_wrapper.tcl (manual child Vivado invocation)
#   3. prepare_v1_min_impl_run.tcl + impl_1/ga3b_system_wrapper.tcl
# This entry point performs the final, repeatable artifacts export.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir export_v1_min_artifacts.tcl]
