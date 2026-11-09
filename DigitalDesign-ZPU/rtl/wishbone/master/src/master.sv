module master (
    wishbone_if.master ms_if,
    bus_protocol_if.peripheral_vital bc_if
);

    typedef enum logic {
        IDLE,
        TRANSFER
    } master_state_t;

    master_state_t state, next_state;

    logic request;
    logic response;

    assign request  = bc_if.ren || bc_if.wen;
    assign response = ms_if.ACK || ms_if.ERR;

    always_ff @(posedge ms_if.SCLK or posedge ms_if.SRESET) begin
        if (ms_if.SRESET)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (request)
                    next_state = TRANSFER;
            end

            TRANSFER: begin
                if (response || !request)
                    next_state = IDLE;
            end

            default:
                next_state = IDLE;
        endcase
    end

    // Wishbone request
    always_comb begin
        ms_if.CYC  = (state == TRANSFER);
        ms_if.STB  = (state == TRANSFER);

        ms_if.ADR  = bc_if.addr;
        ms_if.WDAT = bc_if.wdata;
        ms_if.WE   = bc_if.wen;
        ms_if.SEL  = bc_if.strobe;
    end

    // Response to requester
    always_comb begin
        bc_if.rdata = ms_if.RDAT;
        bc_if.error = (state == TRANSFER) && ms_if.ERR;

        // A request completes only when ACK or ERR arrives.
        bc_if.request_stall =
            request && !((state == TRANSFER) && response);
    end

endmodule