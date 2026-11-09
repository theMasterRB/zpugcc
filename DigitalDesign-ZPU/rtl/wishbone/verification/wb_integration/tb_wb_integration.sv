module tb_wb_integration #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,

    // Current integration has one dummy_zpu/master and three dummy_peripherals.
    parameter int NMASTERS = 1,
    parameter int NSLAVES = 3
);
    localparam int WORD_BYTES = DATA_WIDTH / 8;
    localparam int SLAVE_NBYTES = 256;
    localparam int MEM_DEPTH = SLAVE_NBYTES / WORD_BYTES;

    // Addresses represent half-open ranges:
    // e.g., [0x100,0x200)
    typedef logic [ADDR_WIDTH-1:0] wb_map_t [NSLAVES+1];
    function automatic wb_map_t make_map();
        wb_map_t result;
        for (int i = 0; i <= NSLAVES; i++)
            result[i] = ADDR_WIDTH'(32'h0000_0100 + i * SLAVE_NBYTES);
        return result;
    endfunction
    localparam wb_map_t TEST_WB_MAP = make_map();

    logic clk = 1'b0;
    logic rst = 1'b1; // Active-high for wrappers and dummy_zpu
    int latency = 0;
    int errors = 0;
    int checks = 0;
    logic [DATA_WIDTH-1:0] read_data;

    always #5 clk = ~clk;

    bus_protocol_if master_protifs [0:NMASTERS-1] ();
    bus_protocol_if slave_protifs [0:NSLAVES-1] ();
    wishbone_if master_wbs [0:NMASTERS-1] (.SCLK(clk), .SRESET(rst));
    wishbone_if slave_wbs [0:NSLAVES-1] (.SCLK(clk), .SRESET(rst));
    wishbone_if mux_to_decoder (.SCLK(clk), .SRESET(rst));

    dummy_zpu u_dummy_zpu (
        .clk(clk),
        .rst(rst),
        .protif(master_protifs[0])
    );

    for (genvar i = 0; i < NMASTERS; i++) begin : GEN_MASTERS
        master u_master (
            .ms_if(master_wbs[i]),
            .bc_if(master_protifs[i])
        );
    end

    wb_mux #(
        .NMASTERS(NMASTERS)
    ) u_mux (
        .HCLK(clk),
        // wb_mux uses active-LOW HRESET
        .HRESET(!rst),
        .m_in(master_wbs),
        .m_out(mux_to_decoder)
    );

    address_decoder #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .N_SLAVES(NSLAVES),
        .WB_MAP(TEST_WB_MAP)
    ) u_decoder (
        .master(mux_to_decoder),
        .slaves(slave_wbs)
    );

    for (genvar i = 0; i < NSLAVES; i++) begin : GEN_SLAVES
        slave u_slave (
            .wbif(slave_wbs[i]),
            .busif(slave_protifs[i])
        );

        dummy_peripheral #(
            .MEM_DEPTH(MEM_DEPTH),
            .BYTE_OFFSET(TEST_WB_MAP[i])
        ) u_memory (
            .clk(clk),
            .rst_n(!rst),
            .s(slave_protifs[i]),
            .latency(latency)
        );
    end

    task automatic check_data(
        input logic [DATA_WIDTH-1:0] got,
        input logic [DATA_WIDTH-1:0] expected,
        input string description
    );
        checks++;
        if (got !== expected) begin
            errors++;
            $display("FAIL @%0t: %s expected %08h, got %08h",
                     $time, description, expected, got);
        end
    endtask

    task automatic write_read(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] value,
        input string description
    );
        u_dummy_zpu.write(value, address);
        u_dummy_zpu.read(address, read_data);
        check_data(read_data, value, description);
    endtask

    // timeout watchdog.
    initial begin : WATCHDOG
        #100000;
        $fatal(1, "tb_master: global timeout");
    end

    initial begin : TEST_SEQUENCE
        logic [DATA_WIDTH-1:0] expected [NSLAVES];

        rst = 1'b1;
        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        $display("TEST 1: normal write/read");
        write_read(TEST_WB_MAP[0], 32'h1234_5678, "slave 0 first word");

        $display("TEST 2: write to each peripheral");
        for (int i = 0; i < NSLAVES; i++) begin
            expected[i] = DATA_WIDTH'(32'hC0DE_0000 + i);
            u_dummy_zpu.write(expected[i], TEST_WB_MAP[i]);
        end
        for (int i = 0; i < NSLAVES; i++) begin
            u_dummy_zpu.read(TEST_WB_MAP[i], read_data);
            check_data(read_data, expected[i],
                       $sformatf("slave %0d isolated first word", i));
        end

        $display("TEST 3: last-word address boundary check");
        for (int i = 0; i < NSLAVES; i++) begin
            write_read(TEST_WB_MAP[i+1] - ADDR_WIDTH'(WORD_BYTES),
                       DATA_WIDTH'(32'hABCD_0000 + i),
                       $sformatf("slave %0d last word", i));
        end

        $display("TEST 4: first-word address boundary check");
        for (int i = 0; i < NSLAVES; i++) begin
            u_dummy_zpu.read(TEST_WB_MAP[i], read_data);
            check_data(read_data, expected[i],
                       $sformatf("slave %0d first word preserved", i));
        end

        $display("TEST 5: stalled transactions");
        latency = 2;
        for (int i = 0; i < NSLAVES; i++) begin
            write_read(TEST_WB_MAP[i] + ADDR_WIDTH'(WORD_BYTES),
                       DATA_WIDTH'(32'hDEAD_0000 + i),
                       $sformatf("slave %0d stalled write/read", i));
        end
        latency = 0;

        $display("TEST 6: transtion back to no stall");
        write_read(TEST_WB_MAP[0] + ADDR_WIDTH'(2*WORD_BYTES),
                   32'hFEED_BEEF, "zero-latency recovery");

        if (errors == 0) begin
            $display("tb_wb_integration: PASS (%0d checks)", checks);
        end else begin
            $display("tb_wb_integration: FAIL (%0d errors, %0d checks)",
                     errors, checks);
            $fatal(1, "Integration regression failed");
        end
        $finish;
    end
endmodule
