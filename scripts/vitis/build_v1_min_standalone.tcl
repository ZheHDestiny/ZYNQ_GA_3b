# Resume/build an already-created v1-min Vitis application.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set ws [file join $repo_root vitis_workspace v1_min_standalone]
set app_name ga3b_dma_smoke
setws $ws
app build -name $app_name
set elf [file join $ws $app_name Debug ${app_name}.elf]
if {![file exists $elf]} { error "Vitis build did not produce ELF: $elf" }
puts "GA3B_VITIS_BUILD_PASS: $elf"
