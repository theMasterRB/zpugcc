// ethan path: slave.sv + aft sram_controller
module aft_sram_path #(
    parameter logic [31:0] BASE_ADDR = 32'h0002_0000
) (
    wishbone_if.slave wbif,
    output logic n_OE [1:0],
    output logic n_CE [1:0],
    output logic n_WE [1:0],
    output logic n_LB [1:0],
    output logic n_UB [1:0],
    output logic iopad_n_oe,
    output logic [17:0] addr,
    output logic [15:0] wdata,
    input  logic [15:0] rdata_in
);
    // bus between slave and sram controller
    bus_protocol_if from_slave();
    bus_protocol_if to_sram();

    slave SLAVE (
        .wbif(wbif),
        .busif(from_slave)
    );

    assign to_sram.wen             = from_slave.wen;
    assign to_sram.ren             = from_slave.ren;
    // take away the base address
    assign to_sram.addr            = from_slave.addr - BASE_ADDR;
    assign to_sram.wdata           = from_slave.wdata;
    assign to_sram.strobe          = from_slave.strobe;
    assign to_sram.is_burst        = from_slave.is_burst;
    assign to_sram.burst_type      = from_slave.burst_type;
    assign to_sram.burst_length    = from_slave.burst_length;
    assign to_sram.secure_transfer = from_slave.secure_transfer;
    assign from_slave.rdata         = to_sram.rdata;
    assign from_slave.error         = to_sram.error;
    assign from_slave.request_stall = to_sram.request_stall;

    // aft sram controller
    sram_controller SRAM_CTRL (
        .CLK(wbif.SCLK),
        .n_RST(!wbif.SRESET),
        .prif(to_sram),
        .hintif(to_sram),
        .n_OE(n_OE),
        .n_CE(n_CE),
        .n_WE(n_WE),
        .n_LB(n_LB),
        .n_UB(n_UB),
        .iopad_n_oe(iopad_n_oe),
        .addr(addr),
        .wdata(wdata),
        .rdata_in(rdata_in)
    );
endmodule

// fake counter for the aft sram controller
module socetlib_counter #(
    parameter NBITS = 4
) (
    input  logic             CLK,
    input  logic             nRST,
    input  logic             clear,
    input  logic             count_enable,
    input  logic [NBITS-1:0] overflow_val,
    output logic [NBITS-1:0] count_out,
    output logic             overflow_flag
);
    always_ff @(posedge CLK, negedge nRST) begin
        if (!nRST) begin
            count_out <= '0;
        end else if (clear) begin
            count_out <= '0;
        end else if (count_enable) begin
            if (count_out == overflow_val) count_out <= '0;
            else                           count_out <= count_out + 1'b1;
        end
    end
    assign overflow_flag = (count_out == overflow_val);
endmodule

// testbench, DIRECT = 1 is mine, DIRECT = 0 is ethan's, build with --timescale 1ns/100ps
module tb_wb_sram_controller;
    parameter bit DIRECT = 1;

    localparam logic [31:0] BASE   = 32'h0002_0000;
    localparam int          NWORDS = 4096;

    logic clk = 1'b0;
    logic rst;
    int   errors = 0;
    int   checks = 0;

    // clock
    always #16 clk = ~clk;

    // wishbone bus
    wishbone_if wbif(.SCLK(clk), .SRESET(rst));

    // sram pins
    logic n_OE [1:0];
    logic n_CE [1:0];
    logic n_WE [1:0];
    logic n_LB [1:0];
    logic n_UB [1:0];
    logic iopad_n_oe;
    logic [17:0] addr;
    logic [15:0] wdata, rdata;
    wire  [15:0] data_pins;

    // pick which design to test
    if (DIRECT) begin : g_direct
        wb_sram_controller #(
            .BASE_ADDR(BASE),
            .NWORDS(NWORDS)
        ) DUT (
            .wbif(wbif),
            .n_OE(n_OE), .n_CE(n_CE), .n_WE(n_WE), .n_LB(n_LB), .n_UB(n_UB),
            .iopad_n_oe(iopad_n_oe),
            .addr(addr),
            .wdata(wdata),
            .rdata_in(rdata)
        );
    end else begin : g_aft
        aft_sram_path #(
            .BASE_ADDR(BASE)
        ) DUT (
            .wbif(wbif),
            .n_OE(n_OE), .n_CE(n_CE), .n_WE(n_WE), .n_LB(n_LB), .n_UB(n_UB),
            .iopad_n_oe(iopad_n_oe),
            .addr(addr),
            .wdata(wdata),
            .rdata_in(rdata)
        );
    end

    // data pins
    io_pad PAD (
        .oe_n(iopad_n_oe),
        .wdata(wdata),
        .rdata(rdata),
        .data(data_pins)
    );

    // two sram chips
    sram_sim #(.NREGS(NWORDS), .ORDER(0), .INFILE("none")) CHIP0 (
        .n_OE(n_OE[0]), .n_CE(n_CE[0]), .n_WE(n_WE[0]), .n_LB(n_LB[0]), .n_UB(n_UB[0]),
        .addr(addr), .DOUT(data_pins)
    );

    sram_sim #(.NREGS(NWORDS), .ORDER(1), .INFILE("none")) CHIP1 (
        .n_OE(n_OE[1]), .n_CE(n_CE[1]), .n_WE(n_WE[1]), .n_LB(n_LB[1]), .n_UB(n_UB[1]),
        .addr(addr), .DOUT(data_pins)
    );

    // what the memory should have
    logic [31:0] golden [NWORDS];

    initial for (int i = 0; i < NWORDS; i++) golden[i] = '0;

    // which byte SEL bit i writes (aft is backwards)
    function automatic int lane(input int i);
        return DIRECT ? i : 3 - i;
    endfunction

    // update the golden memory
    function automatic void golden_write(input int idx, input logic [31:0] data, input logic [3:0] sel);
        for (int i = 0; i < 4; i++)
            if (sel[i]) golden[idx][8*lane(i) +: 8] = data[8*lane(i) +: 8];
    endfunction

    // what a read should give
    function automatic logic [31:0] golden_read(input int idx, input logic [3:0] sel);
        logic [31:0] mask;
        mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
        return DIRECT ? (golden[idx] & mask) : golden[idx];
    endfunction

    // checks every cycle
    int chip_cycles = 0;

    always @(negedge clk) begin
        if (!rst) begin

            if ((wbif.ACK || wbif.ERR) && !(wbif.CYC && wbif.STB)) begin
                errors++;
                $display("FAIL %0t: ACK/ERR high while CYC&STB is low", $time);
            end

            if (wbif.ACK && wbif.ERR) begin
                errors++;
                $display("FAIL %0t: ACK and ERR high together", $time);
            end

            if (!n_CE[0] && !n_CE[1]) begin
                errors++;
                $display("FAIL %0t: both chips on at once", $time);
            end

            if (!n_CE[0] || !n_CE[1]) chip_cycles++;

            if (wbif.CYC && wbif.STB) begin
                if (!n_CE[0] && (n_LB[0] !== !wbif.SEL[lane(3)] || n_UB[0] !== !wbif.SEL[lane(2)])) begin
                    errors++;
                    $display("FAIL %0t: chip 0 LB/UB = %b%b do not match SEL %b", $time, n_LB[0], n_UB[0], wbif.SEL);
                end
                if (!n_CE[1] && (n_LB[1] !== !wbif.SEL[lane(1)] || n_UB[1] !== !wbif.SEL[lane(0)])) begin
                    errors++;
                    $display("FAIL %0t: chip 1 LB/UB = %b%b do not match SEL %b", $time, n_LB[1], n_UB[1], wbif.SEL);
                end
            end
        end
    end

    // check helpers
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

    // one wishbone transfer
    task automatic wb_cycle(
        input  logic        we,
        input  logic [31:0] adr,
        input  logic [31:0] wdat,
        input  logic [3:0]  sel,
        input  string       label,
        output logic [31:0] rdat,
        output logic        err
    );
        int waited = 0;

        @(posedge clk); #1;

        wbif.ADR  = adr;
        wbif.WDAT = wdat;
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
            $display("FAIL %0t: %s: no ACK/ERR for addr %h (bus hung)", $time, label, adr);
        end
        rdat = wbif.RDAT;
        err  = wbif.ERR;

        @(posedge clk); #1;
        wbif.CYC = 1'b0;
        wbif.STB = 1'b0;
        wbif.WE  = 1'b0;
        wbif.SEL = '0;
    endtask

    // write one word
    task automatic wb_write(input int idx, input logic [31:0] data, input logic [3:0] sel, input string label);
        logic [31:0] unused;
        logic        err;
        wb_cycle(1'b1, BASE + idx*4, data, sel, label, unused, err);
        check_bit(err, 1'b0, {label, " ERR"});
        golden_write(idx, data, sel);
    endtask

    // read one word
    task automatic wb_read(input int idx, input logic [3:0] sel, input string label);
        logic [31:0] data;
        logic        err;
        wb_cycle(1'b0, BASE + idx*4, '0, sel, label, data, err);
        check_bit(err, 1'b0, {label, " ERR"});
        check_eq(data, golden_read(idx, sel), label);
    endtask

    // bad address should give ERR
    task automatic wb_bad(input logic we, input logic [31:0] adr, input string label);
        logic [31:0] data;
        logic        err;
        int          start = chip_cycles;
        wb_cycle(we, adr, 32'hBAD0_BAD0, 4'hF, label, data, err);
        check_bit(err, 1'b1, {label, " ERR"});
        check_eq(chip_cycles - start, 0, {label, ": chips not touched"});
    endtask

    // give up on a read then read again
    task automatic wb_abort_then_read(input int abort_idx, input int hold, input int idx, input string label);
        logic [31:0] data;
        int          waited = 0;

        @(posedge clk); #1;
        wbif.ADR = BASE + abort_idx*4;
        wbif.WE  = 1'b0;
        wbif.SEL = 4'hF;
        wbif.CYC = 1'b1;
        wbif.STB = 1'b1;
        repeat (hold) @(posedge clk);
        #1;
        wbif.CYC = 1'b0;
        wbif.STB = 1'b0;

        @(posedge clk); #1;
        wbif.ADR = BASE + idx*4;
        wbif.CYC = 1'b1;
        wbif.STB = 1'b1;
        do begin
            @(negedge clk);
            waited++;
        end while (!wbif.ACK && !wbif.ERR && waited < 50);
        data = wbif.RDAT;
        @(posedge clk); #1;
        wbif.CYC = 1'b0;
        wbif.STB = 1'b0;

        check_eq(data, golden_read(idx, 4'hF), label);
    endtask

    initial begin
        logic [31:0] data;
        logic [3:0]  sel;
        int          idx;

        wbif.ADR  = '0;
        wbif.WDAT = '0;
        wbif.WE   = 1'b0;
        wbif.SEL  = '0;
        wbif.CYC  = 1'b0;
        wbif.STB  = 1'b0;

        $display("tb_wb_sram_controller: DIRECT = %0d (%s)", DIRECT,
                 DIRECT ? "wb_sram_controller" : "slave.sv + AFT sram_controller");

        // reset
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        check_bit(wbif.ACK, 1'b0, "idle ACK");
        check_bit(wbif.ERR, 1'b0, "idle ERR");

        // write and read some words
        for (int i = 0; i < 16; i++) wb_write(i, 32'h1234_5600 + i, 4'hF, $sformatf("write w%0d", i));
        for (int i = 0; i < 16; i++) wb_read (i, 4'hF, $sformatf("read w%0d", i));

        // first and last word
        wb_write(0,          32'hA5A5_0000, 4'hF, "write first word");
        wb_write(NWORDS - 1, 32'h5A5A_FFFF, 4'hF, "write last word");
        wb_read (0,          4'hF, "read first word");
        wb_read (NWORDS - 1, 4'hF, "read last word");

        // byte writes
        wb_write(20, 32'hFFFF_FFFF, 4'hF, "fill w20");
        for (int i = 0; i < 4; i++) begin
            wb_write(20, 32'hA0B1_C2D3 + i, 4'b0001 << i, $sformatf("write byte %0d", i));
            wb_read (20, 4'hF, $sformatf("after byte %0d", i));
        end
        wb_write(20, 32'h1111_2222, 4'b0011, "write low half");
        wb_read (20, 4'hF, "after low half");
        wb_write(20, 32'h3333_4444, 4'b1100, "write high half");
        wb_read (20, 4'hF, "after high half");
        wb_write(20, 32'h5555_5555, 4'b0000, "write with SEL = 0");
        wb_read (20, 4'hF, "after SEL = 0");

        // byte reads
        for (int i = 0; i < 4; i++) wb_read(20, 4'b0001 << i, $sformatf("read byte %0d", i));
        wb_read(20, 4'b0011, "read low half");
        wb_read(20, 4'b1100, "read high half");

        // random tests
        for (int n = 0; n < 300; n++) begin
            idx  = $urandom_range(NWORDS - 1);
            data = $urandom;
            sel  = 4'($urandom);
            if ($urandom_range(1) == 1) wb_write(idx, data, sel, $sformatf("random write #%0d w%0d", n, idx));
            else                        wb_read (idx, 4'hF,      $sformatf("random read #%0d w%0d",  n, idx));
        end
        for (int i = 0; i < 64; i++) begin
            idx = $urandom_range(NWORDS - 1);
            wb_read(idx, 4'hF, $sformatf("random read-back w%0d", idx));
        end

        // bad addresses (mine only)
        if (DIRECT) begin
            wb_bad(1'b0, BASE + NWORDS*4, "read past the end");
            wb_bad(1'b1, BASE + NWORDS*4, "write past the end");
            wb_bad(1'b0, BASE - 4,        "read below base");
            wb_read(0, 4'hF, "read after errors");
        end

        // aborts
        wb_abort_then_read(1, 1, 2, "abort after 1 cycle, then read w2");
        wb_abort_then_read(1, 4, 3, "abort after 4 cycles, then read w3");
        wb_read(4, 4'hF, "read after aborts");

        if (chip_cycles == 0) begin
            errors++;
            $display("FAIL: chips were never turned on");
        end
        // pass or fail
        if (errors == 0) begin
            $display("tb_wb_sram_controller: PASS (%0d checks)", checks);
            $finish;
        end else begin
            $fatal(1, "tb_wb_sram_controller: FAIL (%0d errors, %0d checks)", errors, checks);
        end
    end

endmodule
