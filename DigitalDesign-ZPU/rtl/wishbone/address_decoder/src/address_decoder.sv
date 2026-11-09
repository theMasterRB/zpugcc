module address_decoder #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int N_SLAVES = 18,
    parameter logic [ADDR_WIDTH-1:0] WB_MAP[N_SLAVES + 1] = '{default: '0} // Extra member for END address
) (
    // Is slave to master, is master to slaves
    wishbone_if.slave master,
    wishbone_if.master slaves[N_SLAVES]
);
    logic [N_SLAVES-1:0] addr_match_arr;
    logic [N_SLAVES-1:0] ERR_arr;
    logic [N_SLAVES-1:0] ACK_arr;
    logic [DATA_WIDTH-1:0] RDAT_arr [N_SLAVES];

    // Check whether address belongs to slave_idx
    // WB_MAP must be in ascending order
    function automatic logic addr_match(
        logic [ADDR_WIDTH-1:0] bus_addr, 
        int slave_idx
    );
        return (bus_addr >= WB_MAP[slave_idx])
            && (bus_addr < WB_MAP[(slave_idx + 1)]);
    endfunction

    // ADDRESS DECODER
    // Generate an addr_match_ar
    // addr_match_arr[i] = 1 where master.ADR is in slave i
    // addr_match_arr[i] = 0 otherwise
    genvar i;

    generate
        for(i = 0; i < N_SLAVES; i++) begin: gen_addr_match
            assign addr_match_arr[i] = addr_match(master.ADR, i);
        end
    endgenerate

    // ASSIGN MASTER SIGNALS TO EACH PERIPHERAL
    generate
        for (i = 0; i < N_SLAVES; i++) begin : pass_request
            assign slaves[i].ADR = master.ADR;
            assign slaves[i].WDAT = master.WDAT;
            assign slaves[i].WE = master.WE;
            assign slaves[i].SEL = master.SEL;
            // CYC and STB are only high if current slave is addressed
            assign slaves[i].CYC = master.CYC && addr_match_arr[i];
            assign slaves[i].STB = master.STB && addr_match_arr[i];
        end
    endgenerate

    // ASSISN SLAVE SIGNALS TO ARRAYS
    generate
        for (i = 0; i < N_SLAVES; i++) begin : gen_response_arr
            assign RDAT_arr[i]  = slaves[i].RDAT;
            assign ACK_arr[i] = slaves[i].ACK;
            assign ERR_arr[i]  = slaves[i].ERR;
        end
    endgenerate

    // ASSIGN ADDRESSED SLAVE SIGNALS BACK TO MASTER
    always_comb begin : pass_response
        master.RDAT = '0;
        master.ACK = 1'b0;
        // Handle undefined address
        master.ERR = master.CYC && master.STB && !(|addr_match_arr);
        for (int i = 0; i < N_SLAVES; i++) begin
            if (addr_match_arr[i]) begin
                master.RDAT  = RDAT_arr[i];
                master.ACK  = ACK_arr[i];
                master.ERR  = ERR_arr[i];
            end
        end
    end
endmodule