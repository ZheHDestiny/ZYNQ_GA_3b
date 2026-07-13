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

    integer rx_count;
    reg [31:0] got_magic;
    reg [31:0] got_status;
    reg [31:0] got_steps;
    reg [31:0] got_fit_lo;
    reg [31:0] got_fit_hi;
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
            @(posedge clk);
            s_axis_tdata <= data;
            s_axis_tlast <= last;
            s_axis_tvalid <= 1'b1;
            while (!s_axis_tready) @(posedge clk);
            @(posedge clk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast <= 1'b0;
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

    initial begin
        s_axis_tdata = 0; s_axis_tvalid = 0; s_axis_tlast = 0; m_axis_tready = 1'b1;
        rx_count = 0; got_magic = 0; got_status = 0; got_steps = 0; got_fit_lo = 0; got_fit_hi = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        send_word(32'h4741_3342, 1'b0);                 // magic
        send_word((32 << 8) | (8 << 2) | 0, 1'b0);      // gene=8, pop=32
        send_word(32'd2, 1'b0);                         // max_gen
        send_word(32'd16, 1'b0);                        // steps_limit
        send_word({16'hC000, 16'h2000}, 1'b0);          // crossover/mutation
        send_word(32'h1234_5678, 1'b0);
        send_word(32'h8765_4321, 1'b0);
        send_bound(-32'sd65536,  32'sd65536,  32'sd4096, 1'b0); // x0
        send_bound(-32'sd65536,  32'sd65536,  32'sd4096, 1'b0); // y0
        send_bound(-32'sd16384,  32'sd16384,  32'sd1024, 1'b0); // vx0
        send_bound(-32'sd16384,  32'sd16384,  32'sd1024, 1'b0); // vy0
        send_bound(-32'sd65536,  32'sd65536,  32'sd4096, 1'b0); // x1
        send_bound(-32'sd65536,  32'sd65536,  32'sd4096, 1'b0); // y1
        send_bound(-32'sd16384,  32'sd16384,  32'sd1024, 1'b0); // vx1
        send_bound(-32'sd16384,  32'sd16384,  32'sd1024, 1'b1); // vy1

        timeout = 0;
        while (rx_count < 14 && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (m_axis_tvalid && m_axis_tready) begin
                if (rx_count == 0) got_magic = m_axis_tdata;
                if (rx_count == 1) got_status = m_axis_tdata;
                if (rx_count == 3) got_fit_lo = m_axis_tdata;
                if (rx_count == 4) got_fit_hi = m_axis_tdata;
                if (rx_count == 5) got_steps = m_axis_tdata;
                rx_count = rx_count + 1;
                if (m_axis_tlast && rx_count != 14) begin
                    $display("TB_FAIL early tlast count=%0d", rx_count);
                    $finish;
                end
            end
        end

        if (timeout >= 200000) begin
            $display("TB_FAIL timeout rx_count=%0d irq_done=%0d", rx_count, irq_done);
            $finish;
        end
        if (got_magic != 32'h5253_4C54) begin
            $display("TB_FAIL bad magic %08x", got_magic);
            $finish;
        end
        if (got_status[17]) begin
            $display("TB_FAIL proto_error status=%08x", got_status);
            $finish;
        end
        if (got_status[16]) begin
            $display("TB_FAIL core_error status=%08x", got_status);
            $finish;
        end
        if (got_steps == 0) begin
            $display("TB_FAIL zero best_heng_steps fitness=%08x_%08x", got_fit_hi, got_fit_lo);
            $finish;
        end
        $display("TB_PASS pure3_rf words=%0d cur_gen=%0d best_steps=%0d fitness=%08x_%08x irq_done=%0d",
                 rx_count, got_status[15:0], got_steps, got_fit_hi, got_fit_lo, irq_done);
        $finish;
    end
endmodule
