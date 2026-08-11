# Download the routed v1-min bitstream and persistent UART board-agent ELF.
# Usage: xsct download_v1_uart_agent.tcl <bit> <elf> <ps7_init.tcl>

if {$argc != 3} {
    error "usage: download_v1_uart_agent.tcl <bit> <elf> <ps7_init.tcl>"
}
set bit_file [file normalize [lindex $argv 0]]
set elf_file [file normalize [lindex $argv 1]]
set ps_init  [file normalize [lindex $argv 2]]
foreach f [list $bit_file $elf_file $ps_init] {
    if {![file exists $f]} { error "missing download input: $f" }
}

connect -url tcp:127.0.0.1:3121
puts "GA3B_XSDB_CONNECTED"
targets -set -filter {name =~ "APU"}
rst -system
after 2000
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
stop
puts "GA3B_CPU0_STOPPED"
fpga -file $bit_file
puts "GA3B_BITSTREAM_PROGRAMMED"
source $ps_init
ps7_init
ps7_post_config
puts "GA3B_PS7_INITIALIZED"
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
rst -processor
dow $elf_file
puts "GA3B_UART_AGENT_DOWNLOADED"
con
puts "GA3B_CPU0_RUNNING"
after 500
disconnect
exit
