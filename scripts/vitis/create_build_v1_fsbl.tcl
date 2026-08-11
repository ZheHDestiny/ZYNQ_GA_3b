# Create and build a Zynq FSBL against the existing v1-min standalone platform.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set ws [file join $repo_root vitis_workspace v1_min_standalone]
set platform_name ga3b_v1_platform
set app_name ga3b_v1_fsbl

setws $ws
catch {app remove $app_name}
platform active $platform_name
set domains [domain list]
set domain_name standalone_domain
if {[string first $domain_name $domains] < 0} {
    set domain_name standalone_ps7_cortexa9_0
}
domain active $domain_name
bsp setlib -name xilffs
platform generate
app create -name $app_name -platform $platform_name -domain $domain_name -template {Zynq FSBL}
app build -name $app_name
set elf [file join $ws $app_name Debug ${app_name}.elf]
if {![file exists $elf]} { error "FSBL build did not produce: $elf" }
puts "GA3B_FSBL_BUILD_PASS: $elf"
