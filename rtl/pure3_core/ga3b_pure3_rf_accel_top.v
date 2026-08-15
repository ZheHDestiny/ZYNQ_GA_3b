// SPDX-License-Identifier: MIT
// AXI-Stream wrapper for the additional pure3 resource-fit implementation.
`timescale 1ns/1ps

module ga3b_pure3_rf_accel_top #(
    parameter integer GENE_COUNT    = 8,
    parameter integer GENE_WIDTH    = 32,
    parameter integer FITNESS_WIDTH = 64,
    parameter integer HIFI_ENABLE   = 1,
    parameter integer INTEGRATOR_MODE = 0
)(
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire [31:0]                  s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output reg                          s_axis_tready,
    input  wire                         s_axis_tlast,
    output reg  [31:0]                  m_axis_tdata,
    output reg                          m_axis_tvalid,
    input  wire                         m_axis_tready,
    output reg                          m_axis_tlast,
    output wire                         irq_done,
    output reg                          proto_error
);
    localparam [31:0] MAGIC_TASK = 32'h4741_3342; // "GA3B"
    localparam [31:0] MAGIC_RSLT = 32'h5253_4C54; // "RSLT"

    localparam [3:0] ST_IDLE  = 4'd0;
    localparam [3:0] ST_RX    = 4'd1;
    localparam [3:0] ST_START = 4'd2;
    localparam [3:0] ST_RUN   = 4'd3;
    localparam [3:0] ST_TX    = 4'd4;

    reg [3:0] state;
    reg [7:0] rx_word;
    reg [3:0] bound_idx;
    reg [1:0] bound_phase;
    reg signed [31:0] tmp_min, tmp_max;

    reg [15:0] max_gen;
    reg [31:0] steps_limit;
    reg [15:0] mutation_rate_q16;
    reg [15:0] crossover_rate_q16;
    reg [31:0] seed0, seed1;

    reg core_start;
    reg bounds_we;
    reg [5:0] bounds_index;
    reg signed [31:0] bounds_min, bounds_max, bounds_mutation_scale;

    wire core_done, core_error;
    wire [15:0] cur_gen;
    wire [5:0] best_index;
    wire [63:0] best_fitness;
    wire [31:0] best_heng_steps;
    wire [GENE_COUNT*GENE_WIDTH-1:0] best_chromosome_flat;
    reg [7:0] tx_word;
    reg irq_done_r;
    wire [7:0] tx_last_word = 8'd5 + GENE_COUNT[7:0];

    assign irq_done = irq_done_r;

    ga3b_pure3_rf_ga_core #(
        .POP_SIZE(32),
        .GENE_COUNT(GENE_COUNT),
        .GENE_WIDTH(GENE_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .HIFI_ENABLE(HIFI_ENABLE),
        .INTEGRATOR_MODE(INTEGRATOR_MODE)
    ) u_core (
        .clk(aclk),
        .rst_n(aresetn),
        .start(core_start),
        .max_gen(max_gen),
        .steps_limit(steps_limit),
        .mutation_rate_q16(mutation_rate_q16),
        .crossover_rate_q16(crossover_rate_q16),
        .seed0(seed0),
        .seed1(seed1),
        .bounds_we(bounds_we),
        .bounds_index(bounds_index),
        .bounds_min(bounds_min),
        .bounds_max(bounds_max),
        .bounds_mutation_scale(bounds_mutation_scale),
        .busy(),
        .done(core_done),
        .error(core_error),
        .cur_gen(cur_gen),
        .best_index(best_index),
        .best_fitness(best_fitness),
        .best_heng_steps(best_heng_steps),
        .best_chromosome_flat(best_chromosome_flat)
    );

    function [31:0] result_word;
        input [7:0] idx;
        integer gi;
        begin
            case (idx)
                8'd0: result_word = MAGIC_RSLT;
                8'd1: result_word = {14'd0, proto_error, core_error, cur_gen};
                8'd2: result_word = {26'd0, best_index};
                8'd3: result_word = best_fitness[31:0];
                8'd4: result_word = best_fitness[63:32];
                8'd5: result_word = best_heng_steps;
                default: begin
                    gi = idx - 8'd6;
                    if (gi < GENE_COUNT)
                        result_word = best_chromosome_flat[gi*GENE_WIDTH +: GENE_WIDTH];
                    else
                        result_word = 32'd0;
                end
            endcase
        end
    endfunction

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= ST_IDLE; rx_word <= 0; bound_idx <= 0; bound_phase <= 0;
            s_axis_tready <= 1'b0; m_axis_tvalid <= 1'b0; m_axis_tdata <= 0; m_axis_tlast <= 1'b0;
            proto_error <= 1'b0; core_start <= 1'b0; bounds_we <= 1'b0; bounds_index <= 0;
            tmp_min <= 0; tmp_max <= 0;
            max_gen <= 16'd2; steps_limit <= 32'd16; mutation_rate_q16 <= 16'h1000; crossover_rate_q16 <= 16'hC000;
            seed0 <= 32'h12345678; seed1 <= 32'h87654321; tx_word <= 0; irq_done_r <= 1'b0;
            bounds_min <= 0; bounds_max <= 0; bounds_mutation_scale <= 0;
        end else begin
            core_start <= 1'b0;
            bounds_we <= 1'b0;
            case (state)
                ST_IDLE: begin
                    m_axis_tvalid <= 1'b0; m_axis_tlast <= 1'b0; s_axis_tready <= 1'b1;
                    rx_word <= 0; bound_idx <= 0; bound_phase <= 0; proto_error <= 1'b0;
                    // Consume the first word only on a real AXI-Stream
                    // handshake.  After a result packet, TREADY is still low
                    // for the first IDLE cycle; testing VALID alone consumed
                    // the next task's magic one cycle before the sender saw
                    // READY, so the same beat was consumed again as word 1.
                    if (s_axis_tvalid && s_axis_tready) begin
                        irq_done_r <= 1'b0;
                        if (s_axis_tdata != MAGIC_TASK) proto_error <= 1'b1;
                        rx_word <= 8'd1;
                        state <= ST_RX;
                    end
                end

                ST_RX: begin
                    s_axis_tready <= 1'b1;
                    if (s_axis_tvalid) begin
                        if (rx_word == 8'd1) begin
                            // Keep packet layout compatible with the v0.3 wrapper,
                            // but this implementation intentionally accepts only
                            // gene_count=8, pop_size=32.
                            if (s_axis_tdata[7:2] != 6'd8 || s_axis_tdata[13:8] != 6'd32)
                                proto_error <= 1'b1;
                        end else if (rx_word == 8'd2) begin
                            max_gen <= s_axis_tdata[15:0];
                        end else if (rx_word == 8'd3) begin
                            steps_limit <= s_axis_tdata;
                        end else if (rx_word == 8'd4) begin
                            mutation_rate_q16 <= s_axis_tdata[15:0];
                            crossover_rate_q16 <= s_axis_tdata[31:16];
                        end else if (rx_word == 8'd5) begin
                            seed0 <= s_axis_tdata;
                        end else if (rx_word == 8'd6) begin
                            seed1 <= s_axis_tdata;
                        end else begin
                            case (bound_phase)
                                2'd0: begin tmp_min <= s_axis_tdata; bound_phase <= 2'd1; end
                                2'd1: begin tmp_max <= s_axis_tdata; bound_phase <= 2'd2; end
                                default: begin
                                    bounds_index <= {2'd0, bound_idx};
                                    bounds_min <= tmp_min;
                                    bounds_max <= tmp_max;
                                    bounds_mutation_scale <= s_axis_tdata;
                                    bounds_we <= (bound_idx < GENE_COUNT[3:0]);
                                    bound_phase <= 2'd0;
                                    bound_idx <= bound_idx + 1'b1;
                                end
                            endcase
                        end
                        rx_word <= rx_word + 1'b1;
                        if (s_axis_tlast) begin
                            s_axis_tready <= 1'b0;
                            state <= ST_START;
                        end
                    end
                end

                ST_START: begin
                    s_axis_tready <= 1'b0;
                    if (!proto_error) core_start <= 1'b1;
                    tx_word <= 0;
                    state <= proto_error ? ST_TX : ST_RUN;
                end

                ST_RUN: begin
                    if (core_done) begin
                        irq_done_r <= 1'b1;
                        tx_word <= 0;
                        state <= ST_TX;
                    end
                end

                ST_TX: begin
                    if (!m_axis_tvalid) begin
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata <= result_word(tx_word);
                        m_axis_tlast <= (tx_word == tx_last_word);
                    end else if (m_axis_tready) begin
                        if (tx_word == tx_last_word) begin
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            tx_word <= tx_word + 1'b1;
                            m_axis_tdata <= result_word(tx_word + 1'b1);
                            m_axis_tlast <= (tx_word + 1'b1 == tx_last_word);
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
