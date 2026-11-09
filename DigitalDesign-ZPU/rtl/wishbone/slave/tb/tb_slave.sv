
module tb_slave;
    logic clk = 1'b0;
    logic rst;
    int   latency = 0;
    int   errors  = 0;
    int   checks  = 0;

    always #5 clk = ~clk;

    wishbone_if     wbif(.SCLK(clk), .SRESET(rst));
    bus_protocol_if busif();

    slave DUT (
        .wbif(wbif),
        .busif(busif)
    );
    
    dummy_peripheral #(
        .MEM_DEPTH(25),
        .BYTE_OFFSET(32'h0000_0000)
    ) M (
        .clk(clk),
        .rst_n(!rst),
        .s(busif),
        .latency(latency)
    );

    int completions = 0;

    always @(posedge clk) begin
        if (!rst) begin

            if ((wbif.ACK || wbif.ERR) && !(wbif.CYC && wbif.STB)) begin
                errors++;
                $display("FAIL %0t: ACK/ERR high while CYC&STB is low", $time);
            end

            if (wbif.ACK && wbif.ERR) begin
                errors++;
                $display("FAIL %0t: ACK and ERR high together", $time);
            end

            if (busif.wen && busif.ren) begin
                errors++;
                $display("FAIL %0t: wen and ren high together", $time);
            end
            if ((busif.wen || busif.ren) && !busif.request_stall) completions++;
        end
    end

    int access_cycles = 0;
    int idle_cycles   = 0;

    task automatic sig_fail(input string what);
        errors++;
        $display("FAIL %0t: %s", $time, what);
    endtask

    always @(negedge clk) begin
        if (!rst) begin
            if (busif.wen || busif.ren) begin

                access_cycles++;
                if (busif.addr   !== wbif.ADR)  sig_fail($sformatf("addr %h != ADR %h",   busif.addr,   wbif.ADR));
                if (busif.wdata  !== wbif.WDAT) sig_fail($sformatf("wdata %h != WDAT %h", busif.wdata,  wbif.WDAT));
                if (busif.strobe !== wbif.SEL)  sig_fail($sformatf("strobe %b != SEL %b", busif.strobe, wbif.SEL));
                if (busif.wen    !==  wbif.WE)  sig_fail($sformatf("wen %b != WE %b",     busif.wen,    wbif.WE));
                if (busif.ren    !== !wbif.WE)  sig_fail($sformatf("ren %b != !WE %b",    busif.ren,   !wbif.WE));
                if (!(wbif.CYC && wbif.STB))    sig_fail("peripheral asked while CYC&STB is low");
                if (DUT.state.name() != "ACTIVE")
                    sig_fail($sformatf("peripheral asked in state %s", DUT.state.name()));
            end else begin

                idle_cycles++;
                if (busif.addr   !== '0) sig_fail($sformatf("addr %h while idle (expected 0)",   busif.addr));
                if (busif.wdata  !== '0) sig_fail($sformatf("wdata %h while idle (expected 0)",  busif.wdata));
                if (busif.strobe !== '0) sig_fail($sformatf("strobe %b while idle (expected 0)", busif.strobe));
            end

            if (busif.is_burst !== 1'b0 || busif.burst_type !== '0 ||
                busif.burst_length !== '0 || busif.secure_transfer !== 1'b0)
                sig_fail("hint signals not tied to 0");
        end
    end

    task automatic check_eq(input logic [31:0] got, input logic [31:0] exp, input string label);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL %s: expected %h, got %h", label, exp, got);
        end
    endtask

    task automatic check_bit(input logic got, input logic exp, input string label);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("FAIL %s: expected %b, got %b", label, exp, got);
        end
    endtask

    task automatic check_state(input string expected, input string label);
        checks++;
        if (DUT.state.name() != expected) begin
            errors++;
            $display("FAIL %s: slave FSM in %s, expected %s", label, DUT.state.name(), expected);
        end
    endtask

    task automatic check_completions(input int start_count, input int n, input string label);
        checks++;
        if (completions - start_count != n) begin
            errors++;
            $display("FAIL %s: peripheral saw %0d accesses, expected %0d",
                     label, completions - start_count, n);
        end
    endtask

    task automatic wb_cycle(
        input  logic        we,
        input  logic [31:0] addr,
        input  logic [31:0] wdata,
        input  logic [3:0]  sel,
        input  string       label,
        output logic [31:0] rdata,
        output logic        err
    );
        int waited = 0;

        @(posedge clk); #1;

        check_state("IDLE", {label, ": FSM back in IDLE before request"});

        wbif.ADR  = addr;
        wbif.WDAT = wdata;
        wbif.WE   = we;
        wbif.SEL  = sel;
        wbif.CYC  = 1'b1;
        wbif.STB  = 1'b1;

        do begin
            @(negedge clk);
            waited++;
        end while (!wbif.ACK && !wbif.ERR && waited < 50);

        if (waited >= 50) begin
            errors++;
            $display("FAIL %0t: %s: no ACK/ERR for addr %h (bus hung)", $time, label, addr);
        end
        rdata = wbif.RDAT;
        err   = wbif.ERR;

        @(posedge clk); #1;
        wbif.CYC = 1'b0;
        wbif.STB = 1'b0;
        wbif.WE  = 1'b0;
        wbif.SEL = '0;

        @(negedge clk);
        check_bit(wbif.ACK, 1'b0, {label, ": ACK low after CYC/STB drop"});
        check_bit(wbif.ERR, 1'b0, {label, ": ERR low after CYC/STB drop"});
        check_bit(busif.wen || busif.ren, 1'b0, {label, ": no peripheral request after CYC/STB drop"});
    endtask

    task automatic wb_write(input logic [31:0] addr, input logic [31:0] data,
                            input logic [3:0] sel, input logic expect_err, input string label);
        logic [31:0] unused;
        logic        err;
        wb_cycle(1'b1, addr, data, sel, label, unused, err);
        check_bit(err, expect_err, {label, " ERR"});
    endtask

    task automatic wb_read(input logic [31:0] addr, input logic [3:0] sel,
                           input logic expect_err, input logic [31:0] expected, input string label);
        logic [31:0] data;
        logic        err;
        wb_cycle(1'b0, addr, '0, sel, label, data, err);
        check_bit(err, expect_err, {label, " ERR"});
        if (!expect_err) check_eq(data, expected, label);
    endtask

    task automatic wb_abort(input logic we, input logic [31:0] addr, input logic [31:0] wdata,
                            input int stall_cycles, input string label);
        int start_count;

        latency = 1_000_000;
        start_count = completions;

        @(posedge clk); #1;
        check_state("IDLE", {label, ": FSM in IDLE before request"});
        wbif.ADR  = addr;
        wbif.WDAT = wdata;
        wbif.WE   = we;
        wbif.SEL  = 4'hF;
        wbif.CYC  = 1'b1;
        wbif.STB  = 1'b1;

        @(posedge clk);
        repeat (stall_cycles) begin
            @(negedge clk);
            check_state("ACTIVE", {label, ": FSM ACTIVE while stalled"});
            check_bit(we ? busif.wen : busif.ren, 1'b1, {label, ": peripheral asked while stalled"});
            check_bit(wbif.ACK, 1'b0, {label, ": no ACK while stalled"});
            check_bit(wbif.ERR, 1'b0, {label, ": no ERR while stalled"});
        end

        @(posedge clk); #1;
        wbif.CYC = 1'b0;
        wbif.STB = 1'b0;
        wbif.WE  = 1'b0;
        wbif.SEL = '0;

        @(negedge clk);
        check_bit(busif.wen, 1'b0, {label, ": wen dropped on abort"});
        check_bit(busif.ren, 1'b0, {label, ": ren dropped on abort"});
        check_bit(wbif.ACK,  1'b0, {label, ": no ACK on abort"});
        check_bit(wbif.ERR,  1'b0, {label, ": no ERR on abort"});

        @(posedge clk); #1;
        check_state("IDLE", {label, ": FSM ACTIVE -> IDLE after abort"});

        repeat (4) begin
            @(negedge clk);
            check_bit(wbif.ACK || wbif.ERR, 1'b0, {label, ": no late ACK/ERR"});
            check_bit(busif.wen || busif.ren, 1'b0, {label, ": no late peripheral request"});
        end
        check_completions(start_count, 0, {label, ": peripheral never finished"});

        latency = 0;
    endtask

    initial begin
        int start_count;

        wbif.ADR  = '0;
        wbif.WDAT = '0;
        wbif.WE   = 1'b0;
        wbif.SEL  = '0;
        wbif.CYC  = 1'b0;
        wbif.STB  = 1'b0;

        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        check_state("IDLE", "after reset");
        check_bit(wbif.ACK, 1'b0, "idle ACK");
        check_bit(wbif.ERR, 1'b0, "idle ERR");

        for (int i = 0; i < 8; i++) begin
            start_count = completions;
            wb_write(i*4, 32'hC0DE_0000 + i, 4'hF, 1'b0, $sformatf("write w%0d", i));
            check_completions(start_count, 1, $sformatf("write w%0d", i));
        end
        for (int i = 0; i < 8; i++) begin
            start_count = completions;
            wb_read(i*4, 4'hF, 1'b0, 32'hC0DE_0000 + i, $sformatf("read w%0d", i));
            check_completions(start_count, 1, $sformatf("read w%0d", i));
        end

        latency = 2;
        start_count = completions;
        wb_write(32'h20, 32'hDEAD_BEEF, 4'hF, 1'b0, "stalled write w8");
        wb_read (32'h20, 4'hF, 1'b0, 32'hDEAD_BEEF, "stalled read w8");
        check_completions(start_count, 2, "stalled pair");
        latency = 0;

        wb_write(32'h24, 32'hFFFF_FFFF, 4'hF,    1'b0, "fill w9");
        wb_write(32'h24, 32'h0000_00AB, 4'b0001, 1'b0, "byte write w9");
        wb_read (32'h24, 4'hF, 1'b0, 32'hFFFF_FFAB, "read after byte write");

        wb_read(32'h25, 4'b0010, 1'b0, 32'hFFFF_FFAB, "unaligned byte address");

        start_count = completions;
        wb_read(32'h0000_0400, 4'hF, 1'b1, '0, "peripheral error");
        check_completions(start_count, 1, "peripheral error");

        wb_read(32'h0, 4'hF, 1'b0, 32'hC0DE_0000, "read after error");

        wb_abort(1'b0, 32'h8, '0, 1, "abort read (1 cycle)");
        wb_abort(1'b0, 32'h8, '0, 5, "abort read (5 cycles)");
        wb_read (32'h8, 4'hF, 1'b0, 32'hC0DE_0002, "read after aborted reads");

        wb_abort(1'b1, 32'hC, 32'hBAD0_BAD0, 5, "abort write");
        wb_read (32'hC, 4'hF, 1'b0, 32'hC0DE_0003, "aborted write did not land");
        wb_write(32'hC, 32'h1234_5678, 4'hF, 1'b0, "write after aborted write");
        wb_read (32'hC, 4'hF, 1'b0, 32'h1234_5678, "read after write after abort");

        @(posedge clk); #1;
        check_state("IDLE", "end of test");

        repeat (3) @(negedge clk);
        $display("tb_slave: signal checks ran on %0d access cycles and %0d idle cycles",
                 access_cycles, idle_cycles);
        if (access_cycles == 0) begin
            errors++;
            $display("FAIL: signal-assignment monitor never saw an access");
        end
        if (errors == 0) $display("tb_slave: PASS (%0d checks)", checks);
        else             $display("tb_slave: FAIL (%0d errors, %0d checks)", errors, checks);
        $finish;
    end

endmodule
