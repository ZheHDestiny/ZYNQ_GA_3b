// SPDX-License-Identifier: MIT
// GA stable initial-condition search core for ZYNQ_GA_3b v0.3 bring-up.
//
// Scope of this file:
// - Population initialization from gene bounds.
// - Two-lane fitness dispatch interface.
// - Best reduction.
// - Elite copy, selection, crossover, mutation, clamp.
// - MODEL_MODE support: 0=pure3 fallback, 1=restricted4 heng-era search.
//
// The actual physical fitness lane is intentionally separated and currently
// instantiated as ga3b_fitness_lane. Replace that module with the
// modular v0.3 sun3/test-planet integrator without changing this core interface.

`timescale 1ns/1ps

module ga3b_ga_core #(
    parameter integer POP_MAX       = 32,
    parameter integer GENE_MAX      = 18,
    parameter integer GENE_WIDTH    = 32,
    parameter integer FITNESS_WIDTH = 64,
    parameter integer INDEX_WIDTH   = 6
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,
    input  wire [1:0]                   model_mode,       // 0:pure3, 1:restricted4
    input  wire [5:0]                   gene_count,
    input  wire [5:0]                   pop_size,
    input  wire [15:0]                  max_gen,
    input  wire [31:0]                  steps_limit,
    input  wire [15:0]                  mutation_rate_q16,
    input  wire [15:0]                  crossover_rate_q16,
    input  wire [31:0]                  seed0,
    input  wire [31:0]                  seed1,

    // Gene bound write port. Load this before start.
    input  wire                         bounds_we,
    input  wire [5:0]                   bounds_index,
    input  wire signed [GENE_WIDTH-1:0] bounds_min,
    input  wire signed [GENE_WIDTH-1:0] bounds_max,
    input  wire signed [GENE_WIDTH-1:0] bounds_mutation_scale,

    output reg                          busy,
    output reg                          done,
    output reg                          error,
    output reg  [15:0]                  cur_gen,
    output reg  [INDEX_WIDTH-1:0]       best_index,
    output reg  [FITNESS_WIDTH-1:0]     best_fitness,
    output reg  [31:0]                  best_heng_steps,
    output wire [GENE_WIDTH*GENE_MAX-1:0] best_chromosome_flat
);
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_INIT        = 4'd1;
    localparam [3:0] ST_EVAL_START  = 4'd2;
    localparam [3:0] ST_EVAL_WAIT   = 4'd3;
    localparam [3:0] ST_REPRO_INIT  = 4'd4;
    localparam [3:0] ST_REPRO_GENE  = 4'd5;
    localparam [3:0] ST_NEXT_GEN    = 4'd6;
    localparam [3:0] ST_DONE        = 4'd7;
    localparam [3:0] ST_ERROR       = 4'd8;

    localparam [5:0] POP_MAX_U  = POP_MAX;
    localparam [5:0] GENE_MAX_U = GENE_MAX;

    reg [3:0] state;
    reg active_bank; // 0: read A/write B, 1: read B/write A

    reg signed [GENE_WIDTH-1:0] gene_min   [0:GENE_MAX-1];
    reg signed [GENE_WIDTH-1:0] gene_max   [0:GENE_MAX-1];
    reg signed [GENE_WIDTH-1:0] gene_scale [0:GENE_MAX-1];

    reg signed [GENE_WIDTH-1:0] pop_a [0:POP_MAX*GENE_MAX-1];
    reg signed [GENE_WIDTH-1:0] pop_b [0:POP_MAX*GENE_MAX-1];
    reg [FITNESS_WIDTH-1:0] fitness_mem [0:POP_MAX-1];
    reg [31:0] heng_mem [0:POP_MAX-1];

    reg [31:0] rng0;
    reg [31:0] rng1;

    reg [5:0] init_ind;
    reg [5:0] init_gene;
    reg [5:0] eval_idx;
    reg [5:0] child_idx;
    reg [5:0] repro_gene;
    reg [5:0] parent_a_idx;
    reg [5:0] parent_b_idx;

    reg lane0_start;
    reg lane1_start;
    reg [GENE_WIDTH*GENE_MAX-1:0] lane0_genes;
    reg [GENE_WIDTH*GENE_MAX-1:0] lane1_genes;
    wire lane0_busy, lane0_done, lane0_valid;
    wire lane1_busy, lane1_done, lane1_valid;
    wire [FITNESS_WIDTH-1:0] lane0_fitness;
    wire [FITNESS_WIDTH-1:0] lane1_fitness;
    wire [31:0] lane0_heng;
    wire [31:0] lane1_heng;

    integer i;
    integer flat_idx;
    reg signed [GENE_WIDTH-1:0] selected_gene;
    reg signed [GENE_WIDTH-1:0] mutated_gene;
    reg signed [GENE_WIDTH-1:0] delta_gene;
    reg [31:0] span_u;

    function [31:0] xs32;
        input [31:0] x;
        reg [31:0] y;
        begin
            y = x ^ (x << 13);
            y = y ^ (y >> 17);
            y = y ^ (y << 5);
            xs32 = (y == 32'd0) ? 32'h1BAD_F00D : y;
        end
    endfunction

    function [5:0] clamp_pop_idx;
        input [31:0] x;
        input [5:0]  ps;
        begin
            if (ps <= 6'd1)
                clamp_pop_idx = 6'd0;
            else
                clamp_pop_idx = x % ps;
        end
    endfunction
    function [5:0] tournament3_select;
        input [31:0] r0;
        input [31:0] r1;
        input [31:0] r2;
        input [5:0]  ps;
        reg [5:0] i0;
        reg [5:0] i1;
        reg [5:0] i2;
        reg [5:0] best_i;
        begin
            i0 = clamp_pop_idx(r0, ps);
            i1 = clamp_pop_idx(r1, ps);
            i2 = clamp_pop_idx(r2, ps);
            best_i = i0;
            if (fitness_mem[i1] < fitness_mem[best_i]) best_i = i1;
            if (fitness_mem[i2] < fitness_mem[best_i]) best_i = i2;
            tournament3_select = best_i;
        end
    endfunction

    function signed [GENE_WIDTH-1:0] read_pop;
        input bank;
        input [5:0] ind;
        input [5:0] gene;
        begin
            if (!bank)
                read_pop = pop_a[ind*GENE_MAX + gene];
            else
                read_pop = pop_b[ind*GENE_MAX + gene];
        end
    endfunction

    assign best_chromosome_flat = best_flatten(active_bank, best_index);

    function [GENE_WIDTH*GENE_MAX-1:0] best_flatten;
        input bank;
        input [5:0] ind;
        integer bi;
        begin
            best_flatten = {GENE_WIDTH*GENE_MAX{1'b0}};
            for (bi = 0; bi < GENE_MAX; bi = bi + 1) begin
                if (!bank)
                    best_flatten[bi*GENE_WIDTH +: GENE_WIDTH] = pop_a[ind*GENE_MAX + bi];
                else
                    best_flatten[bi*GENE_WIDTH +: GENE_WIDTH] = pop_b[ind*GENE_MAX + bi];
            end
        end
    endfunction

    always @(*) begin
        lane0_genes = {GENE_WIDTH*GENE_MAX{1'b0}};
        lane1_genes = {GENE_WIDTH*GENE_MAX{1'b0}};
        for (i = 0; i < GENE_MAX; i = i + 1) begin
            if (!active_bank) begin
                lane0_genes[i*GENE_WIDTH +: GENE_WIDTH] = pop_a[eval_idx*GENE_MAX + i];
                if (eval_idx + 6'd1 < pop_size)
                    lane1_genes[i*GENE_WIDTH +: GENE_WIDTH] = pop_a[(eval_idx + 6'd1)*GENE_MAX + i];
                else
                    lane1_genes[i*GENE_WIDTH +: GENE_WIDTH] = {GENE_WIDTH{1'b0}};
            end else begin
                lane0_genes[i*GENE_WIDTH +: GENE_WIDTH] = pop_b[eval_idx*GENE_MAX + i];
                if (eval_idx + 6'd1 < pop_size)
                    lane1_genes[i*GENE_WIDTH +: GENE_WIDTH] = pop_b[(eval_idx + 6'd1)*GENE_MAX + i];
                else
                    lane1_genes[i*GENE_WIDTH +: GENE_WIDTH] = {GENE_WIDTH{1'b0}};
            end
        end
    end

    ga3b_fitness_lane #(
        .GENE_WIDTH(GENE_WIDTH),
        .GENE_MAX(GENE_MAX),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) u_lane0 (
        .clk(clk), .rst_n(rst_n), .start(lane0_start), .model_mode(model_mode),
        .gene_count(gene_count), .steps_limit(steps_limit), .genes_flat(lane0_genes),
        .busy(lane0_busy), .done(lane0_done), .fitness(lane0_fitness),
        .best_heng_steps(lane0_heng), .valid_candidate(lane0_valid)
    );

    ga3b_fitness_lane #(
        .GENE_WIDTH(GENE_WIDTH),
        .GENE_MAX(GENE_MAX),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) u_lane1 (
        .clk(clk), .rst_n(rst_n), .start(lane1_start), .model_mode(model_mode),
        .gene_count(gene_count), .steps_limit(steps_limit), .genes_flat(lane1_genes),
        .busy(lane1_busy), .done(lane1_done), .fitness(lane1_fitness),
        .best_heng_steps(lane1_heng), .valid_candidate(lane1_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            busy            <= 1'b0;
            done            <= 1'b0;
            error           <= 1'b0;
            cur_gen         <= 16'd0;
            best_index      <= {INDEX_WIDTH{1'b0}};
            best_fitness    <= {FITNESS_WIDTH{1'b1}};
            best_heng_steps <= 32'd0;
            active_bank     <= 1'b0;
            init_ind        <= 6'd0;
            init_gene       <= 6'd0;
            eval_idx        <= 6'd0;
            child_idx       <= 6'd0;
            repro_gene      <= 6'd0;
            parent_a_idx    <= 6'd0;
            parent_b_idx    <= 6'd0;
            rng0            <= 32'h1234_5678;
            rng1            <= 32'hCAFE_BABE;
            lane0_start     <= 1'b0;
            lane1_start     <= 1'b0;
            for (i = 0; i < GENE_MAX; i = i + 1) begin
                gene_min[i]   <= {GENE_WIDTH{1'b0}};
                gene_max[i]   <= {GENE_WIDTH{1'b0}};
                gene_scale[i] <= {{(GENE_WIDTH-16){1'b0}}, 16'h0100};
            end
        end else begin
            done        <= 1'b0;
            lane0_start <= 1'b0;
            lane1_start <= 1'b0;

            if (bounds_we && bounds_index < GENE_MAX_U) begin
                gene_min[bounds_index]   <= bounds_min;
                gene_max[bounds_index]   <= bounds_max;
                gene_scale[bounds_index] <= bounds_mutation_scale;
            end

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        if (pop_size == 6'd0 || pop_size > POP_MAX_U ||
                            gene_count == 6'd0 || gene_count > GENE_MAX_U) begin
                            error <= 1'b1;
                            state <= ST_ERROR;
                        end else begin
                            busy            <= 1'b1;
                            error           <= 1'b0;
                            cur_gen         <= 16'd0;
                            active_bank     <= 1'b0;
                            init_ind        <= 6'd0;
                            init_gene       <= 6'd0;
                            rng0            <= (seed0 == 32'd0) ? 32'h1234_5678 : seed0;
                            rng1            <= (seed1 == 32'd0) ? 32'hCAFE_BABE : seed1;
                            state           <= ST_INIT;
                        end
                    end
                end

                ST_INIT: begin
                    rng0 <= xs32(rng0);
                    rng1 <= xs32(rng1);
                    span_u = gene_max[init_gene] - gene_min[init_gene];
                    if (span_u == 32'd0)
                        pop_a[init_ind*GENE_MAX + init_gene] <= gene_min[init_gene];
                    else
                        pop_a[init_ind*GENE_MAX + init_gene] <= gene_min[init_gene] + (rng0 % span_u);

                    if (init_gene + 6'd1 >= gene_count) begin
                        init_gene <= 6'd0;
                        if (init_ind + 6'd1 >= pop_size) begin
                            eval_idx        <= 6'd0;
                            best_fitness    <= {FITNESS_WIDTH{1'b1}};
                            best_heng_steps <= 32'd0;
                            best_index      <= {INDEX_WIDTH{1'b0}};
                            state           <= ST_EVAL_START;
                        end else begin
                            init_ind <= init_ind + 6'd1;
                        end
                    end else begin
                        init_gene <= init_gene + 6'd1;
                    end
                end

                ST_EVAL_START: begin
                    lane0_start <= 1'b1;
                    lane1_start <= (eval_idx + 6'd1 < pop_size);
                    state       <= ST_EVAL_WAIT;
                end

                ST_EVAL_WAIT: begin
                    if (lane0_done && (lane1_done || !(eval_idx + 6'd1 < pop_size))) begin
                        fitness_mem[eval_idx] <= lane0_fitness;
                        heng_mem[eval_idx]    <= lane0_heng;
                        if (lane0_fitness < best_fitness) begin
                            best_fitness    <= lane0_fitness;
                            best_index      <= eval_idx;
                            best_heng_steps <= lane0_heng;
                        end
                        if (eval_idx + 6'd1 < pop_size) begin
                            fitness_mem[eval_idx + 6'd1] <= lane1_fitness;
                            heng_mem[eval_idx + 6'd1]    <= lane1_heng;
                            if (lane1_fitness < best_fitness && lane1_fitness < lane0_fitness) begin
                                best_fitness    <= lane1_fitness;
                                best_index      <= eval_idx + 6'd1;
                                best_heng_steps <= lane1_heng;
                            end
                        end

                        if (eval_idx + 6'd2 >= pop_size) begin
                            if (cur_gen + 16'd1 >= max_gen) begin
                                state <= ST_DONE;
                            end else begin
                                child_idx  <= 6'd0;
                                repro_gene <= 6'd0;
                                state      <= ST_REPRO_INIT;
                            end
                        end else begin
                            eval_idx <= eval_idx + 6'd2;
                            state    <= ST_EVAL_START;
                        end
                    end
                end

                ST_REPRO_INIT: begin
                    rng0 <= xs32(rng0);
                    rng1 <= xs32(rng1);
                    parent_a_idx <= tournament3_select(rng0, rng1, rng0 ^ rng1, pop_size);
                    parent_b_idx <= tournament3_select(xs32(rng0), xs32(rng1), xs32(rng0 ^ rng1), pop_size);
                    repro_gene   <= 6'd0;
                    state        <= ST_REPRO_GENE;
                end

                ST_REPRO_GENE: begin
                    rng0 <= xs32(rng0);
                    rng1 <= xs32(rng1);

                    if (child_idx == 6'd0) begin
                        selected_gene = read_pop(active_bank, best_index[5:0], repro_gene); // elite copy
                    end else begin
                        if (rng0[15:0] < crossover_rate_q16)
                            selected_gene = read_pop(active_bank, parent_a_idx, repro_gene);
                        else
                            selected_gene = read_pop(active_bank, parent_b_idx, repro_gene);
                    end

                    delta_gene = (rng1[0]) ? gene_scale[repro_gene] : -gene_scale[repro_gene];
                    if (child_idx != 6'd0 && rng1[31:16] < mutation_rate_q16)
                        mutated_gene = selected_gene + delta_gene;
                    else
                        mutated_gene = selected_gene;

                    if (mutated_gene < gene_min[repro_gene]) mutated_gene = gene_min[repro_gene];
                    if (mutated_gene > gene_max[repro_gene]) mutated_gene = gene_max[repro_gene];

                    if (!active_bank)
                        pop_b[child_idx*GENE_MAX + repro_gene] <= mutated_gene;
                    else
                        pop_a[child_idx*GENE_MAX + repro_gene] <= mutated_gene;

                    if (repro_gene + 6'd1 >= gene_count) begin
                        repro_gene <= 6'd0;
                        if (child_idx + 6'd1 >= pop_size) begin
                            state <= ST_NEXT_GEN;
                        end else begin
                            child_idx <= child_idx + 6'd1;
                            state     <= ST_REPRO_INIT;
                        end
                    end else begin
                        repro_gene <= repro_gene + 6'd1;
                    end
                end

                ST_NEXT_GEN: begin
                    active_bank     <= ~active_bank;
                    cur_gen         <= cur_gen + 16'd1;
                    eval_idx        <= 6'd0;
                    best_fitness    <= {FITNESS_WIDTH{1'b1}};
                    best_heng_steps <= 32'd0;
                    best_index      <= {INDEX_WIDTH{1'b0}};
                    state           <= ST_EVAL_START;
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_ERROR: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

