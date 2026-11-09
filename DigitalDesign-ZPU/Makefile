CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -Werror

# g++ on Windows appends .exe to the output name
EXE := $(if $(filter Windows_NT,$(OS)),.exe,)

BUILD_DIR := build
# Standalone simulator only; the DPI library and Questa test live in simulator/Makefile
SIM_SRC   := simulator/zpu_core.cpp simulator/zpusim_main.cpp
SIM_HDR   := simulator/zpu_core.h
SIM_BIN   := $(BUILD_DIR)/zpu_sim$(EXE)

# Each block's file list lives at rtl/<block>/<block>.f and is owned by that block's team
VERILATOR      ?= verilator
VERILATOR_LINT := --lint-only -Wall
LINT_BLOCKS    := wishbone uart timer
LINT_TARGETS   := $(addprefix lint-,$(LINT_BLOCKS))
LINT_DIR       := $(BUILD_DIR)/lint

.PHONY: sim clean lint lint-summary $(LINT_TARGETS)

sim: $(SIM_BIN)

$(SIM_BIN): $(SIM_SRC) $(SIM_HDR) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $(SIM_SRC)

# -k so one block's warnings don't hide the others
lint:
	@$(MAKE) --no-print-directory -k $(LINT_TARGETS)

$(LINT_TARGETS): lint-%: | $(LINT_DIR)
	@echo "==== lint-$* ===="
	@rm -f $(LINT_DIR)/$*.status
	@if [ -z "$(wildcard rtl/$*/*.sv rtl/$*/*/*.sv)" ]; then \
		echo "No RTL in rtl/$*/ on this branch, skipping." | tee $(LINT_DIR)/$*.log; \
		echo skipped > $(LINT_DIR)/$*.status; \
	else \
		$(VERILATOR) $(VERILATOR_LINT) -F rtl/$*/$*.f > $(LINT_DIR)/$*.log 2>&1; \
		status=$$?; echo $$status > $(LINT_DIR)/$*.status; \
		cat $(LINT_DIR)/$*.log; exit $$status; \
	fi

# Markdown table of the last `make lint` run; CI appends it to the run's Summary page
lint-summary:
	@bash scripts/lint-summary.sh $(LINT_DIR) $(LINT_BLOCKS)

$(BUILD_DIR) $(LINT_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
