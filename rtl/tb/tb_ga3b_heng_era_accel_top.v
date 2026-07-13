// SPDX-License-Identifier: MIT
`timescale 1ns/1ps

module tb_ga3b_heng_era_accel_top;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [31:0] s_tdata = 32'd0;
    reg s_tvalid = 1'b0;
    wire s_tready;
    reg s_tlast = 1'b0;
    wire [31:0] m_tdata;
    wire m_tvalid;
    reg m_tready = 1'b1;
    wire m_tlast;
    wire irq_done;
    wire proto_error;

    always #5 clk = ~clk;

    ga3b_heng_era_accel_top dut (
        .aclk(clk), .aresetn(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .irq_done(irq_done), .proto_error(proto_error)
    );

    task send_word;
        input [31:0] data;
        input last;
        begin
            @(posedge clk);
            s_tdata <= data; s_tvalid <= 1'b1; s_tlast <= last;
            while (!s_tready) @(posedge clk);
            @(posedge clk);
            s_tvalid <= 1'b0; s_tlast <= 1'b0; s_tdata <= 32'd0;
        end
    endtask

    integer i;
    integer timeout;
    integer rx_count;
    reg [31:0] first_word;
    reg got_last;

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Task packet: magic, control, max_gen, steps, rates, seed0, seed1, then 12*(min,max,scale).
        send_word(32'h4741_3342, 1'b0);
        send_word({18'd0, 6'd8, 6'd12, 2'd1}, 1'b0); // restricted4, 12 genes, pop=8
        send_word(32'd3, 1'b0);
        send_word(32'd16, 1'b0);
        send_word({16'hC000, 16'h0800}, 1'b0);
        send_word(32'h1234_5678, 1'b0);
        send_word(32'h8765_4321, 1'b0);
        for (i = 0; i < 12; i = i + 1) begin
            send_word(-32'sd65536, 1'b0);
            send_word( 32'sd65536, 1'b0);
            send_word( 32'sd1024, (i == 11));
        end

        timeout = 0; rx_count = 0; got_last = 0; first_word = 0;
        while (!got_last && timeout < 30000) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (m_tvalid && m_tready) begin
                if (rx_count == 0) first_word = m_tdata;
                rx_count = rx_count + 1;
                if (m_tlast) got_last = 1;
            end
        end

        if (!got_last) begin
            $display("TB_FAIL top result timeout");
            $finish;
        end
        if (first_word != 32'h5253_4C54) begin
            $display("TB_FAIL bad result magic %08x", first_word);
            $finish;
        end
        if (proto_error) begin
            $display("TB_FAIL proto_error asserted");
            $finish;
        end
        $display("TB_PASS top AXIS result words=%0d irq_done=%0b", rx_count, irq_done);
        repeat (5) @(posedge clk);
        $finish;
    end
endmodule
