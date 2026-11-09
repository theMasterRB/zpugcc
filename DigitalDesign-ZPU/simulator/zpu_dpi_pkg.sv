package zpu_dpi_pkg;

  import "DPI-C" function void zpu_dpi_reset();
  import "DPI-C" function void zpu_dpi_set_trace(input int on);
  import "DPI-C" function void zpu_dpi_write_byte(input int unsigned addr, input byte unsigned value);
  import "DPI-C" function int zpu_dpi_step(); // 1 = running, 0 = halted, -1 = error
  import "DPI-C" function int unsigned zpu_dpi_get_pc();
  import "DPI-C" function int unsigned zpu_dpi_get_sp();
  import "DPI-C" function int unsigned zpu_dpi_get_top();
  import "DPI-C" function int zpu_dpi_is_halted();
  import "DPI-C" function int zpu_dpi_has_error();
  import "DPI-C" function int unsigned zpu_dpi_read32(input int unsigned addr);

  // opcodes so the testbench doesn't have random numbers everywhere
  localparam byte unsigned OP_BREAKPOINT = 8'd0;
  localparam byte unsigned OP_ADD = 8'd5;
  localparam byte unsigned OP_NOP = 8'd11;

  // builds an IM x instruction, x can be -64 to 127
  function automatic byte unsigned op_im(input int x);
    return byte'(8'h80 | (x & 8'h7F));
  endfunction

endpackage
