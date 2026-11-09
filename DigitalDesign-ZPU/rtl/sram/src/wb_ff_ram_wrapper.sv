module wb_ff_ram_wrapper #(
   parameter int NBYTES = 4096,
   parameter int ROM = 0
)(
   wishbone_if.slave wbif
  );

   bus_protocol_if busif();

   slave WB_SLAVE (
      .wbif(wbif),
      .busif(busif)
   );

   ff_ram #(
      .NBYTES(NBYTES),
      .ROM(ROM)
   ) RAM (
      .CLK(wbif.SCLK),
      .busif(busif)
   );

endmodule
