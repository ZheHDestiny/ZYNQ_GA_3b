// SPDX-License-Identifier: MIT
// Heng-era metric accumulator for restricted4 fitness lane.
`timescale 1ns/1ps

module ga3b_heng_era_metric_accumulator #(
    parameter integer FITNESS_WIDTH = 64
)(
    input  wire clk,
    input  wire rst_n,
    input  wire clear,
    input  wire step_en,
    input  wire is_heng_step,
    input  wire fail_step,
    input  wire [1:0] dominant_sun,
    output reg  [31:0] current_heng_steps,
    output reg  [31:0] best_heng_steps,
    output reg  [31:0] capture_switch_count,
    output reg  [63:0] penalty_accum,
    output reg  [31:0] survived_steps,
    output reg         failed
);
    reg [1:0] prev_dominant_sun;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_heng_steps  <= 32'd0;
            best_heng_steps     <= 32'd0;
            capture_switch_count<= 32'd0;
            penalty_accum       <= 64'd0;
            survived_steps      <= 32'd0;
            failed              <= 1'b0;
            prev_dominant_sun   <= 2'd0;
        end else if (clear) begin
            current_heng_steps  <= 32'd0;
            best_heng_steps     <= 32'd0;
            capture_switch_count<= 32'd0;
            penalty_accum       <= 64'd0;
            survived_steps      <= 32'd0;
            failed              <= 1'b0;
            prev_dominant_sun   <= 2'd0;
        end else if (step_en) begin
            survived_steps <= survived_steps + 32'd1;
            if (dominant_sun != prev_dominant_sun) begin
                capture_switch_count <= capture_switch_count + 32'd1;
                prev_dominant_sun    <= dominant_sun;
            end
            if (is_heng_step) begin
                current_heng_steps <= current_heng_steps + 32'd1;
                if (current_heng_steps + 32'd1 > best_heng_steps)
                    best_heng_steps <= current_heng_steps + 32'd1;
            end else begin
                current_heng_steps <= 32'd0;
                penalty_accum <= penalty_accum + 64'd1024;
            end
            if (fail_step) begin
                failed <= 1'b1;
                penalty_accum <= penalty_accum + 64'd1000000;
            end
        end
    end
endmodule
