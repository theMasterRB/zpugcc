// sram controller that talks wishbone
module wb_sram_controller #(
    parameter int          ADDR_WIDTH = 18,
    parameter int          DATA_WIDTH = 16,
    parameter logic [31:0] BASE_ADDR  = 32'h0002_0000,
    parameter int          NWORDS     = 4096
) (
    // wishbone side
    wishbone_if.slave wbif,

    // sram chip pins
    output logic n_OE [1:0],
    output logic n_CE [1:0],
    output logic n_WE [1:0],
    output logic n_LB [1:0],
    output logic n_UB [1:0],
    output logic iopad_n_oe,
    output logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] wdata,
    input  logic [DATA_WIDTH-1:0] rdata_in
);

    // states
    typedef enum logic [3:0] {
        IDLE,
        READ_DATA_0,
        READ_WAIT,
        READ_DATA_1,
        WRITE_DATA_0,
        WRITE_WAIT,
        WRITE_DATA_1,
        FINISH,
        ERROR
    } state_t;

    state_t state, state_next;

    // signals
    logic        request;
    logic [31:0] offset;
    logic        in_range;
    logic [2:0]  count;
    logic        done;

    // saved stuff
    logic [ADDR_WIDTH-1:0] addr_q;
    logic [31:0]           wdat_q;
    logic [3:0]            sel_q;
    logic [15:0]           rdata0_q;
    logic [15:0]           rdata1_q;
    logic                  aborted;
    logic [31:0]           rdata_word;

    // master wants something
    assign request  = wbif.CYC && wbif.STB;
    // address inside the sram
    assign offset   = wbif.ADR - BASE_ADDR;
    // is the address ok
    assign in_range = (wbif.ADR >= BASE_ADDR) && (offset < NWORDS * 4);
    // chip is done after 4 cycles
    assign done     = (count == 3'd3);

    // state register
    always_ff @(posedge wbif.SCLK, posedge wbif.SRESET) begin : STATE_REG
        if (wbif.SRESET) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end : STATE_REG

    // next state logic
    always_comb begin : NEXT_STATE
        state_next = state;
        case (state)
            // wait for a request
            IDLE: begin
                if (request && !in_range) begin
                    state_next = ERROR;
                end else if (request && wbif.WE) begin
                    state_next = WRITE_DATA_0;
                end else if (request) begin
                    state_next = READ_DATA_0;
                end
            end

            // read chip 0, wait, read chip 1
            READ_DATA_0:  if (done) state_next = READ_WAIT;
            READ_WAIT:              state_next = READ_DATA_1;
            READ_DATA_1:  if (done) state_next = FINISH;

            // write chip 0, wait, write chip 1
            WRITE_DATA_0: if (done) state_next = WRITE_WAIT;
            WRITE_WAIT:             state_next = WRITE_DATA_1;
            WRITE_DATA_1: if (done) state_next = FINISH;

            // done, go back to idle
            FINISH: state_next = IDLE;
            ERROR:  state_next = IDLE;

            default: state_next = IDLE;
        endcase
    end : NEXT_STATE

    // counter
    always_ff @(posedge wbif.SCLK, posedge wbif.SRESET) begin : COUNTER
        if (wbif.SRESET) begin
            count <= '0;
        end else if (state == READ_DATA_0  || state == READ_DATA_1 ||
                     state == WRITE_DATA_0 || state == WRITE_DATA_1) begin
            count <= count + 1'b1;
        end else begin
            count <= '0;
        end
    end : COUNTER

    // save the request and the read data
    always_ff @(posedge wbif.SCLK, posedge wbif.SRESET) begin : REQUEST_REG
        if (wbif.SRESET) begin
            addr_q   <= '0;
            wdat_q   <= '0;
            sel_q    <= '0;
            rdata0_q <= '0;
            rdata1_q <= '0;
            aborted  <= 1'b0;
        end else begin
            // new request
            if (state == IDLE && request) begin
                addr_q  <= offset[ADDR_WIDTH-1:0];
                wdat_q  <= wbif.WDAT;
                sel_q   <= wbif.SEL;
                aborted <= 1'b0;
            // master gave up
            end else if (state != IDLE && !request) begin
                aborted <= 1'b1;
            end

            // save chip data
            if (state == READ_DATA_0 && done) rdata0_q <= rdata_in;
            if (state == READ_DATA_1 && done) rdata1_q <= rdata_in;
        end
    end : REQUEST_REG

    // drive the chip pins
    always_comb begin : TO_SRAM
        // chip enable
        n_CE[0] = !(state == READ_DATA_0 || state == WRITE_DATA_0);
        n_CE[1] = !(state == READ_DATA_1 || state == WRITE_DATA_1);

        // output enable (read)
        n_OE[0] = !(state == READ_DATA_0);
        n_OE[1] = !(state == READ_DATA_1);

        // write enable
        n_WE[0] = !(state == WRITE_DATA_0);
        n_WE[1] = !(state == WRITE_DATA_1);

        // byte enables from SEL
        n_LB[0] = !((state == READ_DATA_0 || state == WRITE_DATA_0) && sel_q[3]);
        n_UB[0] = !((state == READ_DATA_0 || state == WRITE_DATA_0) && sel_q[2]);
        n_LB[1] = !((state == READ_DATA_1 || state == WRITE_DATA_1) && sel_q[1]);
        n_UB[1] = !((state == READ_DATA_1 || state == WRITE_DATA_1) && sel_q[0]);

        // we drive the data pins when writing
        iopad_n_oe = !(state == WRITE_DATA_0 || state == WRITE_WAIT || state == WRITE_DATA_1);

        // address and write data
        addr  = addr_q;
        wdata = '0;
        if (state == WRITE_DATA_0) wdata = {wdat_q[23:16], wdat_q[31:24]};
        if (state == WRITE_DATA_1) wdata = {wdat_q[7:0],   wdat_q[15:8]};
    end : TO_SRAM

    // ack when done
    assign wbif.ACK  = (state == FINISH) && request && !aborted;
    // err when address is bad
    assign wbif.ERR  = (state == ERROR)  && request && !aborted;

    // put the read data back together
    assign rdata_word = {rdata0_q[7:0], rdata0_q[15:8], rdata1_q[7:0], rdata1_q[15:8]};
    // only send selected bytes
    assign wbif.RDAT  = wbif.ACK ? (rdata_word & {{8{sel_q[3]}}, {8{sel_q[2]}}, {8{sel_q[1]}}, {8{sel_q[0]}}}) : '0;

endmodule
