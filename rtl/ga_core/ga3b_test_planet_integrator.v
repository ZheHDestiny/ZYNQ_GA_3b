// SPDX-License-Identifier: MIT
// One-step massless test-planet integrator and restricted4 per-step metrics.
`timescale 1ns/1ps

module ga3b_test_planet_integrator #(
    parameter integer W = 32
)(
    input  wire signed [W-1:0] px,  input wire signed [W-1:0] py,
    input  wire signed [W-1:0] pvx, input wire signed [W-1:0] pvy,
    input  wire signed [W-1:0] sx0, input wire signed [W-1:0] sy0,
    input  wire signed [W-1:0] sx1, input wire signed [W-1:0] sy1,
    input  wire signed [W-1:0] sx2, input wire signed [W-1:0] sy2,
    output reg  signed [W-1:0] npx,  output reg signed [W-1:0] npy,
    output reg  signed [W-1:0] npvx, output reg signed [W-1:0] npvy,
    output reg  [31:0] dp0_2,
    output reg  [31:0] dp1_2,
    output reg  [31:0] dp2_2,
    output reg  [31:0] min_dp2,
    output reg  [1:0]  dominant_sun,
    output reg  [31:0] flux_proxy,
    output reg  [31:0] tidal_proxy
);
    localparam signed [31:0] Q_DT    = 32'sd256;
    localparam signed [31:0] SOFT_R2 = 32'sd64;

    reg signed [31:0] apx, apy, fax, fay;

    function signed [31:0] qmul;
        input signed [31:0] a; input signed [31:0] b;
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
        accel_pair(px, py, sx0, sy0, fax, fay); apx = fax; apy = fay;
        accel_pair(px, py, sx1, sy1, fax, fay); apx = apx + fax; apy = apy + fay;
        accel_pair(px, py, sx2, sy2, fax, fay); apx = apx + fax; apy = apy + fay;
        npvx = pvx + qmul(apx, Q_DT); npvy = pvy + qmul(apy, Q_DT);
        npx  = px  + qmul(npvx, Q_DT); npy  = py  + qmul(npvy, Q_DT);

        dp0_2 = dist2_q16(npx, npy, sx0, sy0);
        dp1_2 = dist2_q16(npx, npy, sx1, sy1);
        dp2_2 = dist2_q16(npx, npy, sx2, sy2);
        dominant_sun = 2'd0; min_dp2 = dp0_2;
        if (dp1_2 < min_dp2) begin min_dp2 = dp1_2; dominant_sun = 2'd1; end
        if (dp2_2 < min_dp2) begin min_dp2 = dp2_2; dominant_sun = 2'd2; end
        flux_proxy  = inv_r2_q16(dp0_2) + inv_r2_q16(dp1_2) + inv_r2_q16(dp2_2);
        tidal_proxy = flux_proxy;
    end
endmodule
