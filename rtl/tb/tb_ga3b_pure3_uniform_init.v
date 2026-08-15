`timescale 1ns/1ps

module tb_ga3b_pure3_uniform_init;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg bounds_we = 1'b0;
    reg [5:0] bounds_index = 0;
    reg signed [31:0] bounds_min = 0;
    reg signed [31:0] bounds_max = 0;
    reg signed [31:0] bounds_mutation_scale = 0;
    wire busy, done, error;
    wire [15:0] cur_gen;
    wire [5:0] best_index;
    wire [63:0] best_fitness;
    wire [31:0] best_heng_steps;
    wire [255:0] best_chromosome_flat;

    integer g, i;
    integer below_quartile, above_quartile;
    integer signed sample;

    always #5 clk = ~clk;

    ga3b_pure3_rf_ga_core #(.HIFI_ENABLE(0)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .max_gen(16'd1), .steps_limit(32'd1),
        .mutation_rate_q16(16'h1000), .crossover_rate_q16(16'hc000),
        .seed0(32'h12345678), .seed1(32'h87654321),
        .bounds_we(bounds_we), .bounds_index(bounds_index),
        .bounds_min(bounds_min), .bounds_max(bounds_max),
        .bounds_mutation_scale(bounds_mutation_scale),
        .busy(busy), .done(done), .error(error), .cur_gen(cur_gen),
        .best_index(best_index), .best_fitness(best_fitness),
        .best_heng_steps(best_heng_steps),
        .best_chromosome_flat(best_chromosome_flat)
    );

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        for (g = 0; g < 8; g = g + 1) begin
            @(posedge clk);
            bounds_we <= 1'b1;
            bounds_index <= g;
            bounds_min <= -32'sd131072; // -2.0 in Q16
            bounds_max <=  32'sd131072; // +2.0 in Q16
            bounds_mutation_scale <= 32'sd4096;
        end
        @(posedge clk);
        bounds_we <= 1'b0;
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // State 3 is the first population read after all initialization writes.
        wait (dut.state == 5'd3);
        @(posedge clk);
        #1;

        for (g = 0; g < 8; g = g + 1) begin
            if ($signed(dut.u_pop_a.mem[g]) !== 0) begin
                $display("TB_FAIL midpoint gene=%0d value=%0d", g, $signed(dut.u_pop_a.mem[g]));
                $finish;
            end
        end

        below_quartile = 0;
        above_quartile = 0;
        for (i = 1; i < 32; i = i + 1) begin
            sample = $signed(dut.u_pop_a.mem[{i[4:0],3'd0}]);
            if ((sample < -131072) || (sample >= 131072)) begin
                $display("TB_FAIL out_of_bounds indiv=%0d value=%0d", i, sample);
                $finish;
            end
            if (sample < -65536) below_quartile = below_quartile + 1;
            if (sample >  65536) above_quartile = above_quartile + 1;
        end
        if ((below_quartile == 0) || (above_quartile == 0)) begin
            $display("TB_FAIL distribution low=%0d high=%0d", below_quartile, above_quartile);
            $finish;
        end
        $display("TB_PASS uniform_init low_quartile=%0d high_quartile=%0d", below_quartile, above_quartile);
        $finish;
    end

    initial begin
        #200000;
        $display("TB_FAIL timeout state=%0d indiv=%0d gene=%0d", dut.state, dut.indiv_idx, dut.gene_idx);
        $finish;
    end
endmodule
