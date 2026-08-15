// SPDX-License-Identifier: MIT
// Shared, multi-cycle Q16.32 force datapath for the high-fidelity Pure3 lane.
// It evaluates a = GM * delta / |delta|^3 with a normalized smooth LUT and
// linear interpolation.  One 48x48 registered multiplier is reused for both
// distance and force components to keep the Zynq-7020 implementation small.
`timescale 1ns/1ps

module ga3b_pure3_hifi_force_pair(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [47:0]      dx,
    input  wire signed [47:0]      dy,
    output reg                     busy,
    output reg                     done,
    output reg signed [47:0]       fx,
    output reg signed [47:0]       fy
);
    localparam [4:0] S_IDLE=0, S_X_WAIT=1, S_X_CAP=2, S_Y_WAIT=3, S_Y_CAP=4;
    localparam [4:0] S_NORM=5, S_LUT_W1=6, S_LUT_W2=7, S_IP_SETUP=8;
    localparam [4:0] S_IP_WAIT=9, S_IP_CAP=10, S_SCALE=11;
    localparam [4:0] S_FX_WAIT=12, S_FX_CAP=13, S_FY_WAIT=14, S_FY_CAP=15;
    localparam [4:0] S_R2_REG=16;

    // 0.125^2 in Q32.32.  Clamping here makes close approaches finite; the
    // lane still declares collision using the independent 0.125 L1 metric.
    localparam [63:0] R2_SOFT_MIN = 64'd67108864;

    reg [4:0] state;
    reg signed [47:0] dx_r, dy_r;
    reg signed [47:0] mul_a, mul_b;
    reg signed [95:0] mul_p;
    reg [63:0] r2_x, r2_y, r2_stage;
    reg [7:0] lut_index;
    reg [7:0] lut_frac;
    reg lut_odd;
    reg signed [7:0] q_exp;
    wire [39:0] lut_y0, lut_y1;
    reg signed [47:0] coeff_base;

    wire [64:0] r2_sum_wide = {1'b0,r2_x} + {1'b0,r2_y};
    wire [63:0] r2_raw = r2_sum_wide[64] ? 64'hffff_ffff_ffff_ffff : r2_sum_wide[63:0];
    wire [63:0] r2_safe = (r2_raw < R2_SOFT_MIN) ? R2_SOFT_MIN : r2_raw;

    function [5:0] msb64;
        input [63:0] value;
        integer i;
        begin
            msb64 = 0;
            // Ascending priority encoder: each higher asserted bit replaces
            // the previous result.  This form is handled consistently by
            // both XSim and Vivado synthesis around the 2^32 boundary.
            for (i=0; i<64; i=i+1)
                if (value[i]) msb64 = i;
        end
    endfunction

    wire [5:0] r2_msb = msb64(r2_stage);
    wire signed [7:0] k_exp_w = $signed({1'b0,r2_msb}) - 8'sd32;
    wire [63:0] r2_norm = (r2_msb >= 6'd32)
                          ? (r2_stage >> (r2_msb-6'd32))
                          : (r2_stage << (6'd32-r2_msb));

    function signed [47:0] scaled_coeff;
        input signed [47:0] base;
        input signed [7:0] q;
        reg signed [8:0] shift3;
        reg signed [63:0] wide;
        begin
            shift3 = q * 3;
            wide = {{16{base[47]}},base};
            if (shift3 >= 0)
                wide = wide >>> shift3;
            else if (-shift3 >= 9'd15)
                wide = wide <<< 15;
            else
                wide = wide <<< (-shift3);
            if (wide > 64'sh0000_7fff_ffff_ffff)
                scaled_coeff = 48'sh7fff_ffff_ffff;
            else if (wide < 0)
                scaled_coeff = 48'sd0;
            else
                scaled_coeff = wide[47:0];
        end
    endfunction

    ga3b_pure3_inv_r3_lut u_lut(
        .clk(clk), .index(lut_index), .odd_exponent(lut_odd),
        .y0(lut_y0), .y1(lut_y1));

    // A single inferred multiplier.  FSM wait states make its registered
    // latency explicit and prevent a large combinational path into the lane.
    always @(posedge clk)
        mul_p <= mul_a * mul_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0;
            dx_r <= 0; dy_r <= 0; mul_a <= 0; mul_b <= 0; r2_x <= 0; r2_y <= 0; r2_stage <= R2_SOFT_MIN;
            lut_index <= 0; lut_frac <= 0; lut_odd <= 0; q_exp <= 0;
            coeff_base <= 0; fx <= 0; fy <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; dx_r <= dx; dy_r <= dy;
                        mul_a <= dx; mul_b <= dx; state <= S_X_WAIT;
                    end
                end
                S_X_WAIT: state <= S_X_CAP;
                S_X_CAP: begin
                    r2_x <= mul_p[95] ? 64'd0 : (mul_p >>> 32);
                    mul_a <= dy_r; mul_b <= dy_r; state <= S_Y_WAIT;
                end
                S_Y_WAIT: state <= S_Y_CAP;
                S_Y_CAP: begin
                    r2_y <= mul_p[95] ? 64'd0 : (mul_p >>> 32);
                    state <= S_R2_REG;
                end
                S_R2_REG: begin r2_stage <= r2_safe; state <= S_NORM; end
                S_NORM: begin
                    lut_index <= r2_norm[31:24];
                    lut_frac <= r2_norm[23:16];
                    lut_odd <= k_exp_w[0];
                    q_exp <= k_exp_w >>> 1;
                    state <= S_LUT_W1;
                end
                S_LUT_W1: state <= S_LUT_W2;
                S_LUT_W2: state <= S_IP_SETUP;
                S_IP_SETUP: begin
                    mul_a <= $signed({8'd0,lut_y0});
                    mul_b <= $signed({40'd0,lut_frac});
                    // Interpolate as y0 + (y1-y0)*frac/256.  The multiply
                    // below uses a positive magnitude and subtraction.
                    mul_a <= $signed({8'd0,(lut_y0-lut_y1)});
                    state <= S_IP_WAIT;
                end
                S_IP_WAIT: state <= S_IP_CAP;
                S_IP_CAP: begin
                    coeff_base <= $signed({8'd0,lut_y0}) - (mul_p >>> 8);
                    state <= S_SCALE;
                end
                S_SCALE: begin
                    mul_a <= dx_r;
                    mul_b <= scaled_coeff(coeff_base, q_exp);
                    state <= S_FX_WAIT;
                end
                S_FX_WAIT: state <= S_FX_CAP;
                S_FX_CAP: begin
                    fx <= mul_p >>> 32;
                    mul_a <= dy_r;
                    mul_b <= scaled_coeff(coeff_base, q_exp);
                    state <= S_FY_WAIT;
                end
                S_FY_WAIT: state <= S_FY_CAP;
                S_FY_CAP: begin
                    fy <= mul_p >>> 32;
                    busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
