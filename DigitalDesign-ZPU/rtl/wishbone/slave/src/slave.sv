
module slave #(
    parameter int DATA_WIDTH = 32
) (
    wishbone_if.slave wbif,
    bus_protocol_if.protocol busif
);

    typedef enum logic [1:0] {
        IDLE,
        ACTIVE,
        ACKNOWLEDGE
    } state_t;

    state_t state, state_next;

    logic                  request;  // master is talking to us this cycle
    logic [DATA_WIDTH-1:0] rdata_q;  // read data, saved on the cycle the peripheral finishes
    logic                  error_q;  // error, saved the same way

    assign request = wbif.CYC && wbif.STB;


    /*
    *   FSM
    */
    always_ff @(posedge wbif.SCLK, posedge wbif.SRESET) begin : STATE_REG
        if (wbif.SRESET) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end : STATE_REG

    always_comb begin : NEXT_STATE
        state_next = state;
        case (state)
            IDLE: begin
                if (request) begin
                    state_next = ACTIVE;
                end
            end

            ACTIVE: begin
                if (!request) begin
                    state_next = IDLE;
                end else if (!busif.request_stall) begin
                    state_next = ACKNOWLEDGE;  // peripheral finished this cycle
                end
            end

            ACKNOWLEDGE: begin
                if (!request) begin
                    state_next = IDLE;
                end
            end

            default: state_next = IDLE;
        endcase
    end : NEXT_STATE


    always_ff @(posedge wbif.SCLK, posedge wbif.SRESET) begin : RESPONSE_REG
        if (wbif.SRESET) begin
            rdata_q <= '0;
            error_q <= 1'b0;
        end else if (state == ACTIVE && request && !busif.request_stall) begin
            rdata_q <= busif.rdata;
            error_q <= busif.error;
        end
    end : RESPONSE_REG


    /*
    *   To the peripheral: only ask while ACTIVE, drive zeros otherwise.
    */
    always_comb begin : TO_PERIPHERAL
        busif.wen    = 1'b0;
        busif.ren    = 1'b0;
        busif.addr   = '0;
        busif.wdata  = '0;
        busif.strobe = '0;

        if (state == ACTIVE && request) begin
            busif.wen    =  wbif.WE;
            busif.ren    = !wbif.WE;
            busif.addr   = wbif.ADR;
            busif.wdata  = wbif.WDAT;
            busif.strobe = wbif.SEL;   // SEL is the byte mask, NOT STB
        end
    end : TO_PERIPHERAL

    // Hint signals: not used
    assign busif.is_burst        = 1'b0;
    assign busif.burst_type      = '0;
    assign busif.burst_length    = '0;
    assign busif.secure_transfer = 1'b0;


    /*
    *   Back to the master. ACK/ERR only while the master is still asking.
    */
    assign wbif.ACK  = (state == ACKNOWLEDGE) && request && !error_q;
    assign wbif.ERR  = (state == ACKNOWLEDGE) && request &&  error_q;
    assign wbif.RDAT = rdata_q;

endmodule
