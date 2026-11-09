# make sim - builds the normal simulator
# make dpi_lib - builds zpu_dpi.so so questa can load it
# make dpi_test - compiles the sv and runs tb_zpu_dpi in questa

CXX ?= g++
CXXFLAGS ?= -std=c++11 -Wall -O2

CORE_SRC = zpu_core.cpp
DPI_SRC = zpu_dpi.cpp
SV_SRC = zpu_dpi_pkg.sv tb_zpu_dpi.sv

.PHONY: sim dpi_lib dpi_test clean

sim: zpusim

zpusim: $(CORE_SRC) zpusim_main.cpp zpu_core.h
	$(CXX) $(CXXFLAGS) -o $@ $(CORE_SRC) zpusim_main.cpp

dpi_lib: zpu_dpi.so

zpu_dpi.so: $(CORE_SRC) $(DPI_SRC) zpu_core.h
	$(CXX) $(CXXFLAGS) -shared -fPIC -o $@ $(CORE_SRC) $(DPI_SRC)

dpi_test: zpu_dpi.so $(SV_SRC)
	vlib work
	vlog -sv $(SV_SRC)
	vsim -c tb_zpu_dpi -sv_lib zpu_dpi -do "run -all; quit -f"

clean:
	rm -rf zpusim zpu_dpi.so work transcript vsim.wlf
