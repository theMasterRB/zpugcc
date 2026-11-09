module dummy_zpu #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter bit RUN_DEMO = 1'b0
) (
    input logic clk,
    input logic rst,
    bus_protocol_if.protocol protif
    // Real ZPU would have interface to take ISA from the system
    // This Dummy ZPU does not have ISA interface
);

// TODO Define where the stack is (ZPU Stack grows downward)
localparam int WORD_BYTES = DATA_WIDTH / 8;
localparam logic [ADDR_WIDTH-1:0] STACK_TOP = 32'h0002_FFFC;
localparam logic [ADDR_WIDTH-1:0] STACK_BOTTOM = 32'h0002_0000;

// These are probably the only (address) variable not on memory
logic [ADDR_WIDTH-1:0] sp;

// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
// Define tasks for basic operation
// =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
task automatic write(
    input logic [DATA_WIDTH-1:0] data,
    input logic [ADDR_WIDTH-1:0] address,
    input logic [(DATA_WIDTH/8)-1 : 0] strobe = '1
);
    int cycles = 0;

    // Assign the following before next Rising Clock Edge
    @(negedge clk); 

    protif.addr = address;
    protif.wdata = data;
    protif.strobe = strobe;
    protif.wen = 1'b1;
    protif.ren = 1'b0;

    // Loop while request_stall is still asserted
    // (Wait for downstream slave to complete task)
    do begin
        // Check stall at next rising edge
        // TODO Check if this is appropriate
        @(posedge clk);

        cycles++;
        if (cycles > 100) $fatal(1, "write timeout at %h", address);
    end while (protif.request_stall !== 1'b0);
    // Check for error
    if (protif.error)
    $fatal(1, "bus error at address %h", address);


    // Deassert enable after transaction is completed
    @(negedge clk); 
    protif.strobe = '0;
    protif.wen = 1'b0;
endtask

task automatic read(
    input logic [ADDR_WIDTH-1:0] address,
    output logic [DATA_WIDTH-1:0] data,
    input logic [(DATA_WIDTH/8)-1 : 0] strobe = '1
);
    int cycles = 0;

    // Assign the following before next Rising Clock Edge
    @(negedge clk); 

    protif.addr   = address;
    protif.strobe = strobe;
    protif.wen    = 1'b0;
    protif.ren    = 1'b1;

    // Loop while request_stall is still asserted
    // (Wait for downstream slave to complete task)
    do begin
        // Check stall at next rising edge
        // TODO Check if this is appropriate
        @(posedge clk);

        cycles++;
        if (cycles > 100) $fatal(1, "read timeout at %h", address);
    end while (protif.request_stall !== 1'b0);
    // Check for error
    if (protif.error)
    $fatal(1, "bus error at address %h", address);

    // Capture data
    data = protif.rdata;

    // Deassert enable after transaction is completed
    @(negedge clk); 
    protif.strobe = '0;
    protif.ren = 1'b0;
endtask

// =-=-=-=-=-=-=-=-=-=-=-=
//  Simple ZPU Operations
// =-=-=-=-=-=-=-=-=-=-=-=
// For demonstration purposes only

task automatic push(
    input logic [DATA_WIDTH-1:0] value
);
    if (sp < STACK_BOTTOM + WORD_BYTES) $fatal(1, "stack full!");
    
    sp = sp - WORD_BYTES;
    write(value, sp);
endtask

task automatic pop(
    output logic [DATA_WIDTH-1:0] value
);
    if (sp >= STACK_TOP) $fatal(1, "nothing in stack!");

    read(sp, value);
    sp = sp + WORD_BYTES;
endtask

task automatic IM(
    input logic [DATA_WIDTH-1:0] value
    // Real IM only accept 7 bits, but this is for demo
);
    push(value);
endtask

task automatic STORE();
    logic [DATA_WIDTH-1:0] tmp1, tmp2;

    if (sp > STACK_TOP - 2 * WORD_BYTES) $fatal(1, "STORE need at least two operands on stack!");
    
    // Pop the address and value
    pop(tmp2);
    pop(tmp1);
    write(tmp1, tmp2);
endtask

task automatic ADD();
    logic [DATA_WIDTH-1:0] tmp1, tmp2;

    if (sp > STACK_TOP - 2 * WORD_BYTES) $fatal(1, "ADD need at least two operands on stack!");
    
    // Pop the values
    pop(tmp2);
    pop(tmp1);
    push(tmp1 + tmp2);
endtask

// =-=-=-=-=-=-=-=-=-=
// Simple Instructions
// =-=-=-=-=-=-=-=-=-=

initial begin
    // Initialize
    sp = STACK_TOP;

    protif.addr   = '0;
    protif.wdata  = '0;
    protif.strobe = '0;
    protif.wen    = 1'b0;
    protif.ren    = 1'b0;

    wait (rst === 1'b0);

    if (RUN_DEMO) begin
       // Simple Add two numbers example
       IM(2);
       IM(2);
       ADD();

       // Output value at GPIO1 : (For example) 0x00000100
       IM(32'h0000_0100);
       STORE();
    end
end
endmodule
