module wb_mux #(
   parameter int NMASTERS = 2,
   parameter int ADDR_WIDTH = 32,
   parameter int DATA_WIDTH = 32
)(
  input logic HCLK, HRESET,
  wishbone_if.master m_out,
  wishbone_if.slave m_in [NMASTERS-1:0]
);

   //mux acts as a slave to the master
   //and acts as a master to the slave

   //arbsel is one-hot, with number bit corresponding
   //to which master is selected
   //master sel is the index of the selected master
   logic [NMASTERS-1:0] arb_sel, n_arb_sel;
   logic [$clog2(NMASTERS)-1:0] master_sel, n_master_sel;

   logic [NMASTERS-1:0] cyc_in;
   logic [NMASTERS-1:0] [ADDR_WIDTH-1:0] adr_in;
   logic [NMASTERS-1:0] [DATA_WIDTH-1:0] wdat_in;
   logic [NMASTERS-1:0] we_in;
   logic [NMASTERS-1:0] [(DATA_WIDTH/8)-1:0] sel_in;
   logic [NMASTERS-1:0] stb_in;

   for(genvar g = 0; g < NMASTERS; g++) begin
      assign cyc_in[g] = m_in[g].CYC;
      assign adr_in[g] = m_in[g].ADR;
      assign wdat_in[g] = m_in[g].WDAT;
      assign we_in[g] = m_in[g].WE;
      assign sel_in[g] = m_in[g].SEL;
      assign stb_in[g] = m_in[g].STB;
   end

   always_ff @(posedge HCLK, negedge HRESET) begin
     if(!HRESET) begin
        arb_sel <= '0;
        master_sel <= '0;
     end else begin
        arb_sel <= n_arb_sel;
        master_sel <= n_master_sel;
     end
   end

   always_comb begin: arbitration
     if(cyc_in[master_sel] && arb_sel[master_sel]) begin
        n_master_sel = master_sel;
        n_arb_sel = arb_sel;
     end else begin
        n_master_sel = '0;
        n_arb_sel = '0;
        for(int i = NMASTERS-1; i >=0; i--) begin
           if (cyc_in[i]) begin
              n_master_sel = i;
              n_arb_sel = 1'b1 << n_master_sel;
           end
        end
     end
   end

   //routing correct master sigals to slave
   always_comb begin
      //default the signals
      m_out.ADR = 0;
      m_out.WDAT = '0;
      m_out.WE = 0;
      m_out.SEL = '0;
      m_out.CYC = 0;
      m_out.STB = 0;

      for(int i = 0; i < NMASTERS; i++) begin
        if (arb_sel[i]) begin
           m_out.ADR = adr_in[i];
           m_out.WDAT = wdat_in[i];
           m_out.WE = we_in[i];
           m_out.SEL = sel_in[i];
           m_out.CYC = cyc_in[i];
           m_out.STB = stb_in[i];
        end
      end
   end

   //routing slave signals to correct master
   for (genvar g = 0; g < NMASTERS; g++) begin
      always_comb begin
         if (arb_sel[g]) begin
            m_in[g].ACK  = m_out.ACK;
            m_in[g].ERR  = m_out.ERR;
            m_in[g].RDAT = m_out.RDAT;
        end else begin
            m_in[g].ACK  = 1'b0;
            m_in[g].ERR  = 1'b0;
            m_in[g].RDAT = '0;
        end
      end
   end


endmodule
