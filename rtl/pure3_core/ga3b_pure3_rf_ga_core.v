// SPDX-License-Identifier: MIT
// Pure3-only resource-fit GA core: POP=32, GENE=8, one lane, sync population RAMs.
`timescale 1ns/1ps

module ga3b_pure3_rf_pop_ram #(parameter integer ADDR_WIDTH=8, parameter integer DATA_WIDTH=32)(
    input wire clk,
    input wire we_a,
    input wire [ADDR_WIDTH-1:0] addr_a,
    input wire signed [DATA_WIDTH-1:0] din_a,
    output reg signed [DATA_WIDTH-1:0] dout_a,
    input wire we_b,
    input wire [ADDR_WIDTH-1:0] addr_b,
    input wire signed [DATA_WIDTH-1:0] din_b,
    output reg signed [DATA_WIDTH-1:0] dout_b
);
    (* ram_style="block" *) reg signed [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
        if (we_b) mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
endmodule

module ga3b_pure3_rf_ga_core #(
    parameter integer POP_SIZE=32,
    parameter integer GENE_COUNT=8,
    parameter integer GENE_WIDTH=32,
    parameter integer FITNESS_WIDTH=64
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [15:0] max_gen,
    input wire [31:0] steps_limit,
    input wire [15:0] mutation_rate_q16,
    input wire [15:0] crossover_rate_q16,
    input wire [31:0] seed0,
    input wire [31:0] seed1,
    input wire bounds_we,
    input wire [5:0] bounds_index,
    input wire signed [31:0] bounds_min,
    input wire signed [31:0] bounds_max,
    input wire signed [31:0] bounds_mutation_scale,
    output reg busy,
    output reg done,
    output reg error,
    output reg [15:0] cur_gen,
    output reg [5:0] best_index,
    output reg [FITNESS_WIDTH-1:0] best_fitness,
    output reg [31:0] best_heng_steps,
    output reg [GENE_COUNT*GENE_WIDTH-1:0] best_chromosome_flat
);
    localparam [4:0] POP_LAST=5'd31;
    localparam [4:0] S_IDLE=5'd0, S_SEED=5'd1, S_INIT=5'd2, S_LOAD_REQ=5'd3, S_LOAD_CAP=5'd4;
    localparam [4:0] S_LANE_START=5'd5, S_LANE_WAIT=5'd6, S_CHECK_GEN=5'd7, S_REPRO_SEL=5'd8;
    localparam [4:0] S_REPRO_READ_A=5'd9, S_REPRO_CMP_A1=5'd10, S_REPRO_CMP_A2=5'd11;
    localparam [4:0] S_REPRO_READ_B=5'd12, S_REPRO_CMP_B1=5'd13, S_REPRO_CMP_B2=5'd14;
    localparam [4:0] S_REPRO_REQ=5'd15, S_REPRO_WR=5'd16, S_NEXT_GEN=5'd17, S_DONE=5'd18;

    reg [4:0] state;
    reg active_bank;
    reg [4:0] indiv_idx, child_idx;
    reg [2:0] gene_idx;
    reg signed [31:0] child_gene;
    reg [4:0] pa, pb;
    reg [4:0] sel0, sel1, sel2, sel_best;
    reg [FITNESS_WIDTH-1:0] fit0, fit1, fit2, fit_best;
    reg lane_start, rng_seed_we, rng_next;

    reg a_we_a, a_we_b, b_we_a, b_we_b;
    reg [7:0] a_addr_a, a_addr_b, b_addr_a, b_addr_b;
    reg signed [31:0] a_din_a, a_din_b, b_din_a, b_din_b;
    wire signed [31:0] a_dout_a, a_dout_b, b_dout_a, b_dout_b;

    ga3b_pure3_rf_pop_ram u_pop_a(.clk(clk),.we_a(a_we_a),.addr_a(a_addr_a),.din_a(a_din_a),.dout_a(a_dout_a),.we_b(a_we_b),.addr_b(a_addr_b),.din_b(a_din_b),.dout_b(a_dout_b));
    ga3b_pure3_rf_pop_ram u_pop_b(.clk(clk),.we_a(b_we_a),.addr_a(b_addr_a),.din_a(b_din_a),.dout_a(b_dout_a),.we_b(b_we_b),.addr_b(b_addr_b),.din_b(b_din_b),.dout_b(b_dout_b));

    reg [FITNESS_WIDTH-1:0] fitness_mem [0:POP_SIZE-1];
    reg signed [31:0] bmin [0:GENE_COUNT-1];
    reg signed [31:0] bmax [0:GENE_COUNT-1];
    reg signed [31:0] bscale [0:GENE_COUNT-1];

    reg [GENE_COUNT*GENE_WIDTH-1:0] lane_chromosome_flat;
    wire lane_done;
    wire [FITNESS_WIDTH-1:0] lane_fitness;
    wire [31:0] lane_steps;
    wire [31:0] rng_random;

    ga3b_rng_xorshift32 u_rng(.clk(clk),.rst_n(rst_n),.seed_we(rng_seed_we),.seed(seed0 ^ {seed1[15:0], seed1[31:16]}),.next(rng_next),.random(rng_random));
    ga3b_pure3_rf_fitness_lane #(.GENE_COUNT(GENE_COUNT),.GENE_WIDTH(GENE_WIDTH),.FITNESS_WIDTH(FITNESS_WIDTH)) u_lane(
        .clk(clk),.rst_n(rst_n),.start(lane_start),.steps_limit(steps_limit),.chromosome_flat(lane_chromosome_flat),
        .busy(),.done(lane_done),.fitness(lane_fitness),.survived_steps(lane_steps),.valid_stable(),.error());

    function signed [31:0] clamp_gene;
        input signed [31:0] v, lo, hi;
        begin
            if (v < lo) clamp_gene = lo;
            else if (v > hi) clamp_gene = hi;
            else clamp_gene = v;
        end
    endfunction

    function [4:0] tournament3;
        input [4:0] x, y, z;
        reg [4:0] t;
        begin
            t = (fitness_mem[x] >= fitness_mem[y]) ? x : y;
            tournament3 = (fitness_mem[t] >= fitness_mem[z]) ? t : z;
        end
    endfunction

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; active_bank <= 1'b0;
            indiv_idx <= 0; child_idx <= 0; gene_idx <= 0;
            busy <= 1'b0; done <= 1'b0; error <= 1'b0; cur_gen <= 0;
            best_index <= 0; best_fitness <= 0; best_heng_steps <= 0; best_chromosome_flat <= 0;
            lane_chromosome_flat <= 0; lane_start <= 1'b0; rng_seed_we <= 1'b0; rng_next <= 1'b0;
            a_we_a <= 0; a_we_b <= 0; b_we_a <= 0; b_we_b <= 0;
            a_addr_a <= 0; a_addr_b <= 0; b_addr_a <= 0; b_addr_b <= 0;
            a_din_a <= 0; a_din_b <= 0; b_din_a <= 0; b_din_b <= 0;
            child_gene <= 0; pa <= 0; pb <= 0; sel0 <= 0; sel1 <= 0; sel2 <= 0; sel_best <= 0; fit0 <= 0; fit1 <= 0; fit2 <= 0; fit_best <= 0;
            for (k=0; k<GENE_COUNT; k=k+1) begin
                bmin[k] <= -32'sd65536; bmax[k] <= 32'sd65536; bscale[k] <= 32'sd4096;
            end
        end else begin
            done <= 1'b0; lane_start <= 1'b0; rng_seed_we <= 1'b0; rng_next <= 1'b0;
            a_we_a <= 1'b0; a_we_b <= 1'b0; b_we_a <= 1'b0; b_we_b <= 1'b0;

            if (bounds_we && bounds_index < GENE_COUNT) begin
                bmin[bounds_index[2:0]] <= bounds_min;
                bmax[bounds_index[2:0]] <= bounds_max;
                bscale[bounds_index[2:0]] <= bounds_mutation_scale;
            end

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1; error <= (max_gen==16'd0) || (steps_limit==32'd0);
                        cur_gen <= 0; best_index <= 0; best_fitness <= 0; best_heng_steps <= 0; best_chromosome_flat <= 0;
                        active_bank <= 1'b0; indiv_idx <= 0; child_idx <= 0; gene_idx <= 0;
                        rng_seed_we <= 1'b1; state <= S_SEED;
                    end
                end
                S_SEED: begin rng_next <= 1'b1; state <= error ? S_DONE : S_INIT; end
                S_INIT: begin
                    a_addr_a <= {indiv_idx, gene_idx};
                    if (indiv_idx == 5'd0)
                        a_din_a <= clamp_gene((bmin[gene_idx]>>>1)+(bmax[gene_idx]>>>1), bmin[gene_idx], bmax[gene_idx]);
                    else
                        a_din_a <= clamp_gene(bmin[gene_idx]+{{16{rng_random[15]}},rng_random[15:0]}, bmin[gene_idx], bmax[gene_idx]);
                    a_we_a <= 1'b1; rng_next <= 1'b1;
                    if (gene_idx == 3'd7) begin
                        gene_idx <= 0;
                        if (indiv_idx == POP_LAST) begin indiv_idx <= 0; state <= S_LOAD_REQ; end
                        else indiv_idx <= indiv_idx + 1'b1;
                    end else gene_idx <= gene_idx + 1'b1;
                end
                S_LOAD_REQ: begin
                    if (!active_bank) a_addr_a <= {indiv_idx, gene_idx}; else b_addr_a <= {indiv_idx, gene_idx};
                    state <= S_LOAD_CAP;
                end
                S_LOAD_CAP: begin
                    lane_chromosome_flat[gene_idx*GENE_WIDTH +: GENE_WIDTH] <= active_bank ? b_dout_a : a_dout_a;
                    if (gene_idx == 3'd7) begin gene_idx <= 0; state <= S_LANE_START; end
                    else begin gene_idx <= gene_idx + 1'b1; state <= S_LOAD_REQ; end
                end
                S_LANE_START: begin lane_start <= 1'b1; state <= S_LANE_WAIT; end
                S_LANE_WAIT: begin
                    if (lane_done) begin
                        fitness_mem[indiv_idx] <= lane_fitness;
                        if ((indiv_idx==5'd0) || (lane_fitness > best_fitness)) begin
                            best_index <= indiv_idx; best_fitness <= lane_fitness; best_heng_steps <= lane_steps;
                            best_chromosome_flat <= lane_chromosome_flat;
                        end
                        if (indiv_idx == POP_LAST) begin indiv_idx <= 0; state <= S_CHECK_GEN; end
                        else begin indiv_idx <= indiv_idx + 1'b1; state <= S_LOAD_REQ; end
                    end
                end
                S_CHECK_GEN: begin
                    if (cur_gen >= max_gen) state <= S_DONE;
                    else begin child_idx <= 0; gene_idx <= 0; state <= S_REPRO_SEL; end
                end
                S_REPRO_SEL: begin
                    if (child_idx == 5'd0) begin
                        state <= S_REPRO_REQ;
                    end else begin
                        sel0 <= rng_random[4:0];
                        sel1 <= rng_random[9:5];
                        sel2 <= rng_random[14:10];
                        state <= S_REPRO_READ_A;
                    end
                end
                S_REPRO_READ_A: begin
                    fit0 <= fitness_mem[sel0];
                    fit1 <= fitness_mem[sel1];
                    fit2 <= fitness_mem[sel2];
                    state <= S_REPRO_CMP_A1;
                end
                S_REPRO_CMP_A1: begin
                    if (fit0 >= fit1) begin fit_best <= fit0; sel_best <= sel0; end
                    else begin fit_best <= fit1; sel_best <= sel1; end
                    state <= S_REPRO_CMP_A2;
                end
                S_REPRO_CMP_A2: begin
                    pa <= (fit_best >= fit2) ? sel_best : sel2;
                    sel0 <= rng_random[19:15];
                    sel1 <= rng_random[24:20];
                    sel2 <= rng_random[29:25];
                    state <= S_REPRO_READ_B;
                end
                S_REPRO_READ_B: begin
                    fit0 <= fitness_mem[sel0];
                    fit1 <= fitness_mem[sel1];
                    fit2 <= fitness_mem[sel2];
                    state <= S_REPRO_CMP_B1;
                end
                S_REPRO_CMP_B1: begin
                    if (fit0 >= fit1) begin fit_best <= fit0; sel_best <= sel0; end
                    else begin fit_best <= fit1; sel_best <= sel1; end
                    state <= S_REPRO_CMP_B2;
                end
                S_REPRO_CMP_B2: begin
                    pb <= (fit_best >= fit2) ? sel_best : sel2;
                    state <= S_REPRO_REQ;
                end
                S_REPRO_REQ: begin
                    if (child_idx != 5'd0) begin
                        if (!active_bank) begin a_addr_a <= {pa,gene_idx}; a_addr_b <= {pb,gene_idx}; end
                        else begin b_addr_a <= {pa,gene_idx}; b_addr_b <= {pb,gene_idx}; end
                    end
                    state <= S_REPRO_WR;
                end
                S_REPRO_WR: begin
                    if (child_idx == 5'd0) child_gene = best_chromosome_flat[gene_idx*GENE_WIDTH +: GENE_WIDTH];
                    else begin
                        child_gene = (rng_random[31:16] < crossover_rate_q16) ? (active_bank ? b_dout_a : a_dout_a) : (active_bank ? b_dout_b : a_dout_b);
                        if (rng_random[15:0] < mutation_rate_q16) begin
                            if (rng_random[30]) child_gene = child_gene + bscale[gene_idx]; else child_gene = child_gene - bscale[gene_idx];
                        end
                        child_gene = clamp_gene(child_gene, bmin[gene_idx], bmax[gene_idx]);
                    end
                    if (!active_bank) begin b_addr_a <= {child_idx,gene_idx}; b_din_a <= child_gene; b_we_a <= 1'b1; end
                    else begin a_addr_a <= {child_idx,gene_idx}; a_din_a <= child_gene; a_we_a <= 1'b1; end
                    rng_next <= 1'b1;
                    if (gene_idx == 3'd7) begin
                        gene_idx <= 0;
                        if (child_idx == POP_LAST) begin child_idx <= 0; state <= S_NEXT_GEN; end
                        else begin child_idx <= child_idx + 1'b1; state <= S_REPRO_SEL; end
                    end else begin gene_idx <= gene_idx + 1'b1; state <= S_REPRO_SEL; end
                end
                S_NEXT_GEN: begin
                    active_bank <= ~active_bank; indiv_idx <= 0; gene_idx <= 0; cur_gen <= cur_gen + 1'b1; state <= S_LOAD_REQ;
                end
                S_DONE: begin busy <= 1'b0; done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule