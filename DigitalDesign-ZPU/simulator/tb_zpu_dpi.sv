// quick test that sv can actually run the c++ model through DPI
// the rtl isn't hooked up yet, this only checks the model side
`timescale 1ns/1ps

module tb_zpu_dpi;
  import zpu_dpi_pkg::*;

  // same 3 + 4 program as zpusim_main.cpp
  byte unsigned program_bytes[] = '{
    op_im(3),
    OP_NOP, // breaks the IM chain so the next IM pushes a new value
    op_im(4),
    OP_ADD,
    OP_BREAKPOINT,
  };

  int status;
  int steps;

  initial begin
    zpu_dpi_reset();
    zpu_dpi_set_trace(1);

    foreach (program_bytes[i])
      zpu_dpi_write_byte(i, program_bytes[i]);

    // step until it halts, errors, or we give up after 1000 instructions
    steps = 0;
    status = 1;
    while (status == 1 && steps < 1000) begin
      status = zpu_dpi_step();
      steps++;
      $display("[SV] step %0d pc=%0d sp=%0d top=%0d", steps, zpu_dpi_get_pc(), zpu_dpi_get_sp(), $signed(zpu_dpi_get_top()));
    end

    if (status == -1)
      $error("model hit an error");
    else if (status == 1)
      $error("model never halted (ran 1000 steps)");
    else if (zpu_dpi_get_top() !== 32'd7)
      $error("expected 7 on top of the stack, got %0d", zpu_dpi_get_top());
    else
      $display("PASS: 3 + 4 = %0d in %0d steps", zpu_dpi_get_top(), steps);

    // TODO: put the zpu rtl in here, load the same program into its memory,
    // and after every instruction compare its pc/sp/top with the model's

    $finish;
  end
endmodule
