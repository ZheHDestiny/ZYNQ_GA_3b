// SPDX-License-Identifier: MIT
// GA3B v1.0 minimal PS/PL integration top.
//
// This top is intended for Vivado Block Design connection:
//   PS DDR <-> AXI DMA <-> AXI4-Stream <-> pure3 resource-fit GA accelerator
//   PS M_AXI_GP0 <-> AXI4-Lite <-> small control/status register bank
//   irq_out -> PS IRQ_F2P
//
// The SearchTask and SearchResult payload still travel through AXI DMA streams.
// AXI4-Lite is deliberately kept minimal: ID/version/status/IRQ enable/reset.
`timescale 1ns/1ps

module ga3b_v1_min_accel_top #(
    parameter integer GENE_COUNT    = 8,
    parameter integer GENE_WIDTH    = 32,
    parameter integer FITNESS_WIDTH = 64,
    parameter integer HIFI_ENABLE   = 1,
    parameter integer INTEGRATOR_MODE = 0
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input  wire                         aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                         aresetn,

    // AXI4-Stream task input from AXI DMA MM2S.
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *)
    input  wire [31:0]                  s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *)
    input  wire                         s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *)
    output wire                         s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *)
    input  wire                         s_axis_tlast,

    // AXI4-Stream result output to AXI DMA S2MM.
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *)
    output wire [31:0]                  m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output wire                         m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire                         m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output wire                         m_axis_tlast,

    // Minimal AXI4-Lite slave register interface.
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 100000000" *)
    input  wire                         s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                         s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [5:0]                   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                   s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                         s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg                          s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0]                  s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]                   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                         s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                          s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg  [1:0]                   s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                          s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                         s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [5:0]                   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                   s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                         s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                          s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0]                  s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg  [1:0]                   s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                          s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                         s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 IRQ_OUT INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire                         irq_out
);
    localparam [31:0] REG_VERSION = 32'h0001_0000;
    localparam [31:0] REG_PROFILE = (HIFI_ENABLE == 0) ? 32'h0000_0003 :
                                        ((INTEGRATOR_MODE == 0) ? 32'h0000_0004 : 32'h0000_0005);

    // Register map, word offsets:
    // 0x00 CTRL    bit0 accel_enable(default 1), bit1 irq_enable, bit2 clear_done W1P, bit3 soft_reset W1P
    // 0x04 STATUS  bit0 done_latched, bit1 proto_error_latched, bit2 accel_irq_raw, bit3 irq_out, bit8 enabled
    // 0x08 VERSION 0x00010000
    // 0x0c PROFILE 3=legacy pure3_rf, 4=HiFi symplectic, 5=HiFi cached Leapfrog
    // 0x10 RAW     {30'd0, proto_error_raw, accel_irq_raw}
    reg accel_enable;
    reg irq_enable;
    reg done_latched;
    reg proto_error_latched;
    reg soft_reset_hold;

    wire accel_irq_raw;
    wire proto_error_raw;
    wire accel_aresetn = aresetn & accel_enable & ~soft_reset_hold;

    assign irq_out = irq_enable & done_latched;

    ga3b_pure3_rf_accel_top #(
        .GENE_COUNT(GENE_COUNT),
        .GENE_WIDTH(GENE_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .HIFI_ENABLE(HIFI_ENABLE),
        .INTEGRATOR_MODE(INTEGRATOR_MODE)
    ) u_accel (
        .aclk(aclk),
        .aresetn(accel_aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .irq_done(accel_irq_raw),
        .proto_error(proto_error_raw)
    );

    function [31:0] apply_wstrb;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  strobe;
        begin
            apply_wstrb[7:0]   = strobe[0] ? newv[7:0]   : oldv[7:0];
            apply_wstrb[15:8]  = strobe[1] ? newv[15:8]  : oldv[15:8];
            apply_wstrb[23:16] = strobe[2] ? newv[23:16] : oldv[23:16];
            apply_wstrb[31:24] = strobe[3] ? newv[31:24] : oldv[31:24];
        end
    endfunction

    function [31:0] read_reg;
        input [5:0] addr;
        begin
            case (addr[5:2])
                4'h0: read_reg = {28'd0, 1'b0, 1'b0, irq_enable, accel_enable};
                4'h1: read_reg = {23'd0, accel_enable, 4'd0, irq_out, accel_irq_raw, proto_error_latched, done_latched};
                4'h2: read_reg = REG_VERSION;
                4'h3: read_reg = REG_PROFILE;
                4'h4: read_reg = {30'd0, proto_error_raw, accel_irq_raw};
                default: read_reg = 32'd0;
            endcase
        end
    endfunction

    reg [31:0] ctrl_next;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            accel_enable <= 1'b1;
            irq_enable <= 1'b0;
            done_latched <= 1'b0;
            proto_error_latched <= 1'b0;
            soft_reset_hold <= 1'b0;
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;
            soft_reset_hold <= 1'b0;

            if (accel_irq_raw)
                done_latched <= 1'b1;
            if (proto_error_raw)
                proto_error_latched <= 1'b1;

            // Single-beat AXI4-Lite write. PS drivers issue AW/W together for these registers.
            if (!s_axi_bvalid && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready <= 1'b1;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                if (s_axi_awaddr[5:2] == 4'h0) begin
                    ctrl_next = apply_wstrb({28'd0, 1'b0, 1'b0, irq_enable, accel_enable}, s_axi_wdata, s_axi_wstrb);
                    accel_enable <= ctrl_next[0];
                    irq_enable <= ctrl_next[1];
                    if (ctrl_next[2]) begin
                        done_latched <= 1'b0;
                        proto_error_latched <= 1'b0;
                    end
                    if (ctrl_next[3]) begin
                        soft_reset_hold <= 1'b1;
                        done_latched <= 1'b0;
                        proto_error_latched <= 1'b0;
                    end
                end
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Single outstanding AXI4-Lite read.
            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                s_axi_rdata <= read_reg(s_axi_araddr);
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
