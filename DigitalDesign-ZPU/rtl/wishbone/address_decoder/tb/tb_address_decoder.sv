module tb_address_decoder #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int N_SLAVES = 3,
    parameter int SLAVE_NBYTES = 100,
    parameter logic [ADDR_WIDTH-1:0] FIRST_SLAVE_OFFSET = 32'h0000_0800
);
    localparam int WORD_BYTES = DATA_WIDTH / 8;
    localparam int MAX_WAIT = 50;

    logic clk = 1'b0;
    logic rst;
    int latency = 0;
    int errors = 0;
    int checks = 0;

    always #5 clk = ~clk;

    // Ascending
    typedef logic [ADDR_WIDTH-1:0] wb_map_t [N_SLAVES+1];
    function automatic wb_map_t make_map();
        wb_map_t result;
        for (int i = 0; i <= N_SLAVES; i++)
            result[i] = FIRST_SLAVE_OFFSET + i * SLAVE_NBYTES;
        return result;
    endfunction
    localparam wb_map_t WB_MAP = make_map();

    wishbone_if master_wb (.SCLK(clk), .SRESET(rst));
    wishbone_if slaves_wb [0:N_SLAVES-1] (.SCLK(clk), .SRESET(rst));
    bus_protocol_if busif [0:N_SLAVES-1] ();

    address_decoder #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .N_SLAVES(N_SLAVES), .WB_MAP(WB_MAP)
    ) DUT (
        .master(master_wb), .slaves(slaves_wb)
    );

    // Instatiate a wrapper and a dummy peripheral at different addresses
    for (genvar g = 0; g < N_SLAVES; g++) begin : GEN_SLAVES
        slave S (
            .wbif(slaves_wb[g]),
            .busif(busif[g])
        );
        dummy_peripheral #(
            .MEM_DEPTH(SLAVE_NBYTES / WORD_BYTES),
            .BYTE_OFFSET(WB_MAP[g])
        ) M (
            .clk(clk), .rst_n(!rst), .s(busif[g]), .latency(latency)
        );
    end

    // Arrays for testbench loops
    logic [0:N_SLAVES-1] slave_cyc, slave_stb, slave_ack, slave_err, slave_we;
    logic [0:N_SLAVES-1] per_wen, per_ren, per_stall;
    logic [ADDR_WIDTH-1:0] slave_adr [N_SLAVES];
    logic [DATA_WIDTH-1:0] slave_wdat [N_SLAVES];
    logic [DATA_WIDTH-1:0] slave_rdat [N_SLAVES];
    logic [WORD_BYTES-1:0] slave_sel [N_SLAVES];

    int access_cycles [N_SLAVES] = '{default:0};
    int idle_cycles [N_SLAVES] = '{default:0};
    int completions [N_SLAVES] = '{default:0};

    for (genvar g = 0; g < N_SLAVES; g++) begin : GEN_OBSERVE
        assign slave_cyc[g] = slaves_wb[g].CYC;
        assign slave_stb[g] = slaves_wb[g].STB;
        assign slave_ack[g] = slaves_wb[g].ACK;
        assign slave_err[g] = slaves_wb[g].ERR;
        assign slave_we[g] = slaves_wb[g].WE;
        assign slave_adr[g] = slaves_wb[g].ADR;
        assign slave_wdat[g] = slaves_wb[g].WDAT;
        assign slave_rdat[g] = slaves_wb[g].RDAT;
        assign slave_sel[g] = slaves_wb[g].SEL;
        assign per_wen[g] = busif[g].wen;
        assign per_ren[g] = busif[g].ren;
        assign per_stall[g] = busif[g].request_stall;
    end

    task automatic sig_fail(input string what);
        errors++;
        $display("FAIL %0t: %s", $time, what);
    endtask

    task automatic check_eq(
        input logic [DATA_WIDTH-1:0] got,
        input logic [DATA_WIDTH-1:0] exp,
        input string label
    );
        checks++;
        if (got !== exp)
            sig_fail($sformatf("%s: expected %h, got %h", label, exp, got));
    endtask

    task automatic check_bit(input logic got, input logic exp, input string label);
        checks++;
        if (got !== exp)
            sig_fail($sformatf("%s: expected %b, got %b", label, exp, got));
    endtask

    task automatic check_completions(input int idx, input int start_count,
                                     input int expected, input string label);
        checks++;
        if (completions[idx] - start_count != expected)
            sig_fail($sformatf("%s: peripheral %0d completed %0d, expected %0d",
                label, idx, completions[idx] - start_count, expected));
    endtask

    // Compute expected address selection
    always @(negedge clk) begin : ROUTING_MONITOR
        int selected_slave;
        logic expected_cyc, expected_stb;
        if (!rst) begin
            selected_slave = -1;
            for (int i = 0; i < N_SLAVES; i++)
                if (master_wb.ADR >= WB_MAP[i] && master_wb.ADR < WB_MAP[i+1])
                    selected_slave = i;

            for (int i = 0; i < N_SLAVES; i++) begin
                expected_cyc = master_wb.CYC && (selected_slave == i);
                expected_stb = master_wb.STB && (selected_slave == i);
                checks += 2;
                if (slave_cyc[i] !== expected_cyc || slave_stb[i] !== expected_stb)
                    sig_fail($sformatf("slave %0d CYC/STB incorrect, address %h", i, master_wb.ADR));
                if (slave_adr[i] !== master_wb.ADR ||
                    slave_wdat[i] !== master_wb.WDAT ||
                    slave_we[i] !== master_wb.WE ||
                    slave_sel[i] !== master_wb.SEL)
                    sig_fail($sformatf("slave %0d broadcast request incorrect", i));
            end

            checks++;
            if (selected_slave >= 0) begin
                if (master_wb.RDAT !== slave_rdat[selected_slave] ||
                    master_wb.ACK !== slave_ack[selected_slave] ||
                    master_wb.ERR !== slave_err[selected_slave])
                    sig_fail($sformatf("response mux incorrect for slave %0d", selected_slave));
            end else if (master_wb.RDAT !== '0 || master_wb.ACK !== 1'b0 ||
                         master_wb.ERR !== (master_wb.CYC && master_wb.STB))
                sig_fail("unmapped-address response incorrect");

            if (master_wb.ACK && master_wb.ERR)
                sig_fail("ACK and ERR high together");
            if ((master_wb.ACK || master_wb.ERR) && !(master_wb.CYC && master_wb.STB))
                sig_fail("ACK/ERR without CYC and STB");
        end
    end

    // Peripheral access check
    for (genvar g = 0; g < N_SLAVES; g++) begin : GEN_MONITORS
        always @(negedge clk) begin
            if (!rst) begin
                if (per_wen[g] || per_ren[g]) begin
                    access_cycles[g]++;
                    if (busif[g].addr !== master_wb.ADR ||
                        busif[g].wdata !== master_wb.WDAT ||
                        busif[g].strobe !== master_wb.SEL)
                        sig_fail($sformatf("peripheral %0d address/data/strobe mismatch", g));
                    if (per_wen[g] !== master_wb.WE || per_ren[g] !== !master_wb.WE)
                        sig_fail($sformatf("peripheral %0d read/write enable mismatch", g));
                    if (!(slave_cyc[g] && slave_stb[g]))
                        sig_fail($sformatf("peripheral %0d requested without CYC/STB", g));
                end else begin
                    idle_cycles[g]++;
                    if (busif[g].addr !== '0 || busif[g].wdata !== '0 ||
                        busif[g].strobe !== '0)
                        sig_fail($sformatf("peripheral %0d idle outputs nonzero", g));
                end
                if (busif[g].is_burst !== 1'b0 || busif[g].burst_type !== '0 ||
                    busif[g].burst_length !== '0 || busif[g].secure_transfer !== 1'b0)
                    sig_fail($sformatf("peripheral %0d hint signals not zero", g));
                if ((per_wen[g] || per_ren[g]) && !per_stall[g])
                    completions[g]++;
            end
        end
    end

    task automatic drive_idle();
        master_wb.CYC = 1'b0;
        master_wb.STB = 1'b0;
        master_wb.WE = 1'b0;
        master_wb.SEL = '0;
    endtask

    task automatic wb_cycle(
        input logic we,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] wdata,
        input logic [WORD_BYTES-1:0] sel,
        input string label,
        output logic [DATA_WIDTH-1:0] rdata,
        output logic err
    );
        int waited;
        bit completed;
        waited = 0;
        completed = 0;
        rdata = '0;
        err = 1'b0;

        @(posedge clk); #1;
        check_bit(master_wb.ACK, 1'b0, {label, ": no stale ACK"});
        check_bit(master_wb.ERR, 1'b0, {label, ": no stale ERR"});
        master_wb.ADR = addr;
        master_wb.WDAT = wdata;
        master_wb.WE = we;
        master_wb.SEL = sel;
        master_wb.CYC = 1'b1;
        master_wb.STB = 1'b1;

        while (!completed && waited < MAX_WAIT) begin
            @(negedge clk);
            waited++;
            if (master_wb.ACK || master_wb.ERR) begin
                rdata = master_wb.RDAT;
                err = master_wb.ERR;
                completed = 1;
            end
        end
        if (!completed) begin
            sig_fail($sformatf("%s: timeout at address %h", label, addr));
            err = 1'b1;
        end

        // Sample on negedge to avoid race-condition
        #1;
        drive_idle();
        @(posedge clk); #1;
        check_bit(master_wb.ACK, 1'b0, {label, ": ACK cleared"});
        check_bit(master_wb.ERR, 1'b0, {label, ": ERR cleared"});
        for (int i = 0; i < N_SLAVES; i++) begin
            check_bit(slave_cyc[i], 1'b0, $sformatf("%s: slave %0d CYC low", label, i));
            check_bit(slave_stb[i], 1'b0, $sformatf("%s: slave %0d STB low", label, i));
        end
    endtask

    task automatic wb_write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [WORD_BYTES-1:0] sel,
        input logic expect_err, input string label
    );
        logic [DATA_WIDTH-1:0] unused;
        logic err;
        wb_cycle(1'b1, addr, data, sel, label, unused, err);
        check_bit(err, expect_err, {label, ": ERR"});
    endtask

    task automatic wb_read(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [WORD_BYTES-1:0] sel,
        input logic expect_err,
        input logic [DATA_WIDTH-1:0] expected,
        input string label
    );
        logic [DATA_WIDTH-1:0] data;
        logic err;
        wb_cycle(1'b0, addr, '0, sel, label, data, err);
        check_bit(err, expect_err, {label, ": ERR"});
        if (!expect_err) check_eq(data, expected, label);
    endtask

    task automatic wb_abort(
        input logic we,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] wdata,
        input int stall_cycles, input string label
    );
        int start_count [N_SLAVES];
        latency = 1_000_000;
        for (int i = 0; i < N_SLAVES; i++) start_count[i] = completions[i];

        @(posedge clk); #1;
        master_wb.ADR = addr;
        master_wb.WDAT = wdata;
        master_wb.WE = we;
        master_wb.SEL = '1;
        master_wb.CYC = 1'b1;
        master_wb.STB = 1'b1;

        repeat (stall_cycles) begin
            @(negedge clk);
            check_bit(master_wb.ACK, 1'b0, {label, ": no ACK during stall"});
            check_bit(master_wb.ERR, 1'b0, {label, ": no ERR during stall"});
        end
        #1; 
        drive_idle();
        #1;
        for (int i = 0; i < N_SLAVES; i++) begin
            check_bit(slave_cyc[i], 1'b0, $sformatf("%s: slave %0d CYC dropped", label, i));
            check_bit(slave_stb[i], 1'b0, $sformatf("%s: slave %0d STB dropped", label, i));
        end
        @(posedge clk); #1;
        for (int i = 0; i < N_SLAVES; i++) begin
            check_bit(per_wen[i], 1'b0, $sformatf("%s: slave %0d wen dropped", label, i));
            check_bit(per_ren[i], 1'b0, $sformatf("%s: slave %0d ren dropped", label, i));
        end
        repeat (4) begin
            @(negedge clk);
            check_bit(master_wb.ACK, 1'b0, {label, ": no late ACK"});
            check_bit(master_wb.ERR, 1'b0, {label, ": no late ERR"});
        end
        for (int i = 0; i < N_SLAVES; i++)
            check_completions(i, start_count[i], 0, {label, ": no completed peripheral request"});
        latency = 0;
    endtask

    task automatic check_cyc_without_stb(input int target);
        @(posedge clk); #1;
        master_wb.ADR = WB_MAP[target];
        master_wb.CYC = 1'b1;
        master_wb.STB = 1'b0;
        #1;
        for (int i = 0; i < N_SLAVES; i++) begin
            check_bit(slave_cyc[i], i == target, $sformatf("CYC-only: slave %0d", i));
            check_bit(slave_stb[i], 1'b0, $sformatf("STB-only: slave %0d", i));
        end
        drive_idle();
    endtask

    initial begin : TEST_SEQUENCE
        int start_count [N_SLAVES];
        master_wb.ADR = '0;
        master_wb.WDAT = '0;
        master_wb.WE = 1'b0;
        master_wb.SEL = '0;
        master_wb.CYC = 1'b0;
        master_wb.STB = 1'b0;

        if (N_SLAVES < 1 || DATA_WIDTH < 8 || DATA_WIDTH % 8 != 0 ||
            SLAVE_NBYTES < WORD_BYTES || SLAVE_NBYTES % WORD_BYTES != 0 ||
            FIRST_SLAVE_OFFSET % WORD_BYTES != 0)
            $fatal(1, "Invalid decoder TB memory configuration");
        for (int i = 0; i < N_SLAVES; i++)
            if (WB_MAP[i] >= WB_MAP[i+1])
                $fatal(1, "WB_MAP overflow or nonascending at %0d", i);

        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // Test 1: Idle / reset.
        check_bit(master_wb.ACK, 1'b0, "idle ACK");
        check_bit(master_wb.ERR, 1'b0, "idle ERR");
        for (int i = 0; i < N_SLAVES; i++) begin
            check_bit(slave_cyc[i], 1'b0, $sformatf("idle slave %0d CYC", i));
            check_bit(slave_stb[i], 1'b0, $sformatf("idle slave %0d STB", i));
        end

        // Test 2: Unique writes, plus completion-count isolation.
        for (int i = 0; i < N_SLAVES; i++) begin
            for (int j = 0; j < N_SLAVES; j++) start_count[j] = completions[j];
            wb_write(WB_MAP[i], 32'hC0DE_0000 + i, '1, 1'b0,
                     $sformatf("write slave %0d", i));
            for (int j = 0; j < N_SLAVES; j++)
                check_completions(j, start_count[j], (i == j ? 1 : 0),
                    $sformatf("write slave %0d isolation", i));
        end

        // Test 3: Each slave retains its own first word.
        for (int i = 0; i < N_SLAVES; i++)
            wb_read(WB_MAP[i], '1, 1'b0, 32'hC0DE_0000 + i,
                    $sformatf("read slave %0d", i));

        // Test 4: Last aligned word before each exclusive end address.
        for (int i = 0; i < N_SLAVES; i++) begin
            wb_write(WB_MAP[i+1] - WORD_BYTES, 32'hABCD_0000 + i, '1, 1'b0,
                     $sformatf("last word slave %0d", i));
            wb_read(WB_MAP[i+1] - WORD_BYTES, '1, 1'b0, 32'hABCD_0000 + i,
                    $sformatf("read last word slave %0d", i));
        end

        // Test 5: Unmapped ranges (no peripheral should be selected).
        if (WB_MAP[0] >= WORD_BYTES)
            wb_read(WB_MAP[0] - WORD_BYTES, '1, 1'b1, '0, "below first slave");
        wb_read(WB_MAP[N_SLAVES], '1, 1'b1, '0, "at final exclusive end");

        // Test 6: Error recovery.
        wb_read(WB_MAP[0], '1, 1'b0, 32'hC0DE_0000, "valid read after error");

        // Test 7: Stall and preserve per-slave data.
        latency = 2;
        for (int i = 0; i < N_SLAVES; i++) begin
            wb_write(WB_MAP[i] + WORD_BYTES, 32'hDEAD_0000 + i, '1, 1'b0,
                     $sformatf("stalled write slave %0d", i));
            wb_read(WB_MAP[i] + WORD_BYTES, '1, 1'b0, 32'hDEAD_0000 + i,
                    $sformatf("stalled read slave %0d", i));
        end
        latency = 0;

        // Test 8: Aborted writes do not modify memory.
        for (int i = 0; i < N_SLAVES; i++) begin
            wb_abort(1'b1, WB_MAP[i], 32'hBAD0_BAD0, 3,
                     $sformatf("abort slave %0d write", i));
            wb_read(WB_MAP[i], '1, 1'b0, 32'hC0DE_0000 + i,
                    $sformatf("read after aborted write slave %0d", i));
        end

        // Test 9: Reverse-order switching.
        for (int i = N_SLAVES-1; i >= 0; i--)
            wb_read(WB_MAP[i] + WORD_BYTES, '1, 1'b0, 32'hDEAD_0000 + i,
                    $sformatf("reverse-order read slave %0d", i));

        // Test 10: CYC without STB is forwarded to exactly one slave.
        check_cyc_without_stb(0);
        if (N_SLAVES > 1) check_cyc_without_stb(N_SLAVES-1);

        repeat (3) @(negedge clk);
        for (int i = 0; i < N_SLAVES; i++)
            $display("slave %0d: %0d access cycles, %0d idle cycles, %0d completions",
                i, access_cycles[i], idle_cycles[i], completions[i]);
        if (errors == 0) $display("tb_address_decoder: PASS (%0d checks)", checks);
        else $display("tb_address_decoder: FAIL (%0d errors, %0d checks)", errors, checks);
        $finish;
    end
endmodule
