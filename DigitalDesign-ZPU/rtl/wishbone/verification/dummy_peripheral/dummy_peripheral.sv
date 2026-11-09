
module dummy_peripheral #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter MEM_DEPTH   = 256, 
    parameter BYTE_OFFSET = 2
)(
    input logic clk,
    input logic rst_n,
    bus_protocol_if.peripheral_vital s,

    input int latency // ONLY FOR TESTBENCH PURPOSE
);
    // Number of bytes per word
    localparam BYTE_SEL_WIDTH = DATA_WIDTH / 8;
    localparam int WORD_BYTES = DATA_WIDTH / 8;
    localparam int INDEX_WIDTH = $clog2(MEM_DEPTH);

    // Internal Memory Array
    logic [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];
    logic [INDEX_WIDTH-1:0] mem_addr;
    logic [ADDR_WIDTH-1:0] local_addr;
    logic addr_valid;

    logic request;
    int unsigned wait_count;

    // Address translation: extract the word index using explicit parameters
    assign local_addr = s.addr - BYTE_OFFSET;
    assign mem_addr = INDEX_WIDTH'(local_addr / WORD_BYTES);

    // Verify that the requested address is within bounds
    assign addr_valid = (s.addr >= BYTE_OFFSET) && (local_addr < ADDR_WIDTH'(MEM_DEPTH * WORD_BYTES));

    assign request = s.ren || s.wen;

    // Assign error and rdata - Comb
    assign s.error = !addr_valid && request;
    assign s.rdata = (s.ren && addr_valid) ? memory[mem_addr] : '0;

    // latency N, request stall for N cycles (for verification)
    assign s.request_stall = request && (wait_count < latency);

    // Delay counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wait_count <= 0;
        end else if (!request) begin
            wait_count <= 0;
        end else if (wait_count < latency) begin
            wait_count <= wait_count + 1;
        end
    end

    // Write - Synced
    always_ff @(posedge clk, negedge rst_n) begin
        // Write only when stall is going off
        if (addr_valid && !s.request_stall) begin
            // Check if a valid transaction is active (ren or wen)
            if (s.wen) begin
                // Write Operation: supports partial-word writes using byte-select strobe
                for (int i = 0; i < BYTE_SEL_WIDTH; i++) begin
                    if (s.strobe[i]) begin
                        memory[mem_addr][i*8 +: 8] <= s.wdata[i*8 +: 8];
                    end
                end
            end
        end
    end

endmodule
