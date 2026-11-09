module tb_master #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MEM_DEPTH = 64,
    parameter int MAX_WAIT = 50
);
    localparam int WORD_BYTES = DATA_WIDTH / 8;
    localparam int MEM_NBYTES = MEM_DEPTH * WORD_BYTES;

    logic clk = 1'b0;
    logic rst;
    int latency = 0;
    int errors = 0;
    int checks = 0;
    int completed_requests = 0;
    int wishbone_responses = 0;

    always #5 clk = ~clk;

    wishbone_if wbif (.SCLK(clk), .SRESET(rst));
    bus_protocol_if requester ();
    bus_protocol_if slave_busif ();

    master DUT (
        .ms_if(wbif),
        .bc_if(requester)
    );

    slave S (
        .wbif(wbif),
        .busif(slave_busif)
    );

    dummy_peripheral #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(MEM_DEPTH),
        .BYTE_OFFSET(0)
    ) M (
        .clk(clk), .rst_n(!rst), .s(slave_busif), .latency(latency)
    );

    task automatic sig_fail(input string what);
        errors++;
        $display("FAIL %0t: %s", $time, what);
    endtask

    task automatic check_bit(input logic got, input logic exp, input string label);
        checks++;
        if (got !== exp)
            sig_fail($sformatf("%s: expected %b, got %b", label, exp, got));
    endtask

    task automatic check_data(
        input logic [DATA_WIDTH-1:0] got,
        input logic [DATA_WIDTH-1:0] exp,
        input string label
    );
        checks++;
        if (got !== exp)
            sig_fail($sformatf("%s: expected %h, got %h", label, exp, got));
    endtask

    // Completion count check
    always @(posedge clk) begin : REQUEST_MONITOR
        if (!rst) begin
            if (requester.wen && requester.ren)
                sig_fail("requester wen and ren simultaneously asserted");
            if ((requester.wen || requester.ren) && !requester.request_stall)
                completed_requests++;
            if (wbif.ACK && wbif.ERR)
                sig_fail("Wishbone ACK and ERR asserted together");
            if (wbif.ACK || wbif.ERR)
                wishbone_responses++;
        end
    end

    // Monitor translation during transfer
    always @(negedge clk) begin : TRANSLATION_MONITOR
        if (!rst && wbif.CYC && wbif.STB) begin
            checks += 4;
            if (wbif.ADR !== requester.addr)
                sig_fail($sformatf("ADR translation: WB %h requester %h", wbif.ADR, requester.addr));
            if (wbif.WDAT !== requester.wdata)
                sig_fail("WDAT translation incorrect");
            if (wbif.SEL !== requester.strobe)
                sig_fail("SEL translation incorrect");
            if (wbif.WE !== requester.wen)
                sig_fail("WE translation incorrect");
        end
    end

    task automatic drive_idle();
        requester.wen = 1'b0;
        requester.ren = 1'b0;
        requester.addr = '0;
        requester.wdata = '0;
        requester.strobe = '0;
    endtask

    // Issue one bus_protocol_if command. Request remains stable until
    // the requester-side completion handshake (wen|ren && !request_stall).
    // Sampling at negedge is used to avoid races with the positive-edge FSMs;
    // keep the request through the next positive edge for the completion.
    task automatic bus_cycle(
        input logic we,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] wdata,
        input logic [WORD_BYTES-1:0] sel,
        input string label,
        output logic [DATA_WIDTH-1:0] rdata,
        output logic err
    );
        int waited;
        bit complete;
        waited = 0;
        complete = 0;
        rdata = '0;
        err = 1'b0;

        @(posedge clk); #1;
        requester.addr = addr;
        requester.wdata = wdata;
        requester.strobe = sel;
        requester.wen = we;
        requester.ren = !we;

        while (!complete && waited < MAX_WAIT) begin
            @(negedge clk);
            waited++;
            if (!requester.request_stall) begin
                // Capture before next rising edge clears the response.
                rdata = requester.rdata;
                err = requester.error;
                complete = 1;
            end
        end

        if (!complete)
            sig_fail($sformatf("%s: requester timeout at %h", label, addr));

        // Keep request stable for unntl completion edge
        @(posedge clk); #1;
        drive_idle();
        @(posedge clk); #1;
        check_bit(requester.request_stall, 1'b0, {label, ": idle stall"});
    endtask

    task automatic bus_write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [WORD_BYTES-1:0] sel,
        input logic expect_err,
        input string label
    );
        logic [DATA_WIDTH-1:0] unused;
        logic got_err;
        bus_cycle(1'b1, addr, data, sel, label, unused, got_err);
        check_bit(got_err, expect_err, {label, ": error"});
    endtask

    task automatic bus_read(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [WORD_BYTES-1:0] sel,
        input logic expect_err,
        input logic [DATA_WIDTH-1:0] expected,
        input string label
    );
        logic [DATA_WIDTH-1:0] got;
        logic got_err;
        bus_cycle(1'b0, addr, '0, sel, label, got, got_err);
        check_bit(got_err, expect_err, {label, ": error"});
        if (!expect_err)
            check_data(got, expected, label);
    endtask

    // timeout watchdog.
    initial begin : WATCHDOG
        #100000;
        $fatal(1, "tb_master: global timeout");
    end

    initial begin : TEST_SEQUENCE
        drive_idle();
        rst = 1'b1;
        if (DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0 || MEM_DEPTH < 4)
            $fatal(1, "tb_master: invalid memory configuration");
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // 1. Idle after reset.
        check_bit(wbif.CYC, 1'b0, "idle CYC");
        check_bit(wbif.STB, 1'b0, "idle STB");
        check_bit(requester.request_stall, 1'b0, "idle request_stall");

        // 2. Basic writes and reads.
        for (int i = 0; i < 8; i++)
            bus_write(ADDR_WIDTH'(i * WORD_BYTES), DATA_WIDTH'(32'hC0DE_0000 + i),
                      '1, 1'b0, $sformatf("write word %0d", i));
        for (int i = 0; i < 8; i++)
            bus_read(ADDR_WIDTH'(i * WORD_BYTES), '1, 1'b0,
                     DATA_WIDTH'(32'hC0DE_0000 + i), $sformatf("read word %0d", i));

        // 3.Byte-select write/overwrite
        if (DATA_WIDTH == 32) begin
            bus_write(ADDR_WIDTH'(8 * WORD_BYTES), 32'hFFFF_FFFF,
                      '1, 1'b0, "initialize partial-write word");
            bus_write(ADDR_WIDTH'(8 * WORD_BYTES), 32'h0000_00AB,
                      WORD_BYTES'(1), 1'b0, "write low byte");
            bus_read(ADDR_WIDTH'(8 * WORD_BYTES), '1, 1'b0,
                     DATA_WIDTH'(32'hFFFF_FFAB), "read after partial write");
        end

        // 4. Delayed peripheral response
        latency = 2;
        bus_write(ADDR_WIDTH'(9 * WORD_BYTES), DATA_WIDTH'(32'hDEAD_BEEF),
                  '1, 1'b0, "stalled write");
        bus_read(ADDR_WIDTH'(9 * WORD_BYTES), '1, 1'b0,
                 DATA_WIDTH'(32'hDEAD_BEEF), "stalled read");
        latency = 0;

        // 5. Peripheral out-of-range error
        bus_read(ADDR_WIDTH'(MEM_NBYTES), '1, 1'b1, '0, "invalid address error");
        bus_read('0, '1, 1'b0, DATA_WIDTH'(32'hC0DE_0000), "recovery after error");

        // 6. Boundary and rapid transactions
        bus_write(ADDR_WIDTH'(MEM_NBYTES - WORD_BYTES), DATA_WIDTH'(32'hBEEF_1234),
                  '1, 1'b0, "last word write");
        bus_read(ADDR_WIDTH'(MEM_NBYTES - WORD_BYTES), '1, 1'b0,
                 DATA_WIDTH'(32'hBEEF_1234), "last word read");
        bus_read(ADDR_WIDTH'(WORD_BYTES), '1, 1'b0,
                 DATA_WIDTH'(32'hC0DE_0001), "switch back to first words");

        repeat (3) @(negedge clk);
        $display("tb_master: %0d requester completions, %0d Wishbone responses",
                 completed_requests, wishbone_responses);
        if (errors == 0)
            $display("tb_master: PASS (%0d checks)", checks);
        else
            $display("tb_master: FAIL (%0d errors, %0d checks)", errors, checks);
        $finish;
    end
endmodule
