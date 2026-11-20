# apb-uart-uvm - Verilator 5.054 + Accellera UVM (1800.2-2020, chipsalliance/uvm-verilator)
#
#   make lint                       verilator --lint-only -Wall on the RTL
#   make build                      compile the UVM testbench (with code coverage)
#   make test TEST=uart_rx_test SEED=7
#   make regress N=50               N seeds round-robin over all tests (<=4 jobs)
#   make cov                        merge coverage from the last regression and report
#   make mutate                     bug-injection campaign (scripts/mutate.py)

SHELL   := /bin/bash
UVM     ?= third_party/uvm-verilator/src
JOBS    ?= 4
TEST    ?= uart_rand_test
SEED    ?= 1
N       ?= 50
VERB    ?= UVM_LOW
BUILD   ?= build/sim
DEFINES ?=
COV     ?= 1

RTL := rtl/uart_fifo.sv rtl/uart_baud_gen.sv rtl/uart_tx.sv rtl/uart_rx.sv rtl/apb_uart.sv
TB  := $(shell grep -v '^//' tb/files.f | grep '^tb/')

VFLAGS := --binary --timing --vpi --assert -j $(JOBS) --timescale 1ns/1ps \
          -Wno-fatal -Wno-lint -Wno-style -Wno-COVERIGN \
          +incdir+$(UVM) +incdir+tb/apb +incdir+tb/uart \
          -CFLAGS "-O1 -DVERILATOR -I$(CURDIR)/tb/compat" \
          --top-module tb_top $(addprefix +define+,$(DEFINES))
ifeq ($(COV),1)
VFLAGS += --coverage-line --coverage-toggle --coverage-user tb/coverage.vlt
endif
export OBJCACHE := ccache

.PHONY: lint build test regress regress-ws0 cov mutate clean uvm help

help:
	@sed -n '3,9p' Makefile

lint:
	verilator --lint-only -Wall $(RTL) --top-module apb_uart
	@echo "lint clean"

uvm:
	@test -f $(UVM)/uvm_pkg.sv || scripts/get_uvm.sh

$(BUILD)/Vtb_top: uvm $(RTL) $(TB) tb/files.f tb/coverage.vlt
	@mkdir -p $(BUILD)
	verilator $(VFLAGS) --Mdir $(BUILD) -o Vtb_top \
	  $(UVM)/uvm_pkg.sv $(UVM)/dpi/uvm_dpi.cc $(RTL) $(TB) > $(BUILD)/build.log 2>&1 \
	  || (tail -40 $(BUILD)/build.log; exit 1)
	@echo "built $(BUILD)/Vtb_top"

build: $(BUILD)/Vtb_top

test: $(BUILD)/Vtb_top
	@mkdir -p logs
	$(BUILD)/Vtb_top +UVM_TESTNAME=$(TEST) +verilator+seed+$(SEED) +UVM_VERBOSITY=$(VERB) \
	  +verilator+coverage+file+logs/$(TEST)_$(SEED).dat 2>&1 | tee logs/$(TEST)_$(SEED).log
	@grep -q "TEST PASSED" logs/$(TEST)_$(SEED).log

regress: $(BUILD)/Vtb_top
	.venv/bin/python scripts/regress.py --sim $(BUILD)/Vtb_top --n $(N) --jobs $(JOBS) --out logs/regress

cov:
	.venv/bin/python scripts/coverage_report.py logs/regress

mutate:
	.venv/bin/python scripts/mutate.py --jobs $(JOBS)

clean:
	rm -rf build logs

# zero-wait-state DUT configuration (WAIT_STATES = 0), no coverage
regress-ws0:
	$(MAKE) build BUILD=build/ws0 DEFINES=TB_WAIT_STATES=0 COV=0
	.venv/bin/python scripts/regress.py --sim build/ws0/Vtb_top --n $(N) --seed0 1001 --jobs $(JOBS) --no-cov --out logs/ws0
