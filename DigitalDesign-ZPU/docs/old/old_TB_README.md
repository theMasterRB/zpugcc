# Running Testbench
A rough guide of how to run the testbench
## 1. SSH into ececomp
~~~
ssh ececomp
~~~
## 2. Load new version of verilator and CPP
~~~
module load verilator/5.026
module load gcc/11.1
~~~
## 3. Run the correspoding commands
Note: You may need to create a folder named obj_dir/ for these commands

### Wishbone Bus Integration Testbench
An example of dummy masters to dummy peripherals architecture
~~~
verilator --binary --timing --trace \
    -Wno-fatal \
    --top-module tb_wb_integration \
    --Mdir tb/obj_dir/tb_wb_integration \
    -Irtl/wishbone/if \
    -Irtl/wishbone/slave \
    -Irtl/wishbone/mux \
    -Irtl/wishbone/master \
    -Irtl/wishbone/address_decoder \
    rtl/wishbone/if/bus_protocol_if.vh \
    rtl/wishbone/if/wishbone_if.vh \
    rtl/wishbone/slave/slave.sv \
    rtl/wishbone/master/master.sv \
    rtl/wishbone/mux/mux.sv \
    rtl/wishbone/address_decoder/address_decoder.sv \
    tb/integration/dummy_peripheral.sv \
    tb/integration/dummy_zpu.sv \
    tb/integration/tb_wb_integration.sv \
&& ./tb/obj_dir/tb_wb_integration/Vtb_wb_integration
~~~

### Master Testbench
~~~
verilator --binary --timing --trace \
    -Wno-fatal \
    --top-module tb_master \
    --Mdir tb/obj_dir/tb_master \
    -Irtl/wishbone/if \
    -Irtl/wishbone/slave \
    -Irtl/wishbone/master \
    rtl/wishbone/if/bus_protocol_if.vh \
    rtl/wishbone/if/wishbone_if.vh \
    rtl/wishbone/slave/slave.sv \
    rtl/wishbone/master/master.sv \
    tb/integration/dummy_peripheral.sv \
    tb/master/tb_master.sv \
&& ./tb/obj_dir/tb_master/Vtb_master
~~~
### Slave Testbench
~~~
verilator --binary --timing --trace \
    -Wno-fatal \
    --top-module tb_slave \
    --Mdir tb/obj_dir/tb_slave \
    -Irtl/wishbone/if \
    -Irtl/wishbone/slave \
    rtl/wishbone/if/bus_protocol_if.vh \
    rtl/wishbone/if/wishbone_if.vh \
    rtl/wishbone/slave/slave.sv \
    tb/integration/dummy_peripheral.sv \
    tb/slave/tb_slave.sv \
&& ./tb/obj_dir/tb_slave/Vtb_slave
~~~

### Master Mux Testbench
~~~
verilator --binary --timing --trace \
    -Wno-fatal \
    --top-module tb_mux \
    --Mdir tb/obj_dir/tb_mux \
    -Irtl/wishbone/if \
    -Irtl/wishbone/slave \
    -Irtl/wishbone/mux \
    -Irtl/wishbone/master \
    rtl/wishbone/if/bus_protocol_if.vh \
    rtl/wishbone/if/wishbone_if.vh \
    rtl/wishbone/slave/slave.sv \
    rtl/wishbone/master/master.sv \
    rtl/wishbone/mux/mux.sv \
    tb/integration/dummy_peripheral.sv \
    tb/mux/tb_mux.sv \
&& ./tb/obj_dir/tb_mux/Vtb_mux
~~~

### Address Decoder Testbench
Note: -O0 is used the disable Verilator optimizer (Which breaks this TB for some reason)
~~~
verilator --binary --timing --trace \
    -O0 \
    -Wno-fatal \
    --top-module tb_address_decoder \
    --Mdir tb/obj_dir/tb_address_decoder \
    -Irtl/wishbone/if \
    -Irtl/wishbone/slave \
    -Irtl/wishbone/address_decoder \
    rtl/wishbone/if/bus_protocol_if.vh \
    rtl/wishbone/if/wishbone_if.vh \
    rtl/wishbone/slave/slave.sv \
    rtl/wishbone/address_decoder/address_decoder.sv \
    tb/integration/dummy_peripheral.sv \
    tb/address_decoder/tb_address_decoder.sv \
    && ./tb/obj_dir/tb_address_decoder/Vtb_address_decoder
~~~

