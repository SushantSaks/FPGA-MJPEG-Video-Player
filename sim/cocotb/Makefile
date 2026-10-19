# ==============================================================================
# Cocotb Testbench Master Makefile for FPGA MJPEG Video Player
# Supports:
#   1. 'make' / 'make pytest' : Fast batch execution via pytest test_runner.py
#   2. 'make test_<module>'   : Isolated native Cocotb simulation with optional WAVES=1
# ==============================================================================

PYTHON ?= python3
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
COCOTB_MAKEFILE := $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: all test pytest clean \
        test_scaler test_uart_tx test_uart_rx test_jpeg_huffman \
        test_mjpeg_parser test_button_debounce test_hdmi_timing

all: pytest

pytest:
	$(PYTHON) -m pytest -v test_runner.py

test: pytest

# --- Individual Module Targets (Native Cocotb runner with waveform support) ---

test_scaler:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/framebuffer/scaler_5x.v \
		TOPLEVEL=scaler_5x \
		COCOTB_TEST_MODULES=test_scaler_5x \
		SIM_BUILD=sim_build_scaler

test_uart_tx:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/uart/uart_tx.v \
		TOPLEVEL=uart_tx \
		COCOTB_TEST_MODULES=test_uart_tx \
		SIM_BUILD=sim_build_uart_tx

test_uart_rx:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/uart/uart_rx.v \
		TOPLEVEL=uart_rx \
		COCOTB_TEST_MODULES=test_uart_rx \
		SIM_BUILD=sim_build_uart_rx

test_jpeg_huffman:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/jpeg/jpeg_huffman_lut.v \
		TOPLEVEL=jpeg_huffman_lut \
		COCOTB_TEST_MODULES=test_jpeg_huffman \
		SIM_BUILD=sim_build_jpeg_huffman

test_mjpeg_parser:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/mjpeg/mjpeg_stream_parser.v \
		TOPLEVEL=mjpeg_stream_parser \
		COCOTB_TEST_MODULES=test_mjpeg_parser \
		SIM_BUILD=sim_build_mjpeg_parser

test_button_debounce:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/button_debounce.v \
		TOPLEVEL=button_debounce \
		COCOTB_TEST_MODULES=test_button_debounce \
		COMPILE_ARGS="-Pbutton_debounce.CLK_FREQ_HZ=1000 -Pbutton_debounce.DEBOUNCE_MS=5" \
		SIM_BUILD=sim_build_button_debounce

test_hdmi_timing:
	$(MAKE) -f $(COCOTB_MAKEFILE) \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES=$(shell pwd)/../../rtl/hdmi/hdmi_timing_gen.v \
		TOPLEVEL=hdmi_timing_gen \
		COCOTB_TEST_MODULES=test_hdmi_timing \
		SIM_BUILD=sim_build_hdmi_timing

clean:
	rm -rf sim_build* __pycache__ .pytest_cache results.xml
