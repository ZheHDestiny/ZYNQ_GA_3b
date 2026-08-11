`timescale 1ns/1ps

module tb_ga3b_pure3_rf_accel_top;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [31:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;
    wire [31:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    wire irq_done;
    wire proto_error;

    reg [31:0] result0 [0:13];
    reg [31:0] result1 [0:13];
    integer i;
    integer timeout;

    ga3b_pure3_rf_accel_top dut (
        .aclk(clk), .aresetn(rst_n),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .irq_done(irq_done), .proto_error(proto_error)
    );

    task send_word;
        input [31:0] data;
        input last;
        begin
            // Drive on the falling edge, then hold VALID until exactly the
            // first rising edge where READY is sampled high.  Deassert on the
            // following falling edge so a READY transition cannot duplicate
            // the beat.
            @(negedge clk);
            s_axis_tdata = data;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            do @(posedge clk); while (!s_axis_tready);
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task send_bound;
        input signed [31:0] lo;
        input signed [31:0] hi;
        input signed [31:0] scale;
        input last;
        begin
            send_word(lo[31:0], 1'b0);
            send_word(hi[31:0], 1'b0);
            send_word(scale[31:0], last);
        end
    endtask

    task send_task;
        begin
            send_word(32'h4741_3342, 1'b0);
            send_word((32 << 8) | (8 << 2), 1'b0);
            send_word(32'd2, 1'b0);
            send_word(32'd16, 1'b0);
            send_word({16'hC000, 16'h1000}, 1'b0);
            send_word(32'h1234_5678, 1'b0);
            send_word(32'h8765_4321, 1'b0);
            send_bound(-32'sd131072, 32'sd131072, 32'sd6554, 1'b0);
            send_bound(-32'sd131072, 32'sd131072, 32'sd6554, 1'b0);
            send_bound(-32'sd65536,   32'sd65536,  32'sd2048, 1'b0);
            send_bound(-32'sd65536,   32'sd65536,  32'sd2048, 1'b0);
            send_bound(-32'sd131072, 32'sd131072, 32'sd6554, 1'b0);
            send_bound(-32'sd131072, 32'sd131072, 32'sd6554, 1'b0);
            send_bound(-32'sd65536,   32'sd65536,  32'sd2048, 1'b0);
            send_bound(-32'sd65536,   32'sd65536,  32'sd2048, 1'b1);
        end
    endtask

    task receive_result;
        input integer run_id;
        integer count;
        begin
            count = 0;
            timeout = 0;
            while (count < 14 && timeout < 250000) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (m_axis_tvalid && m_axis_tready) begin
                    if (run_id == 0) result0[count] = m_axis_tdata;
                    else result1[count] = m_axis_tdata;
                    count = count + 1;
                    if (m_axis_tlast && count != 14) begin
                        $display("TB_FAIL run=%0d early_tlast count=%0d", run_id, count);
                        $finish;
                    end
                end
            end
            if (timeout >= 250000) begin
                $display("TB_FAIL run=%0d timeout count=%0d", run_id, count);
                $finish;
            end
        end
    endtask

    initial begin
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 1'b1;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Two identical packets without resetting the wrapper/core.  This is
        // the re-entrant use case exercised by the persistent board agent.
        send_task();
        receive_result(0);
        send_task();
        receive_result(1);

        if (result0[0] != 32'h5253_4C54 || result1[0] != 32'h5253_4C54) begin
            $display("TB_FAIL bad_magic first=%08x second=%08x", result0[0], result1[0]);
            $finish;
        end
        if (result0[1][17:16] != 2'b00 || result1[1][17:16] != 2'b00) begin
            $display("TB_FAIL status first=%08x second=%08x", result0[1], result1[1]);
            $finish;
        end
        for (i = 0; i < 14; i = i + 1) begin
            if (result0[i] !== result1[i]) begin
                $display("TB_FAIL repeat_drift word=%0d first=%08x second=%08x", i, result0[i], result1[i]);
                $finish;
            end
        end
        $display("TB_PASS pure3_rf_repeat words=14 fitness=%08x_%08x steps=%0d",
                 result0[4], result0[3], result0[5]);
        $finish;
    end
endmodule
