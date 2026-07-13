// SPDX-License-Identifier: MIT
// One-step 2D sun3 integrator for ZYNQ_GA_3b v0.3.
// Q16.16, equal-mass normalized G=1 prototype. sun2 is already decoded upstream.
`timescale 1ns/1ps

module ga3b_sun3_integrator #(
    parameter integer W = 32
)(
    input  wire signed [W-1:0] sx0,  input wire signed [W-1:0] sy0,
    input  wire signed [W-1:0] svx0, input wire signed [W-1:0] svy0,
    input  wire signed [W-1:0] sx1,  input wire signed [W-1:0] sy1,
    input  wire signed [W-1:0] svx1, input wire signed [W-1:0] svy1,
    input  wire signed [W-1:0] sx2,  input wire signed [W-1:0] sy2,
    input  wire signed [W-1:0] svx2, input wire signed [W-1:0] svy2,
    output reg  signed [W-1:0] nsx0,  output reg signed [W-1:0] nsy0,
    output reg  signed [W-1:0] nsvx0, output reg signed [W-1:0] nsvy0,
    output reg  signed [W-1:0] nsx1,  output reg signed [W-1:0] nsy1,
    output reg  signed [W-1:0] nsvx1, output reg signed [W-1:0] nsvy1,
    output reg  signed [W-1:0] nsx2,  output reg signed [W-1:0] nsy2,
    output reg  signed [W-1:0] nsvx2, output reg signed [W-1:0] nsvy2,
    output reg  [31:0] d01_2,
    output reg  [31:0] d02_2,
    output reg  [31:0] d12_2
);
    localparam signed [31:0] Q_DT    = 32'sd256; // 1/256
    localparam signed [31:0] SOFT_R2 = 32'sd64;

    reg signed [31:0] ax0, ay0, ax1, ay1, ax2, ay2;
    reg signed [31:0] fax, fay;

    function signed [31:0] qmul;
        input signed [31:0] a;
        input signed [31:0] b;
        reg signed [63:0] p;
        begin p = a * b; qmul = p >>> 16; end
    endfunction

    function [31:0] dist2_q16;
        input signed [31:0] ax; input signed [31:0] ay;
        input signed [31:0] bx; input signed [31:0] by;
        reg signed [31:0] dx; reg signed [31:0] dy;
        reg signed [31:0] xx; reg signed [31:0] yy;
        begin
            dx = bx - ax; dy = by - ay;
            xx = qmul(dx, dx); yy = qmul(dy, dy);
            dist2_q16 = (xx[31] || yy[31]) ? 32'h7fff_ffff : (xx + yy);
        end
    endfunction

    function signed [31:0] inv_r2_q16;
        input [31:0] r2;
        reg [63:0] numerator;
        reg [31:0] denom;
        begin
            denom = r2 + SOFT_R2;
            numerator = 64'd65536 << 16;
            inv_r2_q16 = numerator / denom;
        end
    endfunction

    task accel_pair;
        input signed [31:0] xi; input signed [31:0] yi;
        input signed [31:0] xj; input signed [31:0] yj;
        output signed [31:0] ax; output signed [31:0] ay;
        reg signed [31:0] dx; reg signed [31:0] dy;
        reg [31:0] r2; reg signed [31:0] invr2;
        begin
            dx = xj - xi; dy = yj - yi;
            r2 = dist2_q16(xi, yi, xj, yj);
            invr2 = inv_r2_q16(r2);
            ax = qmul(dx, invr2);
            ay = qmul(dy, invr2);
        end
    endtask

    always @(*) begin
        accel_pair(sx0, sy0, sx1, sy1, fax, fay); ax0 = fax; ay0 = fay;
        accel_pair(sx0, sy0, sx2, sy2, fax, fay); ax0 = ax0 + fax; ay0 = ay0 + fay;
        accel_pair(sx1, sy1, sx0, sy0, fax, fay); ax1 = fax; ay1 = fay;
        accel_pair(sx1, sy1, sx2, sy2, fax, fay); ax1 = ax1 + fax; ay1 = ay1 + fay;
        accel_pair(sx2, sy2, sx0, sy0, fax, fay); ax2 = fax; ay2 = fay;
        accel_pair(sx2, sy2, sx1, sy1, fax, fay); ax2 = ax2 + fax; ay2 = ay2 + fay;

        nsvx0 = svx0 + qmul(ax0, Q_DT); nsvy0 = svy0 + qmul(ay0, Q_DT);
        nsvx1 = svx1 + qmul(ax1, Q_DT); nsvy1 = svy1 + qmul(ay1, Q_DT);
        nsvx2 = svx2 + qmul(ax2, Q_DT); nsvy2 = svy2 + qmul(ay2, Q_DT);
        nsx0  = sx0  + qmul(nsvx0, Q_DT); nsy0 = sy0 + qmul(nsvy0, Q_DT);
        nsx1  = sx1  + qmul(nsvx1, Q_DT); nsy1 = sy1 + qmul(nsvy1, Q_DT);
        nsx2  = sx2  + qmul(nsvx2, Q_DT); nsy2 = sy2 + qmul(nsvy2, Q_DT);

        d01_2 = dist2_q16(nsx0, nsy0, nsx1, nsy1);
        d02_2 = dist2_q16(nsx0, nsy0, nsx2, nsy2);
        d12_2 = dist2_q16(nsx1, nsy1, nsx2, nsy2);
    end
endmodule
