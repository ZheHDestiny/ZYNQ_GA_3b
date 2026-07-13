// SPDX-License-Identifier: MIT
// Resource-fit pure three-body fitness lane for GA3B.
// Additional fallback RTL: deeply multi-cycle to close 100 MHz on Zynq-7020.
`timescale 1ns/1ps

module ga3b_pure3_rf_fitness_lane #(
    parameter integer GENE_COUNT    = 8,
    parameter integer GENE_WIDTH    = 32,
    parameter integer FITNESS_WIDTH = 64
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [31:0]                  steps_limit,
    input  wire [GENE_COUNT*GENE_WIDTH-1:0] chromosome_flat,
    output reg                          busy,
    output reg                          done,
    output reg  [FITNESS_WIDTH-1:0]     fitness,
    output reg  [31:0]                  survived_steps,
    output reg                          valid_stable,
    output reg                          error
);
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_PAIR_PRE    = 4'd1;
    localparam [3:0] ST_PAIR_FORCE  = 4'd2;
    localparam [3:0] ST_PAIR_ACC    = 4'd3;
    localparam [3:0] ST_UPDATE      = 4'd4;
    localparam [3:0] ST_METRIC_PRE  = 4'd5;
    localparam [3:0] ST_METRIC_CHK  = 4'd6;
    localparam [3:0] ST_METRIC_DONE = 4'd7;
    localparam [3:0] ST_DONE        = 4'd8;

    localparam signed [31:0] ESCAPE_ABS = 32'sd524288; // 8.0 in Q16

    reg [3:0] state;
    reg [31:0] step_idx;
    reg failed;
    reg step_failed;
    reg [1:0] pair_sel;
    reg [2:0] metric_sel;

    reg signed [31:0] x0, y0, vx0, vy0;
    reg signed [31:0] x1, y1, vx1, vy1;
    reg signed [31:0] x2, y2, vx2, vy2;
    reg signed [31:0] ax0, ay0, ax1, ay1, ax2, ay2;
    reg signed [31:0] pair_dx, pair_dy;
    reg signed [31:0] pair_fx, pair_fy;

    wire signed [31:0] g_x0  = chromosome_flat[0*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_y0  = chromosome_flat[1*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vx0 = chromosome_flat[2*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vy0 = chromosome_flat[3*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_x1  = chromosome_flat[4*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_y1  = chromosome_flat[5*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vx1 = chromosome_flat[6*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vy1 = chromosome_flat[7*GENE_WIDTH +: GENE_WIDTH];

    function signed [31:0] abs_s32;
        input signed [31:0] v;
        begin
            abs_s32 = v[31] ? -v : v;
        end
    endfunction

    function [4:0] force_shift;
        input signed [31:0] dx;
        input signed [31:0] dy;
        reg [32:0] l1;
        begin
            l1 = {1'b0, abs_s32(dx)} + {1'b0, abs_s32(dy)};
            if      (l1 < 33'd8192)    force_shift = 5'd4;
            else if (l1 < 33'd16384)   force_shift = 5'd5;
            else if (l1 < 33'd32768)   force_shift = 5'd6;
            else if (l1 < 33'd65536)   force_shift = 5'd7;
            else if (l1 < 33'd131072)  force_shift = 5'd8;
            else if (l1 < 33'd262144)  force_shift = 5'd9;
            else if (l1 < 33'd524288)  force_shift = 5'd10;
            else                       force_shift = 5'd11;
        end
    endfunction

    function signed [31:0] fcomp;
        input signed [31:0] dcomp;
        input signed [31:0] dx;
        input signed [31:0] dy;
        begin
            fcomp = dcomp >>> force_shift(dx, dy);
        end
    endfunction

    function pair_collision;
        input signed [31:0] dx;
        input signed [31:0] dy;
        reg [32:0] l1;
        begin
            l1 = {1'b0, abs_s32(dx)} + {1'b0, abs_s32(dy)};
            pair_collision = (l1 < 33'd8192);
        end
    endfunction

    function body_escape;
        input signed [31:0] x;
        input signed [31:0] y;
        begin
            body_escape = (abs_s32(x) > ESCAPE_ABS) || (abs_s32(y) > ESCAPE_ABS);
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            busy <= 1'b0; done <= 1'b0; fitness <= 0; survived_steps <= 0;
            valid_stable <= 1'b0; error <= 1'b0; step_idx <= 0; failed <= 1'b0; step_failed <= 1'b0;
            pair_sel <= 0; metric_sel <= 0;
            x0 <= 0; y0 <= 0; vx0 <= 0; vy0 <= 0;
            x1 <= 0; y1 <= 0; vx1 <= 0; vy1 <= 0;
            x2 <= 0; y2 <= 0; vx2 <= 0; vy2 <= 0;
            ax0 <= 0; ay0 <= 0; ax1 <= 0; ay1 <= 0; ax2 <= 0; ay2 <= 0;
            pair_dx <= 0; pair_dy <= 0; pair_fx <= 0; pair_fy <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        fitness <= 0;
                        survived_steps <= 0;
                        valid_stable <= 1'b0;
                        error <= (steps_limit == 32'd0);
                        step_idx <= 0;
                        failed <= (steps_limit == 32'd0);
                        step_failed <= 1'b0;
                        x0 <= g_x0;  y0 <= g_y0;  vx0 <= g_vx0;  vy0 <= g_vy0;
                        x1 <= g_x1;  y1 <= g_y1;  vx1 <= g_vx1;  vy1 <= g_vy1;
                        x2 <= -g_x0 - g_x1;   y2 <= -g_y0 - g_y1;
                        vx2 <= -g_vx0 - g_vx1; vy2 <= -g_vy0 - g_vy1;
                        ax0 <= 0; ay0 <= 0; ax1 <= 0; ay1 <= 0; ax2 <= 0; ay2 <= 0;
                        pair_sel <= 0;
                        state <= (steps_limit == 32'd0) ? ST_DONE : ST_PAIR_PRE;
                    end
                end

                ST_PAIR_PRE: begin
                    if (pair_sel == 2'd0) begin
                        ax0 <= 0; ay0 <= 0; ax1 <= 0; ay1 <= 0; ax2 <= 0; ay2 <= 0;
                        pair_dx <= x1 - x0;
                        pair_dy <= y1 - y0;
                    end else if (pair_sel == 2'd1) begin
                        pair_dx <= x2 - x0;
                        pair_dy <= y2 - y0;
                    end else begin
                        pair_dx <= x2 - x1;
                        pair_dy <= y2 - y1;
                    end
                    state <= ST_PAIR_FORCE;
                end

                ST_PAIR_FORCE: begin
                    pair_fx <= fcomp(pair_dx, pair_dx, pair_dy);
                    pair_fy <= fcomp(pair_dy, pair_dx, pair_dy);
                    state <= ST_PAIR_ACC;
                end

                ST_PAIR_ACC: begin
                    if (pair_sel == 2'd0) begin
                        ax0 <= ax0 + pair_fx; ay0 <= ay0 + pair_fy;
                        ax1 <= ax1 - pair_fx; ay1 <= ay1 - pair_fy;
                        pair_sel <= 2'd1;
                        state <= ST_PAIR_PRE;
                    end else if (pair_sel == 2'd1) begin
                        ax0 <= ax0 + pair_fx; ay0 <= ay0 + pair_fy;
                        ax2 <= ax2 - pair_fx; ay2 <= ay2 - pair_fy;
                        pair_sel <= 2'd2;
                        state <= ST_PAIR_PRE;
                    end else begin
                        ax1 <= ax1 + pair_fx; ay1 <= ay1 + pair_fy;
                        ax2 <= ax2 - pair_fx; ay2 <= ay2 - pair_fy;
                        state <= ST_UPDATE;
                    end
                end

                ST_UPDATE: begin
                    vx0 <= vx0 + (ax0 >>> 8); vy0 <= vy0 + (ay0 >>> 8);
                    vx1 <= vx1 + (ax1 >>> 8); vy1 <= vy1 + (ay1 >>> 8);
                    vx2 <= vx2 + (ax2 >>> 8); vy2 <= vy2 + (ay2 >>> 8);
                    x0 <= x0 + (vx0 >>> 8);  y0 <= y0 + (vy0 >>> 8);
                    x1 <= x1 + (vx1 >>> 8);  y1 <= y1 + (vy1 >>> 8);
                    x2 <= x2 + (vx2 >>> 8);  y2 <= y2 + (vy2 >>> 8);
                    state <= ST_METRIC_PRE;
                end

                ST_METRIC_PRE: begin
                    metric_sel <= 0;
                    step_failed <= 1'b0;
                    state <= ST_METRIC_CHK;
                end

                ST_METRIC_CHK: begin
                    case (metric_sel)
                        3'd0: step_failed <= step_failed | pair_collision(x1-x0, y1-y0);
                        3'd1: step_failed <= step_failed | pair_collision(x2-x0, y2-y0);
                        3'd2: step_failed <= step_failed | pair_collision(x2-x1, y2-y1);
                        3'd3: step_failed <= step_failed | body_escape(x0, y0);
                        3'd4: step_failed <= step_failed | body_escape(x1, y1);
                        default: step_failed <= step_failed | body_escape(x2, y2);
                    endcase
                    if (metric_sel == 3'd5) begin
                        state <= ST_METRIC_DONE;
                    end else begin
                        metric_sel <= metric_sel + 1'b1;
                    end
                end

                ST_METRIC_DONE: begin
                    if (step_failed) begin
                        failed <= 1'b1;
                    end else begin
                        survived_steps <= survived_steps + 1'b1;
                    end

                    if (failed || step_failed || (step_idx + 1'b1 >= steps_limit)) begin
                        state <= ST_DONE;
                    end else begin
                        step_idx <= step_idx + 1'b1;
                        pair_sel <= 0;
                        state <= ST_PAIR_PRE;
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    valid_stable <= (!failed && !error && (survived_steps >= steps_limit));
                    fitness <= ((!failed && !error && (survived_steps >= steps_limit)) ? 64'h0000_0001_0000_0000 : 64'd0)
                               + {32'd0, survived_steps};
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule