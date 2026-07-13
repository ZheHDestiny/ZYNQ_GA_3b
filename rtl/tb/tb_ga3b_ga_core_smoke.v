// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module tb_ga3b_ga_core_smoke;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg bounds_we = 1'b0;
    reg [5:0] bounds_index = 6'd0;
    reg signed [31:0] bounds_min = 32'sd0;
    reg signed [31:0] bounds_max = 32'sd0;
    reg signed [31:0] bounds_scale = 32'sd0;

    wire busy, done, error;
    wire [15:0] cur_gen;
    wire [5:0] best_index;
    wire [63:0] best_fitness;
    wire [31:0] best_heng_steps;
    wire [32*18-1:0] best_chromosome_flat;

    always #5 clk = ~clk;

    ga3b_ga_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .model_mode(2'd1),
        .gene_count(6'd12),
        .pop_size(6'd8),
        .max_gen(16'd3),
        .steps_limit(32'd16),
        .mutation_rate_q16(16'h0800),
        .crossover_rate_q16(16'hC000),
        .seed0(32'h12345678),
        .seed1(32'h87654321),
        .bounds_we(bounds_we),
        .bounds_index(bounds_index),
        .bounds_min(bounds_min),
        .bounds_max(bounds_max),
        .bounds_mutation_scale(bounds_scale),
        .busy(busy),
        .done(done),
        .error(error),
        .cur_gen(cur_gen),
        .best_index(best_index),
        .best_fitness(best_fitness),
        .best_heng_steps(best_heng_steps),
        .best_chromosome_flat(best_chromosome_flat)
    );

    integer i;
    integer timeout;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (i = 0; i < 12; i = i + 1) begin
            @(posedge clk);
            bounds_we = 1'b1;
            bounds_index = i;
            bounds_min = -32'sd65536;
            bounds_max =  32'sd65536;
            bounds_scale = 32'sd1024;
        end
        @(posedge clk);
        bounds_we = 1'b0;
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        timeout = 0;
        while (!done && timeout < 20000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (!done) begin
            $display("TB_FAIL timeout waiting for done");
            $finish;
        end
        if (error) begin
            $display("TB_FAIL core asserted error");
            $finish;
        end
        if (best_fitness === 64'hFFFF_FFFF_FFFF_FFFF) begin
            $display("TB_FAIL best_fitness was not updated");
            $finish;
        end
        $display("TB_PASS done cur_gen=%0d best_index=%0d best_fitness=%0d best_heng_steps=%0d", cur_gen, best_index, best_fitness, best_heng_steps);
        repeat (5) @(posedge clk);
        $finish;
    end
endmodule