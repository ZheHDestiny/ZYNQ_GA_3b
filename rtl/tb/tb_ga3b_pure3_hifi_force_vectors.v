`timescale 1ns/1ps
module tb_ga3b_pure3_hifi_force_vectors;
    reg clk=0,rst_n=0,start=0;
    reg signed [47:0] dx,dy;
    wire done;
    wire signed [47:0] fx,fy;
    integer errors=0;
    always #5 clk=~clk;
    ga3b_pure3_hifi_force_pair dut(.clk(clk),.rst_n(rst_n),.start(start),.dx(dx),.dy(dy),.busy(),.done(done),.fx(fx),.fy(fy));

    task check;
        input signed [47:0] tx,ty,ex,ey;
        input [47:0] tolerance;
        reg signed [48:0] dfx,dfy;
        begin
            dx=tx;dy=ty;@(posedge clk);start<=1;@(posedge clk);start<=0;
            wait(done); #1;
            dfx=$signed(fx)-$signed(ex); dfy=$signed(fy)-$signed(ey);
            if(dfx<0) dfx=-dfx; if(dfy<0) dfy=-dfy;
            $display("VECTOR dx=%0d dy=%0d r2=%0d msb=%0d idx=%0d frac=%0d q=%0d base=%0d fx=%0d fy=%0d exp=%0d/%0d",
                tx,ty,dut.r2_safe,dut.r2_msb,dut.lut_index,dut.lut_frac,dut.q_exp,dut.coeff_base,fx,fy,ex,ey);
            if(dfx>tolerance || dfy>tolerance) errors=errors+1;
            @(posedge clk);
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);rst_n<=1;repeat(2) @(posedge clk);
        check(48'sd4294967296,0,48'sd16777216,0,48'd2000);
        check(48'sd8589934592,0,48'sd4194304,0,48'd2000);
        check(48'sd2147483648,0,48'sd67108864,0,48'd8000);
        check(48'sd4294967296,48'sd4294967296,48'sd5931642,48'sd5931642,48'd8000);
        check(48'sd4166118277,-48'sd1043677053,48'sd16275149,-48'sd4077176,48'd12000);
        check(-48'sd8332274006,48'sd2088105983,-48'sd4068493,48'sd1019583,48'd12000);
        if(errors==0) $display("TB_PASS force_vectors"); else $display("TB_FAIL force_vectors errors=%0d",errors);
        $finish;
    end
endmodule
