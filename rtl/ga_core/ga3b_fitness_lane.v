// SPDX-License-Identifier: MIT
// Unified fitness lane: restricted4 heng-era or pure3 fallback.
`timescale 1ns/1ps

module ga3b_fitness_lane #(
    parameter integer GENE_WIDTH    = 32,
    parameter integer GENE_MAX      = 18,
    parameter integer FITNESS_WIDTH = 64
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start,
    input  wire [1:0]                     model_mode,
    input  wire [5:0]                     gene_count,
    input  wire [31:0]                    steps_limit,
    input  wire [GENE_WIDTH*GENE_MAX-1:0] genes_flat,
    output wire                           busy,
    output wire                           done,
    output wire [FITNESS_WIDTH-1:0]       fitness,
    output wire [31:0]                    best_heng_steps,
    output wire                           valid_candidate
);
    wire r4_start = start && (model_mode == 2'd1);
    wire p3_start = start && (model_mode != 2'd1);
    wire r4_busy, r4_done, r4_valid;
    wire p3_busy, p3_done, p3_valid;
    wire [FITNESS_WIDTH-1:0] r4_fitness, p3_fitness;
    wire [31:0] r4_heng, p3_heng;

    ga3b_heng_era_fitness_lane #(.GENE_WIDTH(GENE_WIDTH), .GENE_MAX(GENE_MAX), .FITNESS_WIDTH(FITNESS_WIDTH)) u_r4 (
        .clk(clk), .rst_n(rst_n), .start(r4_start), .gene_count(gene_count), .steps_limit(steps_limit),
        .genes_flat(genes_flat), .busy(r4_busy), .done(r4_done), .fitness(r4_fitness),
        .best_heng_steps(r4_heng), .valid_candidate(r4_valid)
    );

    ga3b_pure3_fallback_fitness_lane #(.GENE_WIDTH(GENE_WIDTH), .GENE_MAX(GENE_MAX), .FITNESS_WIDTH(FITNESS_WIDTH)) u_p3 (
        .clk(clk), .rst_n(rst_n), .start(p3_start), .gene_count(gene_count), .steps_limit(steps_limit),
        .genes_flat(genes_flat), .busy(p3_busy), .done(p3_done), .fitness(p3_fitness),
        .best_heng_steps(p3_heng), .valid_candidate(p3_valid)
    );

    assign busy = (model_mode == 2'd1) ? r4_busy : p3_busy;
    assign done = (model_mode == 2'd1) ? r4_done : p3_done;
    assign fitness = (model_mode == 2'd1) ? r4_fitness : p3_fitness;
    assign best_heng_steps = (model_mode == 2'd1) ? r4_heng : p3_heng;
    assign valid_candidate = (model_mode == 2'd1) ? r4_valid : p3_valid;
endmodule
