// SPDX-License-Identifier: MIT
// Simple xorshift32 PRNG used by the GA RTL core.
// This module is synthesizable and intentionally small.

`timescale 1ns/1ps

module ga3b_rng_xorshift32 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        seed_we,
    input  wire [31:0] seed,
    input  wire        next,
    output reg  [31:0] random
);
    wire [31:0] xs_1;
    wire [31:0] xs_2;
    wire [31:0] xs_3;

    assign xs_1 = random ^ (random << 13);
    assign xs_2 = xs_1   ^ (xs_1   >> 17);
    assign xs_3 = xs_2   ^ (xs_2   << 5);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            random <= 32'h1BAD_F00D;
        end else if (seed_we) begin
            random <= (seed == 32'd0) ? 32'h1BAD_F00D : seed;
        end else if (next) begin
            random <= (xs_3 == 32'd0) ? 32'h1BAD_F00D : xs_3;
        end
    end
endmodule
