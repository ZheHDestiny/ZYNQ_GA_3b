// SPDX-License-Identifier: MIT
// Restricted-four-body heng-era fitness lane for v0.3.
`timescale 1ns/1ps

module ga3b_heng_era_fitness_lane #(
    parameter integer GENE_WIDTH    = 32,
    parameter integer GENE_MAX      = 18,
    parameter integer FITNESS_WIDTH = 64
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [5:0]                     gene_count,
    input  wire [31:0]                    steps_limit,
    input  wire [GENE_WIDTH*GENE_MAX-1:0] genes_flat,
    output reg                            busy,
    output reg                            done,
    output reg  [FITNESS_WIDTH-1:0]       fitness,
    output wire [31:0]                    best_heng_steps,
    output wire                           valid_candidate
);
    localparam [1:0] S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    localparam [31:0] SUN_DMIN2 = 32'd164;
    localparam [31:0] SUN_RMAX2 = 32'd6553600;
    localparam [31:0] PL_DMIN2  = 32'd164;
    localparam [31:0] HAB_MIN2  = 32'd16384;
    localparam [31:0] HAB_MAX2  = 32'd589824;
    localparam [31:0] TIDAL_MAX = 32'd262144;
    localparam [31:0] XY_RMAX   = 32'd655360;

    reg [1:0] state;
    reg [31:0] step_counter, run_steps;
    reg metric_clear, metric_step_en;

    reg signed [31:0] sx0, sy0, svx0, svy0;
    reg signed [31:0] sx1, sy1, svx1, svy1;
    reg signed [31:0] sx2, sy2, svx2, svy2;
    reg signed [31:0] px, py, pvx, pvy;

    wire signed [31:0] nsx0, nsy0, nsvx0, nsvy0;
    wire signed [31:0] nsx1, nsy1, nsvx1, nsvy1;
    wire signed [31:0] nsx2, nsy2, nsvx2, nsvy2;
    wire signed [31:0] npx, npy, npvx, npvy;
    wire [31:0] d01_2, d02_2, d12_2;
    wire [31:0] dp0_2, dp1_2, dp2_2, min_dp2, flux_proxy, tidal_proxy;
    wire [1:0] dominant_sun;
    wire [31:0] current_heng_steps, capture_switch_count, survived_steps;
    wire [63:0] penalty_accum;
    wire metric_failed;
    wire is_heng_step, fail_step;

    function signed [31:0] gene_at;
        input integer idx;
        begin gene_at = genes_flat[idx*GENE_WIDTH +: GENE_WIDTH]; end
    endfunction

    function [31:0] abs32;
        input signed [31:0] a;
        begin abs32 = a[31] ? (~a + 32'd1) : a; end
    endfunction

    ga3b_sun3_integrator u_sun3 (
        .sx0(sx0), .sy0(sy0), .svx0(svx0), .svy0(svy0),
        .sx1(sx1), .sy1(sy1), .svx1(svx1), .svy1(svy1),
        .sx2(sx2), .sy2(sy2), .svx2(svx2), .svy2(svy2),
        .nsx0(nsx0), .nsy0(nsy0), .nsvx0(nsvx0), .nsvy0(nsvy0),
        .nsx1(nsx1), .nsy1(nsy1), .nsvx1(nsvx1), .nsvy1(nsvy1),
        .nsx2(nsx2), .nsy2(nsy2), .nsvx2(nsvx2), .nsvy2(nsvy2),
        .d01_2(d01_2), .d02_2(d02_2), .d12_2(d12_2)
    );

    ga3b_test_planet_integrator u_planet (
        .px(px), .py(py), .pvx(pvx), .pvy(pvy),
        .sx0(nsx0), .sy0(nsy0), .sx1(nsx1), .sy1(nsy1), .sx2(nsx2), .sy2(nsy2),
        .npx(npx), .npy(npy), .npvx(npvx), .npvy(npvy),
        .dp0_2(dp0_2), .dp1_2(dp1_2), .dp2_2(dp2_2), .min_dp2(min_dp2),
        .dominant_sun(dominant_sun), .flux_proxy(flux_proxy), .tidal_proxy(tidal_proxy)
    );

    assign is_heng_step = (d01_2 > SUN_DMIN2) && (d02_2 > SUN_DMIN2) && (d12_2 > SUN_DMIN2) &&
                          (dp0_2 > PL_DMIN2) && (dp1_2 > PL_DMIN2) && (dp2_2 > PL_DMIN2) &&
                          (min_dp2 >= HAB_MIN2) && (min_dp2 <= HAB_MAX2) &&
                          (tidal_proxy <= TIDAL_MAX) && (abs32(npx) < XY_RMAX) && (abs32(npy) < XY_RMAX);
    assign fail_step = (d01_2 < SUN_DMIN2) || (d02_2 < SUN_DMIN2) || (d12_2 < SUN_DMIN2) ||
                       (d01_2 > SUN_RMAX2) || (d02_2 > SUN_RMAX2) || (d12_2 > SUN_RMAX2) ||
                       (dp0_2 < PL_DMIN2) || (dp1_2 < PL_DMIN2) || (dp2_2 < PL_DMIN2) ||
                       (abs32(npx) > XY_RMAX) || (abs32(npy) > XY_RMAX);

    ga3b_heng_era_metric_accumulator u_metric (
        .clk(clk), .rst_n(rst_n), .clear(metric_clear), .step_en(metric_step_en),
        .is_heng_step(is_heng_step), .fail_step(fail_step), .dominant_sun(dominant_sun),
        .current_heng_steps(current_heng_steps), .best_heng_steps(best_heng_steps),
        .capture_switch_count(capture_switch_count), .penalty_accum(penalty_accum),
        .survived_steps(survived_steps), .failed(metric_failed)
    );

    assign valid_candidate = !metric_failed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0; fitness <= {FITNESS_WIDTH{1'b1}};
            step_counter <= 0; run_steps <= 0; metric_clear <= 1'b0; metric_step_en <= 1'b0;
            sx0<=0;sy0<=0;svx0<=0;svy0<=0;sx1<=0;sy1<=0;svx1<=0;svy1<=0;sx2<=0;sy2<=0;svx2<=0;svy2<=0;px<=0;py<=0;pvx<=0;pvy<=0;
        end else begin
            done <= 1'b0; metric_clear <= 1'b0; metric_step_en <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; step_counter <= 0; run_steps <= (steps_limit == 0) ? 32'd1 : steps_limit;
                        metric_clear <= 1'b1;
                        sx0 <= gene_at(0); sy0 <= gene_at(1); svx0 <= gene_at(2); svy0 <= gene_at(3);
                        sx1 <= gene_at(4); sy1 <= gene_at(5); svx1 <= gene_at(6); svy1 <= gene_at(7);
                        sx2 <= -gene_at(0) - gene_at(4); sy2 <= -gene_at(1) - gene_at(5);
                        svx2 <= -gene_at(2) - gene_at(6); svy2 <= -gene_at(3) - gene_at(7);
                        px <= (gene_count >= 12) ? gene_at(8) : 32'sd0;
                        py <= (gene_count >= 12) ? gene_at(9) : 32'sd0;
                        pvx <= (gene_count >= 12) ? gene_at(10) : 32'sd0;
                        pvy <= (gene_count >= 12) ? gene_at(11) : 32'sd0;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    sx0<=nsx0; sy0<=nsy0; svx0<=nsvx0; svy0<=nsvy0;
                    sx1<=nsx1; sy1<=nsy1; svx1<=nsvx1; svy1<=nsvy1;
                    sx2<=nsx2; sy2<=nsy2; svx2<=nsvx2; svy2<=nsvy2;
                    px<=npx; py<=npy; pvx<=npvx; pvy<=npvy;
                    metric_step_en <= 1'b1;
                    step_counter <= step_counter + 1;
                    if (fail_step || (step_counter + 1 >= run_steps)) state <= S_DONE;
                end
                S_DONE: begin
                    busy <= 1'b0; done <= 1'b1;
                    fitness <= penalty_accum + {22'd0, capture_switch_count, 10'd0} +
                               ({32'd0, run_steps} - {32'd0, best_heng_steps});
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
