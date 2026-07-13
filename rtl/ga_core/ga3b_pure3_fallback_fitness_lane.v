// SPDX-License-Identifier: MIT
// Pure three-body fallback fitness lane for v0.3.
`timescale 1ns/1ps

module ga3b_pure3_fallback_fitness_lane #(
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
    output reg  [31:0]                    best_heng_steps,
    output reg                            valid_candidate
);
    localparam [1:0] S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    localparam [31:0] SUN_DMIN2 = 32'd164;
    localparam [31:0] SUN_RMAX2 = 32'd6553600;

    reg [1:0] state;
    reg [31:0] step_counter, run_steps, survived_steps;
    reg failed;
    reg [63:0] penalty_accum;

    reg signed [31:0] sx0, sy0, svx0, svy0;
    reg signed [31:0] sx1, sy1, svx1, svy1;
    reg signed [31:0] sx2, sy2, svx2, svy2;
    wire signed [31:0] nsx0, nsy0, nsvx0, nsvy0;
    wire signed [31:0] nsx1, nsy1, nsvx1, nsvy1;
    wire signed [31:0] nsx2, nsy2, nsvx2, nsvy2;
    wire [31:0] d01_2, d02_2, d12_2;

    function signed [31:0] gene_at;
        input integer idx;
        begin gene_at = genes_flat[idx*GENE_WIDTH +: GENE_WIDTH]; end
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0;
            fitness <= {FITNESS_WIDTH{1'b1}}; best_heng_steps <= 32'd0;
            valid_candidate <= 1'b0; step_counter <= 0; run_steps <= 0;
            survived_steps <= 0; failed <= 1'b0; penalty_accum <= 0;
            sx0<=0;sy0<=0;svx0<=0;svy0<=0;sx1<=0;sy1<=0;svx1<=0;svy1<=0;sx2<=0;sy2<=0;svx2<=0;svy2<=0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; step_counter <= 0; survived_steps <= 0; failed <= 1'b0; penalty_accum <= 0;
                        run_steps <= (steps_limit == 0) ? 32'd1 : steps_limit;
                        sx0 <= gene_at(0); sy0 <= gene_at(1); svx0 <= gene_at(2); svy0 <= gene_at(3);
                        sx1 <= gene_at(4); sy1 <= gene_at(5); svx1 <= gene_at(6); svy1 <= gene_at(7);
                        sx2 <= -gene_at(0) - gene_at(4); sy2 <= -gene_at(1) - gene_at(5);
                        svx2 <= -gene_at(2) - gene_at(6); svy2 <= -gene_at(3) - gene_at(7);
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    sx0<=nsx0; sy0<=nsy0; svx0<=nsvx0; svy0<=nsvy0;
                    sx1<=nsx1; sy1<=nsy1; svx1<=nsvx1; svy1<=nsvy1;
                    sx2<=nsx2; sy2<=nsy2; svx2<=nsvx2; svy2<=nsvy2;
                    step_counter <= step_counter + 1;
                    survived_steps <= survived_steps + 1;
                    if ((d01_2 < SUN_DMIN2) || (d02_2 < SUN_DMIN2) || (d12_2 < SUN_DMIN2) ||
                        (d01_2 > SUN_RMAX2) || (d02_2 > SUN_RMAX2) || (d12_2 > SUN_RMAX2)) begin
                        failed <= 1'b1; penalty_accum <= penalty_accum + 64'd1000000; state <= S_DONE;
                    end else if (step_counter + 1 >= run_steps) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    busy <= 1'b0; done <= 1'b1; valid_candidate <= !failed; best_heng_steps <= 32'd0;
                    fitness <= penalty_accum + ({32'd0, run_steps} - {32'd0, survived_steps});
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
