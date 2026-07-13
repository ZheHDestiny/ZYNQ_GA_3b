# Create GA3B v1.0 minimal Zynq PS + AXI DMA + PL accelerator block design.
# Target: xc7z020clg400-2. This script is intentionally board-agnostic;
# it exports PS DDR/FIXED_IO and uses FCLK0=100 MHz for PL.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set run_dir   [file join $repo_root vivado runs v1_min_bd]
file mkdir $run_dir
cd $run_dir

set part xc7z020clg400-2
set proj_name ga3b_v1_min_bd

create_project -force $proj_name $run_dir -part $part
set_property target_language Verilog [current_project]

read_verilog [file join $repo_root rtl ga_core ga3b_rng_xorshift32.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_fitness_lane.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_ga_core.v]
read_verilog [file join $repo_root rtl pure3_core ga3b_pure3_rf_accel_top.v]
read_verilog [file join $repo_root rtl top ga3b_v1_min_accel_top.v]
update_compile_order -fileset sources_1

create_bd_design ga3b_system

# Processing System 7
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
] [get_bd_cells ps7_0]

# AXI DMA in simple mode. MM2S sends SearchTask to PL; S2MM receives SearchResult.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_sg_length_width {23} \
] [get_bd_cells axi_dma_0]

# RTL module instance: pure3 resource-fit profile wrapped with AXI-Lite status regs.
create_bd_cell -type module -reference ga3b_v1_min_accel_top ga3b_accel_0

# Reset and interconnect IP.
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_fclk0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ctrl_intercon
set_property CONFIG.NUM_MI 2 [get_bd_cells axi_ctrl_intercon]
set_property CONFIG.NUM_SI 1 [get_bd_cells axi_ctrl_intercon]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_hp_intercon
set_property CONFIG.NUM_MI 1 [get_bd_cells axi_hp_intercon]
set_property CONFIG.NUM_SI 2 [get_bd_cells axi_hp_intercon]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat
set_property CONFIG.NUM_PORTS 3 [get_bd_cells irq_concat]

# Export PS DDR/FIXED_IO for the top-level BD wrapper.
make_bd_intf_pins_external [get_bd_intf_pins ps7_0/DDR]
set_property name DDR [get_bd_intf_ports DDR_0]
make_bd_intf_pins_external [get_bd_intf_pins ps7_0/FIXED_IO]
set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]

# Clocking: PS FCLK0 drives all PL AXI and accelerator clocks.
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins rst_fclk0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ps7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ps7_0/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ga3b_accel_0/aclk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ga3b_accel_0/s_axi_aclk]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_ctrl_intercon/ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_ctrl_intercon/S00_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_ctrl_intercon/M00_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_ctrl_intercon/M01_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_hp_intercon/ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_hp_intercon/S00_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_hp_intercon/S01_ACLK]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins axi_hp_intercon/M00_ACLK]

# Reset. FCLK_RESET0_N is used as the upstream reset source.
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_fclk0/ext_reset_in]
connect_bd_net [get_bd_pins rst_fclk0/peripheral_aresetn] [get_bd_pins axi_dma_0/axi_resetn]
connect_bd_net [get_bd_pins rst_fclk0/peripheral_aresetn] [get_bd_pins ga3b_accel_0/aresetn]
connect_bd_net [get_bd_pins rst_fclk0/peripheral_aresetn] [get_bd_pins ga3b_accel_0/s_axi_aresetn]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_ctrl_intercon/ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_ctrl_intercon/S00_ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_ctrl_intercon/M00_ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_ctrl_intercon/M01_ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_hp_intercon/ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_hp_intercon/S00_ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_hp_intercon/S01_ARESETN]
connect_bd_net [get_bd_pins rst_fclk0/interconnect_aresetn] [get_bd_pins axi_hp_intercon/M00_ARESETN]

# AXI-Lite control path: PS GP0 -> DMA regs + GA3B regs.
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] [get_bd_intf_pins axi_ctrl_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_intercon/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_intercon/M01_AXI] [get_bd_intf_pins ga3b_accel_0/S_AXI]

# DMA memory path: DMA masters -> PS HP0 DDR slave port.
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_hp_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_hp_intercon/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_hp_intercon/M00_AXI] [get_bd_intf_pins ps7_0/S_AXI_HP0]

# DMA streams.
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins ga3b_accel_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins ga3b_accel_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# Interrupts: DMA MM2S, DMA S2MM, accelerator done -> PS IRQ_F2P.
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins ga3b_accel_0/irq_out] [get_bd_pins irq_concat/In2]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins ps7_0/IRQ_F2P]

assign_bd_address
# Prefer stable base addresses for PS software. AXI DMA usually lands at 0x40400000
# automatically; the inferred RTL-module AXI-Lite segment is named reg0.
set accel_seg [get_bd_addr_segs -quiet ps7_0/Data/SEG_ga3b_accel_0_reg0]
if {[llength $accel_seg] > 0} {
    set_property offset 0x43C00000 $accel_seg
    set_property range 64K $accel_seg
}
set dma_seg [get_bd_addr_segs -quiet ps7_0/Data/SEG_axi_dma_0_Reg]
if {[llength $dma_seg] > 0} {
    set_property offset 0x40400000 $dma_seg
    set_property range 64K $dma_seg
}

validate_bd_design
save_bd_design

make_wrapper -files [get_files [file join $run_dir $proj_name.srcs sources_1 bd ga3b_system ga3b_system.bd]] -top
add_files -norecurse [file join $run_dir $proj_name.gen sources_1 bd ga3b_system hdl ga3b_system_wrapper.v]
set_property top ga3b_system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

# Generate HDL products and leave a project ready for bitstream generation/export to Vitis.
generate_target all [get_files [file join $run_dir $proj_name.srcs sources_1 bd ga3b_system ga3b_system.bd]]
puts "GA3B_V1_MIN_BD_CREATED: $run_dir"