// SPDX-License-Identifier: MIT
// Restricted-four-body heng-era fitness lane for ZYNQ_GA_3b v0.3.
//
// This module replaces the previous proxy fitness stub with a synthesizable
// fixed-point evaluator:
//   - pure3 mode:     three suns only, 2D, sun2 derived from COM constraints.
//   - restricted4:   three suns + one massless test planet, 2D.
//
// Notes for v0.3:
//   * Q16.16 arithmetic is used throughout.
//   * The force law uses a hardware-cheap softened inverse-r2 directional
//     approximation rather than a full 1/r^3 Newtonian pipeline. The later
//     math/ pipeline can replace force_pair_accel() with LUT+NR invsqrt.
//   * Metrics are hardware-oriented: collision/escape early reject, dominant
//     sun switches, habitable radius window, flux/tidal proxies, heng window.

`timescale 1ns/1ps

module ga3b_heng_era_fitness_lane_stub #(
    parameter integer GENE_WIDTH    = 32,
    parameter integer GENE_MAX      = 18,
    parameter integer FITNESS_WIDTH = 64
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [1:0]                     model_mode,   // 0: pure3, 1: restricted4
    input  wire [5:0]                     gene_count,
    input  wire [31:0]                    steps_limit,
    input  wire [GENE_WIDTH*GENE_MAX-1:0] genes_flat,
    output reg                            busy,
    output reg                            done,
    output reg  [FITNESS_WIDTH-1:0]       fitness,
    output reg  [31:0]                    best_heng_steps,
    output reg                            valid_candidate
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_RUN  = 3'd1;
    localparam [2:0] S_DONE = 3'd2;

    localparam signed [31:0] Q_ONE      = 32'sd65536;
    localparam signed [31:0] Q_DT       = 32'sd256;      // 1/256 normalized time
    localparam signed [31:0] SOFT_R2    = 32'sd64;
    localparam signed [31:0] SUN_DMIN2  = 32'sd164;      // about 0.05^2 in Q16.16
    localparam signed [31:0] SUN_RMAX2  = 32'sd6553600;  // 10^2 in Q16.16
    localparam signed [31:0] PL_DMIN2   = 32'sd164;
    localparam signed [31:0] PL_RMAX2   = 32'sd6553600;
    localparam signed [31:0] HAB_MIN2   = 32'sd16384;    // 0.5^2 in Q16.16
    localparam signed [31:0] HAB_MAX2   = 32'sd589824;   // 3.0^2 in Q16.16
    localparam [31:0]        TIDAL_MAX  = 32'd262144;    // proxy threshold

    reg [2:0] state;
    reg [31:0] step_counter;
    reg [31:0] run_steps;
    reg failed;

    // 2D states for three suns and one massless planet.
    reg signed [31:0] sx0, sy0, svx0, svy0;
    reg signed [31:0] sx1, sy1, svx1, svy1;
    reg signed [31:0] sx2, sy2, svx2, svy2;
    reg signed [31:0] px,  py,  pvx,  pvy;

    reg signed [31:0] nsx0, nsy0, nsvx0, nsvy0;
    reg signed [31:0] nsx1, nsy1, nsvx1, nsvy1;
    reg signed [31:0] nsx2, nsy2, nsvx2, nsvy2;
    reg signed [31:0] npx,  npy,  npvx,  npvy;

    reg signed [31:0] ax0, ay0, ax1, ay1, ax2, ay2, apx, apy;
    reg signed [31:0] fax, fay;

    reg [31:0] current_heng;
    reg [31:0] capture_switch_count;
    reg [1:0]  dominant_sun;
    reg [1:0]  prev_dominant_sun;
    reg [63:0] penalty_accum;
    reg [31:0] survived_steps;

    reg [31:0] d01_2, d02_2, d12_2;
    reg [31:0] dp0_2, dp1_2, dp2_2;
    reg [31:0] min_dp2;
    reg [31:0] flux_proxy;
    reg [31:0] tidal_proxy;
    reg is_heng_step;

    function signed [31:0] gene_at;
        input integer idx;
        begin
            gene_at = genes_flat[idx*GENE_WIDTH +: GENE_WIDTH];
        end
    endfunction

    function signed [31:0] qmul;
        input signed [31:0] a;
        input signed [31:0] b;
        reg signed [63:0] p;
        begin
            p = a * b;
            qmul = p >>> 16;
        end
    endfunction

    function [31:0] abs32;
        input signed [31:0] a;
        begin
            abs32 = a[31] ? (~a + 32'd1) : a;
        end
    endfunction

    function [31:0] dist2_q16;
        input signed [31:0] ax;
        input signed [31:0] ay;
        input signed [31:0] bx;
        input signed [31:0] by;
        reg signed [31:0] dx;
        reg signed [31:0] dy;
        reg signed [31:0] xx;
        reg signed [31:0] yy;
        begin
            dx = bx - ax;
            dy = by - ay;
            xx = qmul(dx, dx);
            yy = qmul(dy, dy);
            dist2_q16 = xx[31] || yy[31] ? 32'h7fff_ffff : (xx + yy);
        end
    endfunction

    function signed [31:0] inv_r2_q16;
        input [31:0] r2;
        reg [63:0] numerator;
        reg [31:0] denom;
        begin
            denom = r2 + SOFT_R2;
            numerator = 64'd65536 << 16; // Q16.16 one shifted for division result
            inv_r2_q16 = numerator / denom;
        end
    endfunction

    task add_accel_pair;
        input signed [31:0] xi;
        input signed [31:0] yi;
        input signed [31:0] xj;
        input signed [31:0] yj;
        output signed [31:0] ax;
        output signed [31:0] ay;
        reg signed [31:0] dx;
        reg signed [31:0] dy;
        reg [31:0] r2;
        reg signed [31:0] invr2;
        begin
            dx = xj - xi;
            dy = yj - yi;
            r2 = dist2_q16(xi, yi, xj, yj);
            invr2 = inv_r2_q16(r2);
            ax = qmul(dx, invr2);
            ay = qmul(dy, invr2);
        end
    endtask

    always @(*) begin
        // sun accelerations
        add_accel_pair(sx0, sy0, sx1, sy1, fax, fay); ax0 = fax; ay0 = fay;
        add_accel_pair(sx0, sy0, sx2, sy2, fax, fay); ax0 = ax0 + fax; ay0 = ay0 + fay;

        add_accel_pair(sx1, sy1, sx0, sy0, fax, fay); ax1 = fax; ay1 = fay;
        add_accel_pair(sx1, sy1, sx2, sy2, fax, fay); ax1 = ax1 + fax; ay1 = ay1 + fay;

        add_accel_pair(sx2, sy2, sx0, sy0, fax, fay); ax2 = fax; ay2 = fay;
        add_accel_pair(sx2, sy2, sx1, sy1, fax, fay); ax2 = ax2 + fax; ay2 = ay2 + fay;

        // planet acceleration: affected by suns, no back reaction
        add_accel_pair(px, py, sx0, sy0, fax, fay); apx = fax; apy = fay;
        add_accel_pair(px, py, sx1, sy1, fax, fay); apx = apx + fax; apy = apy + fay;
        add_accel_pair(px, py, sx2, sy2, fax, fay); apx = apx + fax; apy = apy + fay;

        nsvx0 = svx0 + qmul(ax0, Q_DT); nsvy0 = svy0 + qmul(ay0, Q_DT);
        nsvx1 = svx1 + qmul(ax1, Q_DT); nsvy1 = svy1 + qmul(ay1, Q_DT);
        nsvx2 = svx2 + qmul(ax2, Q_DT); nsvy2 = svy2 + qmul(ay2, Q_DT);
        npvx  = pvx  + qmul(apx, Q_DT); npvy  = pvy  + qmul(apy, Q_DT);

        nsx0 = sx0 + qmul(nsvx0, Q_DT); nsy0 = sy0 + qmul(nsvy0, Q_DT);
        nsx1 = sx1 + qmul(nsvx1, Q_DT); nsy1 = sy1 + qmul(nsvy1, Q_DT);
        nsx2 = sx2 + qmul(nsvx2, Q_DT); nsy2 = sy2 + qmul(nsvy2, Q_DT);
        npx  = px  + qmul(npvx,  Q_DT); npy  = py  + qmul(npvy,  Q_DT);

        d01_2 = dist2_q16(nsx0, nsy0, nsx1, nsy1);
        d02_2 = dist2_q16(nsx0, nsy0, nsx2, nsy2);
        d12_2 = dist2_q16(nsx1, nsy1, nsx2, nsy2);
        dp0_2 = dist2_q16(npx, npy, nsx0, nsy0);
        dp1_2 = dist2_q16(npx, npy, nsx1, nsy1);
        dp2_2 = dist2_q16(npx, npy, nsx2, nsy2);

        dominant_sun = 2'd0;
        min_dp2 = dp0_2;
        if (dp1_2 < min_dp2) begin min_dp2 = dp1_2; dominant_sun = 2'd1; end
        if (dp2_2 < min_dp2) begin min_dp2 = dp2_2; dominant_sun = 2'd2; end

        flux_proxy  = inv_r2_q16(dp0_2) + inv_r2_q16(dp1_2) + inv_r2_q16(dp2_2);
        tidal_proxy = flux_proxy; // v0.3 proxy; future lane will use inv_r3/gradient

        is_heng_step = (model_mode == 2'd1) &&
                       (d01_2 > SUN_DMIN2) && (d02_2 > SUN_DMIN2) && (d12_2 > SUN_DMIN2) &&
                       (dp0_2 > PL_DMIN2)  && (dp1_2 > PL_DMIN2)  && (dp2_2 > PL_DMIN2) &&
                       (min_dp2 >= HAB_MIN2) && (min_dp2 <= HAB_MAX2) &&
                       (tidal_proxy <= TIDAL_MAX) &&
                       (abs32(npx) < 32'd655360) && (abs32(npy) < 32'd655360);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= S_IDLE;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            fitness              <= {FITNESS_WIDTH{1'b1}};
            best_heng_steps      <= 32'd0;
            valid_candidate      <= 1'b0;
            step_counter         <= 32'd0;
            run_steps            <= 32'd0;
            failed               <= 1'b0;
            current_heng         <= 32'd0;
            capture_switch_count <= 32'd0;
            prev_dominant_sun    <= 2'd0;
            penalty_accum        <= 64'd0;
            survived_steps       <= 32'd0;
            sx0 <= 0; sy0 <= 0; svx0 <= 0; svy0 <= 0;
            sx1 <= 0; sy1 <= 0; svx1 <= 0; svy1 <= 0;
            sx2 <= 0; sy2 <= 0; svx2 <= 0; svy2 <= 0;
            px  <= 0; py  <= 0; pvx  <= 0; pvy  <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy                 <= 1'b1;
                        valid_candidate      <= 1'b1;
                        step_counter         <= 32'd0;
                        survived_steps       <= 32'd0;
                        failed               <= 1'b0;
                        current_heng         <= 32'd0;
                        best_heng_steps      <= 32'd0;
                        capture_switch_count <= 32'd0;
                        penalty_accum        <= 64'd0;
                        run_steps            <= (steps_limit == 32'd0) ? 32'd1 : steps_limit;

                        sx0  <= gene_at(0); sy0  <= gene_at(1); svx0 <= gene_at(2); svy0 <= gene_at(3);
                        sx1  <= gene_at(4); sy1  <= gene_at(5); svx1 <= gene_at(6); svy1 <= gene_at(7);
                        sx2  <= -gene_at(0) - gene_at(4);
                        sy2  <= -gene_at(1) - gene_at(5);
                        svx2 <= -gene_at(2) - gene_at(6);
                        svy2 <= -gene_at(3) - gene_at(7);
                        if (model_mode == 2'd1 && gene_count >= 6'd12) begin
                            px  <= gene_at(8);  py  <= gene_at(9);
                            pvx <= gene_at(10); pvy <= gene_at(11);
                        end else begin
                            px  <= 32'sd0; py  <= 32'sd0; pvx <= 32'sd0; pvy <= 32'sd0;
                        end
                        prev_dominant_sun <= 2'd0;
                        state <= S_RUN;
                    end
                end

                S_RUN: begin
                    busy <= 1'b1;
                    sx0 <= nsx0; sy0 <= nsy0; svx0 <= nsvx0; svy0 <= nsvy0;
                    sx1 <= nsx1; sy1 <= nsy1; svx1 <= nsvx1; svy1 <= nsvy1;
                    sx2 <= nsx2; sy2 <= nsy2; svx2 <= nsvx2; svy2 <= nsvy2;
                    px  <= npx;  py  <= npy;  pvx  <= npvx;  pvy  <= npvy;

                    step_counter   <= step_counter + 32'd1;
                    survived_steps <= survived_steps + 32'd1;

                    if (dominant_sun != prev_dominant_sun) begin
                        capture_switch_count <= capture_switch_count + 32'd1;
                        prev_dominant_sun    <= dominant_sun;
                    end

                    if (is_heng_step) begin
                        current_heng <= current_heng + 32'd1;
                        if (current_heng + 32'd1 > best_heng_steps)
                            best_heng_steps <= current_heng + 32'd1;
                    end else begin
                        current_heng <= 32'd0;
                        penalty_accum <= penalty_accum + 64'd1024;
                    end

                    if ((d01_2 < SUN_DMIN2) || (d02_2 < SUN_DMIN2) || (d12_2 < SUN_DMIN2) ||
                        (d01_2 > SUN_RMAX2) || (d02_2 > SUN_RMAX2) || (d12_2 > SUN_RMAX2) ||
                        ((model_mode == 2'd1) && ((dp0_2 < PL_DMIN2) || (dp1_2 < PL_DMIN2) ||
                         (dp2_2 < PL_DMIN2) || (abs32(npx) > 32'd655360) || (abs32(npy) > 32'd655360)))) begin
                        failed <= 1'b1;
                        penalty_accum <= penalty_accum + 64'd1000000;
                        state <= S_DONE;
                    end else if (step_counter + 32'd1 >= run_steps) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    valid_candidate <= !failed;
                    if (model_mode == 2'd1) begin
                        fitness <= penalty_accum + {22'd0, capture_switch_count, 10'd0} +
                                   ({32'd0, run_steps} - {32'd0, best_heng_steps});
                    end else begin
                        fitness <= penalty_accum + ({32'd0, run_steps} - {32'd0, survived_steps});
                        best_heng_steps <= 32'd0;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule