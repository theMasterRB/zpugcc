/*
 *  Maxwell Michalec
 *
 *  05/31/2023
 *
 *  Simulation: parameterizable scratchpad flip-flop RAM 
 *  Synthesis: wrapper for Altera RAM module
 *  SRAM: wrapper for the Synopsys SRAM module
*/

module ff_ram #(
    parameter NBYTES = 4096,
    parameter int ROM = 0
) (
    input CLK,
    bus_protocol_if.peripheral_vital busif
);

`ifdef SRAM
    logic [31:0] word_addr;
    assign word_addr = busif.addr >> 2;

    // makes the later case easier to read
    localparam int K = 1024;

    // we can only read data the *next* cycle after the address is ready
    // make sure we tell the bus to hang on a cyle
    logic stall;
    assign busif.request_stall = busif.ren && !stall;
    always_ff @(posedge CLK) begin
        stall <= busif.ren;
    end

    // to avoid typing this all out repeatedly
    `define SRAM_PORTS(num, width) \
        .Q(busif.rdata[(num*8)+:8]), \
        .ADR(word_addr[(width):0]), \
        .D(busif.wdata[(num*8)+:8]), \
        .WE(busif.strobe[(num)] && busif.wen), \
        .OE(busif.ren), \
        .ME(busif.wen | busif.ren), \
        .CLK(CLK)

    // makes 4x SRAM modules for each (due to the need to obey the write strobe)
    // and to obey it each 1/4 SRAM needs to have its own WriteEnable pin
    generate
        genvar i;
        for (i = 0; i < 4; ++i) begin
            case (NBYTES)
                8*K:    sram_2k sram(`SRAM_PORTS(i, 10));
                12*K:   sram_3k sram(`SRAM_PORTS(i, 11));
                16*K:   sram_4k sram(`SRAM_PORTS(i, 11));
                20*K:   sram_5k sram(`SRAM_PORTS(i, 12));
                32*K:   sram_8k sram(`SRAM_PORTS(i, 12));
                64*K:   sram_16k sram(`SRAM_PORTS(i, 13));

                //if the value is wrong, 8k sram
                default: begin
                    sram_2k sram(`SRAM_PORTS(i, 10));
                    $error("SRAM value not recognized. Defaulting to 8k");
                end
            endcase
        end
    endgenerate
    
`elsif NOIP
    localparam int NWORDS = NBYTES / 4;

    reg   [31:0] data [NWORDS-1:0];
    logic [31:0] word_addr;

    assign word_addr = busif.addr >> 2;

    always @(posedge CLK) begin
        if (busif.wen) begin
            data[word_addr][0+:8]  <= busif.strobe[3] ? busif.wdata[24+:8] : data[word_addr][0+:8];
            data[word_addr][8+:8]  <= busif.strobe[2] ? busif.wdata[16+:8] : data[word_addr][8+:8];
            data[word_addr][16+:8] <= busif.strobe[1] ? busif.wdata[8+:8]  : data[word_addr][16+:8];
            data[word_addr][24+:8] <= busif.strobe[0] ? busif.wdata[0+:8]  : data[word_addr][24+:8];
        end
    end

    assign busif.rdata = { data[word_addr][0+:8],
                           data[word_addr][8+:8],
                           data[word_addr][16+:8],
                           data[word_addr][24+:8] };

    assign busif.error = 1'b0;
    assign busif.request_stall = 1'b0;

`elsif SYNTHESIS
    int LATENCY = 0;
    logic [31:0] word_addr;
	logic [31:0] latency_count;
	logic latency_done;
	
	assign word_addr = busif.addr >> 2;
	
	// 64KB RAM module
	ram BLOCK (
		.address(word_addr[13:0]),
		.byteena(busif.strobe),
		.clock(CLK),
		.data(busif.wdata),
		.rden(busif.ren),
		.wren(busif.wen),
		.q(busif.rdata)
	);
	
	always @(posedge CLK) begin
		if ((latency_count < LATENCY) && (busif.ren || busif.wen)) begin
            latency_count <= latency_count + 1;
        end else begin
            latency_count <= '0;
        end
	end

	assign busif.error = 1'b0;
    assign latency_done = (latency_count == LATENCY);
    assign busif.request_stall = !latency_done && (busif.ren || busif.wen);
`else

    /* sim only */
    string INFILE = "meminit.bin";
    string OUTFILE = "memsim.hex";
    int LATENCY = 0;
    logic [31:0] latency_count;
    logic latency_done;
    int fd, temp;
    /* -------- */

    localparam int NWORDS = NBYTES / 4;

    reg   [31:0] data [NWORDS-1:0];
    logic [31:0] word_addr;

    assign word_addr = busif.addr >> 2;

    // if ROM, error on write
    if (ROM) begin
        assign busif.error = busif.wen;
    end else begin
	assign busif.error = 1'b0;
    end
    
    always @(posedge CLK) begin
        if (busif.wen && !ROM) begin
            data[word_addr][0+:8]  <= busif.strobe[3] ? busif.wdata[24+:8] : data[word_addr][0+:8];
            data[word_addr][8+:8]  <= busif.strobe[2] ? busif.wdata[16+:8] : data[word_addr][8+:8];
            data[word_addr][16+:8] <= busif.strobe[1] ? busif.wdata[8+:8]  : data[word_addr][16+:8];
            data[word_addr][24+:8] <= busif.strobe[0] ? busif.wdata[0+:8]  : data[word_addr][24+:8];
        end

        // increment latency var	
	if ((latency_count < LATENCY) && ( busif.ren || (!ROM && busif.wen) )) begin
            latency_count <= latency_count + 1;
        end else begin
            latency_count <= '0;
        end
    end

    assign busif.rdata = { data[word_addr][0+:8],
                           data[word_addr][8+:8],
                           data[word_addr][16+:8],
                           data[word_addr][24+:8] };

    // latency status; stall read if latency is not done counting
    assign latency_done = (latency_count == LATENCY);
    assign busif.request_stall = !latency_done && (busif.ren || busif.wen);
    
    initial begin
        if($test$plusargs("latency")) begin
            $value$plusargs("latency=%d", LATENCY);
	end

        if($test$plusargs("firmware") && ROM) begin
            $value$plusargs("firmware=%s", INFILE);
    	end else if($test$plusargs("meminit") && !ROM) begin
	    $value$plusargs("meminit=%s", INFILE);	
	end
	OUTFILE = { INFILE.substr(0, INFILE.len() - 5), ".hex" };

        data = '{default: '0};
        fd = $fopen(INFILE, "rb");
        if (!fd) begin
            $display("Warning: Could not open %s!\n", INFILE);
        end else begin
            temp = $fread(data, fd);
            $display("Read %d bytes from %s\n", temp, INFILE); 
            $fclose(fd);
        end
    end

    final begin
        fd = $fopen(OUTFILE, "wb");
        if(!fd) begin
            $display("Warning: Could not open %s!\n", OUTFILE);
        end else begin
            for(int i = 0; i < NWORDS; i++) begin
                $fwrite(fd, "%h: %h\n", i, data[i]);
            end
            $display("Wrote to %s\n", OUTFILE);
            $fclose(fd);
        end
    end
    /* -------- */

`endif
endmodule : ff_ram
