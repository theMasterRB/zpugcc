TARGET = sim
TOOL = modelsim

.PHONY: sim_slave sim_slave_gui sim sim_gui clean

sim: 
	fusesoc run --target=$(TARGET) --tool=$(TOOL) socet:bus-components:tb_wb_integration:0.1.0

sim_gui:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) --setup --build socet:bus-components:tb_wb_integration:0.1.0
	$(MAKE) -C build/socet_bus-components_tb_wb_integration_0.1.0/sim-modelsim  run-gui

sim_slave:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) socet:bus-components:wb_slave:0.1.0

sim_slave_gui:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) --setup --build socet:bus-components:wb_slave:0.1.0
	$(MAKE) -C build/socet_bus-components_wb_slave_0.1.0/sim-modelsim run-gui

sim_master:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) socet:bus-components:wb_master:0.1.0

sim_master_gui:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) --setup --build socet:bus-components:wb_master:0.1.0
	$(MAKE) -C build/socet_bus-components_wb_master_0.1.0/sim-modelsim run-gui

sim_mux:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) socet:bus-components:wb_mux:0.1.0

sim_mux_gui:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) --setup --build CORE = socet:bus-components:wb_mux:0.1.0
	$(MAKE) -C build/socet_bus-components_wb_mux_0.1.0/sim-modelsim run-gui

sim_address_decoder:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) socet:bus-components:wb_address_decoder:0.1.0

sim_address_decoder_gui:
	fusesoc run --target=$(TARGET) --tool=$(TOOL) --setup --build socet:bus-components:wb_address_decoder:0.1.0
	$(MAKE) -C build/socet_bus-components_wb_address_decoder_0.1.0/sim-modelsim run-gui

clean:
	rm -rf build
