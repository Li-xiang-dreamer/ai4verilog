`timescale 1ns/1ps

module tb_float_adder;

    reg         clk;
    reg         rst_n;
    reg         en;
    reg [31:0]  aIn;
    reg [31:0]  bIn;
    wire        busy;
    wire        out_vld;
    wire [31:0] out;

    integer     pass_count;
    integer     fail_count;
    integer     trace_fd;

    float_adder dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (en),
        .aIn    (aIn),
        .bIn    (bIn),
        .busy   (busy),
        .out_vld(out_vld),
        .out    (out)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        #1;
        if (trace_fd != 0) begin
            $fdisplay(trace_fd, "%0t,%0b,%0b,%0b,%0b,%0b,%0d,0x%08h,0x%08h,0x%08h",
                      $time, clk, rst_n, en, busy, out_vld, dut.state, aIn, bIn, out);
        end
    end

    task wait_until_idle;
        integer timeout;
        begin
            timeout = 0;
            while (busy !== 1'b0) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 20) begin
                    $display("[TB][FAIL] timeout while waiting for busy deassert.");
                    fail_count = fail_count + 1;
                    disable wait_until_idle;
                end
            end
        end
    endtask

    task run_case;
        input [127:0] case_name;
        input [31:0]  op_a;
        input [31:0]  op_b;
        input [31:0]  expected;
        integer latency;
        begin
            wait_until_idle();

            @(negedge clk);
            aIn = op_a;
            bIn = op_b;
            en  = 1'b1;

            @(posedge clk);
            #1;
            if (busy !== 1'b1) begin
                $display("[TB][FAIL] %0s: busy did not assert after input accept.", case_name);
                fail_count = fail_count + 1;
            end

            @(negedge clk);
            en = 1'b0;

            latency = 0;
            while (out_vld !== 1'b1) begin
                @(posedge clk);
                latency = latency + 1;
                if (latency > 20) begin
                    $display("[TB][FAIL] %0s: timeout waiting for out_vld.", case_name);
                    fail_count = fail_count + 1;
                    disable run_case;
                end
            end

            #1;
            if (out !== expected) begin
                $display("[TB][FAIL] %0s: expected 0x%08h, got 0x%08h.", case_name, expected, out);
                fail_count = fail_count + 1;
            end else begin
                $display("[TB][PASS] %0s: out=0x%08h, latency=%0d cycles.", case_name, out, latency);
                pass_count = pass_count + 1;
            end

            @(posedge clk);
            #1;
            if (out_vld !== 1'b0) begin
                $display("[TB][FAIL] %0s: out_vld should stay high for only one cycle.", case_name);
                fail_count = fail_count + 1;
            end
            if (busy !== 1'b0) begin
                $display("[TB][FAIL] %0s: busy should deassert after result output completes.", case_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task run_busy_ignore_case;
        integer latency;
        begin
            wait_until_idle();

            @(negedge clk);
            aIn = 32'h3f800000;  // 1.0
            bIn = 32'h40000000;  // 2.0
            en  = 1'b1;

            @(posedge clk);
            #1;
            if (busy !== 1'b1) begin
                $display("[TB][FAIL] busy-ignore: busy did not assert after first request.");
                fail_count = fail_count + 1;
            end

            @(negedge clk);
            en  = 1'b0;
            aIn = 32'h40f00000;  // 7.5
            bIn = 32'h40f00000;  // 7.5

            @(negedge clk);
            en = 1'b1;

            @(posedge clk);
            #1;
            if (busy !== 1'b1) begin
                $display("[TB][FAIL] busy-ignore: busy unexpectedly dropped during operation.");
                fail_count = fail_count + 1;
            end

            @(negedge clk);
            en = 1'b0;

            latency = 0;
            while (out_vld !== 1'b1) begin
                @(posedge clk);
                latency = latency + 1;
                if (latency > 20) begin
                    $display("[TB][FAIL] busy-ignore: timeout waiting for first output.");
                    fail_count = fail_count + 1;
                    disable run_busy_ignore_case;
                end
            end

            #1;
            if (out !== 32'h40400000) begin
                $display("[TB][FAIL] busy-ignore: expected first request result 0x40400000, got 0x%08h.", out);
                fail_count = fail_count + 1;
            end else begin
                $display("[TB][PASS] busy-ignore: second request while busy was ignored as expected.");
                pass_count = pass_count + 1;
            end

            @(posedge clk);
            #1;
            if (busy !== 1'b0) begin
                $display("[TB][FAIL] busy-ignore: busy should deassert after first result.");
                fail_count = fail_count + 1;
            end
            if (out_vld !== 1'b0) begin
                $display("[TB][FAIL] busy-ignore: out_vld should be a one-cycle pulse.");
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst_n     = 1'b0;
        en        = 1'b0;
        aIn       = 32'd0;
        bIn       = 32'd0;
        pass_count= 0;
        fail_count= 0;
        trace_fd  = 0;

        $dumpfile("tb_float_adder.vcd");
        $dumpvars(0, tb_float_adder);
        trace_fd = $fopen("tb_float_adder_trace.csv", "w");
        if (trace_fd != 0) begin
            $fdisplay(trace_fd, "time_ps,clk,rst_n,en,busy,out_vld,state,aIn,bIn,out");
        end

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        if (busy !== 1'b0 || out_vld !== 1'b0 || out !== 32'd0) begin
            $display("[TB][FAIL] reset release: outputs are not in the expected idle state.");
            fail_count = fail_count + 1;
        end else begin
            $display("[TB][PASS] reset release: outputs returned to idle state.");
            pass_count = pass_count + 1;
        end

        run_case("1.0 + 2.0",    32'h3f800000, 32'h40000000, 32'h40400000);
        run_case("1.5 + 2.25",   32'h3fc00000, 32'h40100000, 32'h40700000);
        run_case("0.5 + 0.25",   32'h3f000000, 32'h3e800000, 32'h3f400000);
        run_case("4.0 + 0.125",  32'h40800000, 32'h3e000000, 32'h40840000);
        run_case("1.0 + 0.0",    32'h3f800000, 32'h00000000, 32'h3f800000);
        run_case("255.0 + 1.0",  32'h437f0000, 32'h3f800000, 32'h43800000);
        run_busy_ignore_case();

        $display("[TB] simulation done: pass=%0d, fail=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            if (trace_fd != 0) begin
                $fclose(trace_fd);
            end
            $finish;
        end else begin
            if (trace_fd != 0) begin
                $fclose(trace_fd);
            end
            $fatal(1, "[TB] one or more test cases failed.");
        end
    end

endmodule
