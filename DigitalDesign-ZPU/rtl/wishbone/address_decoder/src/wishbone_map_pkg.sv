// NOTE : 
// This memory map is referenced from the original AFTx07 map
// Some changes will be needed for compatibility with Wishbonepackage wishbone_map_pkg;

package wishbone_map_pkg;

    localparam int WB_ADDR_WIDTH = 32;
    localparam int WB_N_SLAVES = 18;

    localparam int GPIO0_ID          = 0;
    localparam int GPIO1_ID          = 1;
    localparam int GPIO2_ID          = 2;
    localparam int GPIO3_ID          = 3;
    localparam int ROM_ID            = 4;
    localparam int PWM_ID            = 5;
    localparam int TIMER_ID          = 6;
    localparam int SPI_ID            = 7;
    localparam int DIGITAL_IO_MUX_ID = 8;
    localparam int GPIO_BOOT_ID      = 9;
    localparam int MEMORY_ID         = 10;
    localparam int SRAM_ID           = 11;
    localparam int APB_BRIDGE_ID     = 12;
    localparam int DMA_ID            = 13;
    localparam int UART_ID           = 14;
    localparam int CLINT_ID          = 15;
    localparam int PLIC_ID           = 16;
    localparam int PRINTER_ID        = 17;

    localparam logic [WB_ADDR_WIDTH-1:0] WB_MAP [WB_N_SLAVES+1] = 
    '{
        32'h0000_0000, // GPIO0
        32'h0000_0100, // GPIO1
        32'h0000_0200, // GPIO2
        32'h0000_0300, // GPIO3
        32'h0000_0400, // ROM
        32'h0000_1000, // PWM
        32'h0000_2000, // TIMER
        32'h0000_4000, // SPI
        32'h0000_5000, // DIGITAL_IO_MUX
        32'h0000_6000, // GPIO_BOOT
        32'h0000_8400, // MEMORY
        32'h0002_0000, // SRAM
        32'h8000_0000, // APB Bridge (unused)
        32'h9000_1000, // DMA
        32'h9000_2000, // UART
        32'h9001_0000, // CLINT
        32'hA000_0000, // PLIC
        32'hB000_0000, // PRINTER
        32'hFFFF_FFFF  // END (placeholder)
    };

endpackage
