`timescale 1ns/1ps
module tb_ga3b_pure3_hifi_dual;
    localparam [31:0] TEST_STEPS=32'd100000;
    reg clk=0, rst_n=0, start=0;
    reg [255:0] chromosome;
    wire done_sym,done_lf,valid_sym,valid_lf;
    wire [31:0] steps_sym,steps_lf;
    integer cycles;
    reg seen_sym=0,seen_lf=0;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(done_sym) seen_sym<=1;
        if(done_lf) seen_lf<=1;
    end

    ga3b_pure3_hifi_fitness_lane #(.INTEGRATOR_MODE(0)) u_sym(
        .clk(clk),.rst_n(rst_n),.start(start),.steps_limit(TEST_STEPS),
        .chromosome_flat(chromosome),.busy(),.done(done_sym),.fitness(),
        .survived_steps(steps_sym),.valid_stable(valid_sym),.error());
    ga3b_pure3_hifi_fitness_lane #(.INTEGRATOR_MODE(1)) u_lf(
        .clk(clk),.rst_n(rst_n),.start(start),.steps_limit(TEST_STEPS),
        .chromosome_flat(chromosome),.busy(),.done(done_lf),.fitness(),
        .survived_steps(steps_lf),.valid_stable(valid_lf),.error());

    initial begin
        chromosome=0;
        chromosome[0*32 +:32]=32'h0000f852;
        chromosome[1*32 +:32]=32'hffffc1c5;
        chromosome[2*32 +:32]=32'h00000776;
        chromosome[3*32 +:32]=32'h000006eb;
        chromosome[4*32 +:32]=32'hffff07ae;
        chromosome[5*32 +:32]=32'h00003e3b;
        chromosome[6*32 +:32]=32'h00000776;
        chromosome[7*32 +:32]=32'h000006eb;
        repeat(5) @(posedge clk); rst_n<=1;
        repeat(3) @(posedge clk); start<=1;
        @(posedge clk); start<=0;
        cycles=0;
        while((!seen_sym || !seen_lf) && cycles<8000000) begin @(posedge clk); cycles=cycles+1; end
        if(seen_sym && seen_lf && valid_sym && valid_lf && steps_sym==TEST_STEPS && steps_lf==TEST_STEPS)
            $display("TB_PASS hifi_dual sym_steps=%0d lf_steps=%0d cycles=%0d",steps_sym,steps_lf,cycles);
        else
            $display("TB_FAIL hifi_dual seen=%b%b valid=%b%b steps=%0d/%0d cycles=%0d",seen_sym,seen_lf,valid_sym,valid_lf,steps_sym,steps_lf,cycles);
        $finish;
    end
endmodule
