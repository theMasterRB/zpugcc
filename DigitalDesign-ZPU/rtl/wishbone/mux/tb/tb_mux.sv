module tb_mux #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int N_MASTERS = 3
);
    localparam int WORD_BYTES = DATA_WIDTH / 8;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    int checks = 0;
    int errors = 0;

    wishbone_if masters_wb [N_MASTERS-1:0] (.SCLK(clk), .SRESET(rst));
    wishbone_if slave_wb (.SCLK(clk), .SRESET(rst));

    wb_mux #(.NMASTERS(N_MASTERS)) DUT (
        .HCLK(clk), .HRESET(!rst),
        .m_in(masters_wb), .m_out(slave_wb)
    );

    logic [ADDR_WIDTH-1:0] req_addr [0:N_MASTERS-1];
    logic [DATA_WIDTH-1:0] req_data [0:N_MASTERS-1];
    logic [WORD_BYTES-1:0] req_sel [0:N_MASTERS-1];
    logic [N_MASTERS-1:0] req_cyc, req_stb, req_we;
    logic [N_MASTERS-1:0] got_ack, got_err;
    logic [DATA_WIDTH-1:0] got_rdata [0:N_MASTERS-1];

    for (genvar g = 0; g < N_MASTERS; g++) begin : GEN_PORTS
        assign masters_wb[g].ADR = req_addr[g];
        assign masters_wb[g].WDAT = req_data[g];
        assign masters_wb[g].SEL = req_sel[g];
        assign masters_wb[g].WE = req_we[g];
        assign masters_wb[g].CYC = req_cyc[g];
        assign masters_wb[g].STB = req_stb[g];

        assign got_ack[g] = masters_wb[g].ACK;
        assign got_err[g]  = masters_wb[g].ERR;
        assign got_rdata[g] = masters_wb[g].RDAT;
    end

    // Dummy Wishbone slaves
    logic response_enable = 1'b0;
    logic response_error = 1'b0;
    logic [DATA_WIDTH-1:0] response_data = '0;
    assign slave_wb.ACK = response_enable && !response_error &&
                            slave_wb.CYC && slave_wb.STB;
    assign slave_wb.ERR = response_enable && response_error &&
                            slave_wb.CYC && slave_wb.STB;
    assign slave_wb.RDAT = response_data;

    task automatic fail(input string message);
        errors++;
        $display("FAIL @%0t: %s", $time, message);
    endtask

    task automatic check_bit(
        input logic actual, 
        input logic expected,
        input string label
    );
        checks++;
        if (actual !== expected)
            fail($sformatf("%s: expected %b got %b", label, expected, actual));
    endtask

    task automatic check_word(
        input logic [DATA_WIDTH-1:0] actual,
        input logic [DATA_WIDTH-1:0] expected,
        input string label
    );
        checks++;
        if (actual !== expected)
            fail($sformatf("%s: expected %h got %h", label, expected, actual));
    endtask

    task automatic clear_requests();
        for (int i = 0; i < N_MASTERS; i++) begin
            req_addr[i] = '0;
            req_data[i] = '0;
            req_sel[i] = '0;
            req_cyc[i] = 1'b0;
            req_stb[i] = 1'b0;
            req_we[i] = 1'b0;
        end
    endtask

    task automatic request_master(
        input int idx, 
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic we
    );
        req_addr[idx] = addr;
        req_data[idx] = data;
        req_sel[idx]  = '1;
        req_we[idx]   = we;
        req_cyc[idx]  = 1'b1;
        req_stb[idx]  = 1'b1;
    endtask

    task automatic release_master(input int idx);
        req_cyc[idx] = 1'b0;
        req_stb[idx] = 1'b0;
    endtask

    // ensure only the owner sees a response.
    // owner index of -1 = idle mux.
    task automatic expect_owner(input int owner, input string label);
        #1;
        if (owner < 0) begin
            check_bit(slave_wb.CYC, 1'b0, {label, " idle CYC"});
            check_bit(slave_wb.STB, 1'b0, {label, " idle STB"});
        end else begin
            check_bit(slave_wb.CYC, req_cyc[owner], {label, " CYC"});
            check_bit(slave_wb.STB, req_stb[owner], {label, " STB"});
            check_bit(slave_wb.WE, req_we[owner], {label, " WE"});
            check_word(slave_wb.ADR, req_addr[owner], {label, " ADR"});
            check_word(slave_wb.WDAT, req_data[owner], {label, " WDAT"});
            checks++;
            if (slave_wb.SEL !== req_sel[owner])
                fail($sformatf("%s SEL: expected %b got %b", label,
                               req_sel[owner], slave_wb.SEL));
        end
        for (int i = 0; i < N_MASTERS; i++) begin
            check_bit(got_ack[i], (i == owner) && slave_wb.ACK,
                      $sformatf("%s master %0d ACK", label, i));
            check_bit(got_err[i], (i == owner) && slave_wb.ERR,
                      $sformatf("%s master %0d ERR", label, i));
            if (i == owner)
                check_word(got_rdata[i], response_data,
                           $sformatf("%s master %0d RDAT", label, i));
        end
    endtask

    // apply inputs after falling edge, sample owner after rising edge.
    // arbiter is clocked, so selection is not instantaneous.
    task automatic next_grant();
        @(posedge clk);
        #1;
    endtask
    

    initial begin : WATCHDOG
        #100000;
        $fatal(1, "tb_mux: global timeout");
    end

    initial begin : TEST_SEQUENCE
        clear_requests();
        response_enable = 1'b0;
        response_error = 1'b0;
        response_data = '0;
        if (N_MASTERS < 2)
            $fatal(1, "tb_mux expects N_MASTERS >= 2");

        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);
        expect_owner(-1, "reset/idle");

        // 1. Any requester on idle mux
        for (int i = 0; i < N_MASTERS; i++) begin
            @(negedge clk);
            request_master(i, ADDR_WIDTH'(32'h1000 + i*16),
                           DATA_WIDTH'(32'hCAFE_0000 + i), i[0]);
            next_grant();
            expect_owner(i, $sformatf("single master %0d", i));
            response_data = DATA_WIDTH'(32'hABCD_0000 + i);
            response_enable = 1'b1;
            expect_owner(i, $sformatf("single response %0d", i));
            @(negedge clk);
            response_enable = 1'b0;
            release_master(i);
            next_grant(); 
            expect_owner(-1, $sformatf("release %0d", i));
        end

        // 2. Prioritze lowest-index requester
        @(negedge clk);
        for (int i = 0; i < N_MASTERS; i++)
            request_master(i, ADDR_WIDTH'(32'h2000 + i*16),
                           DATA_WIDTH'(32'h1111_0000 + i), 1'b1);
        next_grant();
        expect_owner(0, "simultaneous priority");

        // 3. Owner maintain ownership of the bus with other buses pending
        repeat (3) begin
            next_grant();
            expect_owner(0, "owner retention");
        end

        // 4. Transfer error go only to owner.
        response_error = 1'b1;
        response_enable = 1'b1;
        response_data = 'hDEADBEEF;
        expect_owner(0, "error routing");
        @(negedge clk);
        response_enable = 1'b0;
        response_error = 1'b0;
        release_master(0);
        next_grant();
        expect_owner(1, "handoff to master 1");

        // 5. Requester 1 must not be preempted by requester 0.
        @(negedge clk);
        request_master(0, ADDR_WIDTH'(32'h3000), 'h12345678, 1'b0);
        next_grant();
        expect_owner(1, "no mid-cycle preemption");

        // 6. Active owner to pending owner transition
        for (int i = 1; i < N_MASTERS; i++) begin
            @(negedge clk);
            release_master(i);
            next_grant();
            if (i < N_MASTERS-1)
                expect_owner(0, $sformatf("higher priority pending after %0d", i));
            else
                expect_owner(0, "final remaining requester 0");
            if (i < N_MASTERS-1) begin
                // Remove request 0 so subsequent waiting requesters can progress.
                @(negedge clk);
                release_master(0);
                next_grant();
                expect_owner(i+1, $sformatf("next pending requester %0d", i+1));
                @(negedge clk);
                request_master(0, ADDR_WIDTH'(32'h3100 + i*16),
                               DATA_WIDTH'(32'hFACE_0000 + i), 1'b1);
                next_grant();
                expect_owner(i+1, "new high priority cannot preempt");
            end
        end
        @(negedge clk);
        release_master(0);
        next_grant();
        expect_owner(-1, "all released");

        // 7. CYC asserted without STB should maintain ownership
        @(negedge clk);
        request_master(N_MASTERS-1, 'h4000, 'h55AA55AA, 1'b0);
        req_stb[N_MASTERS-1] = 1'b0;
        next_grant();
        expect_owner(N_MASTERS-1, "CYC without STB");
        check_bit(slave_wb.STB, 1'b0, "CYC-only no strobe");
        @(negedge clk);
        req_stb[N_MASTERS-1] = 1'b1;
        response_enable = 1'b1;
        next_grant();
        expect_owner(N_MASTERS-1, "CYC-only resumes STB");
        @(negedge clk);
        response_enable = 1'b0;
        release_master(N_MASTERS-1);
        next_grant();
        expect_owner(-1, "final idle");

        $display("tb_mux: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("tb_mux: PASS (%0d checks)", checks);
        else $fatal(1, "tb_mux: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
