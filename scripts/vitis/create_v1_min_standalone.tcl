# XSCT/Vitis 2023.2 project creation and build for the v1-min DMA smoke test.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set ws [file join $repo_root vitis_workspace v1_min_standalone]
set xsa [file join $repo_root vivado runs v1_min_bd artifacts ga3b_v1_min.xsa]
set app_src [file join $repo_root ps_app board_agent standalone ga3b_dma_smoke.c]
set protocol [file join $repo_root ps_app common ga3b_protocol.h]

if {![file exists $xsa]} { error "Missing XSA: $xsa" }
file mkdir $ws
setws $ws

set platform_name ga3b_v1_platform
set app_name ga3b_dma_smoke
catch {app remove $app_name}
catch {platform remove $platform_name}

platform create -name $platform_name -hw $xsa -proc ps7_cortexa9_0 -os standalone
platform write
platform generate

set domains [domain list]
puts "GA3B_VITIS_DOMAINS: $domains"
set domain_name standalone_domain
if {[string first $domain_name $domains] < 0} {
    # Vitis may derive the domain name from processor/OS.
    set domain_name standalone_ps7_cortexa9_0
}
app create -name $app_name -platform $platform_name -domain $domain_name -template {Empty Application(C)}
set src_dir [file join $ws $app_name src]
file copy -force $app_src [file join $src_dir ga3b_dma_smoke.c]
file copy -force $protocol [file join $src_dir ga3b_protocol.h]
puts "GA3B_VITIS_PROJECT_CREATED: [file join $ws $app_name]"
puts "GA3B_VITIS_NEXT: run scripts/run/build_v1_min_standalone.ps1"
