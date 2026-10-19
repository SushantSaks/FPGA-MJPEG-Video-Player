# Cocotb Testbenches

Python-based verification for core modules using [cocotb](https://www.cocotb.org/) and Icarus Verilog.

## Quick Start

```bash
# Run all tests via pytest
make -C sim/cocotb

# Or run pytest directly
pytest -v sim/cocotb/test_runner.py
```

## Test Coverage

| Testbench | Module Under Test | What It Verifies |
|:---|:---|:---|
| `test_scaler_5x.py` | `rtl/framebuffer/scaler_5x.v` | 5x nearest-neighbor coordinate mapping (`x // 5`), 1-cycle pipeline delay, RGB565 to RGB888 bit expansion, and blanking behavior. |
| `test_uart_tx.py` | `rtl/uart/uart_tx.v` | 8N1 serial framing at 921,600 baud, 108 clocks/bit timing, start/data/stop bit generation, and `tx_busy` flag. |
| `test_uart_rx.py` | `rtl/uart/uart_rx.v` | 2-stage synchronizer, midpoint bit sampling, boundary byte patterns, and framing error detection on invalid stop bits. |
| `test_jpeg_huffman.py` | `rtl/jpeg/jpeg_huffman_lut.v` | Annex K DC/AC Huffman lookup tables (Luma & Chroma), EOB/ZRL markers, and prefix matching across suffix variations. |
| `test_mjpeg_parser.py` | `rtl/mjpeg/mjpeg_stream_parser.v` | Inter-frame noise rejection, SOI (`0xFFD8`) & EOI (`0xFFD9`) frame delimiting, backpressure (`out_ready`), and abort handling. |
| `test_button_debounce.py` | `rtl/button_debounce.v` | Rejection of glitches shorter than debounce interval, stable press detection, and single-cycle edge pulse output. |
| `test_hdmi_timing.py` | `rtl/hdmi/hdmi_timing_gen.v` | 720p 60Hz scanline timing: active video (1280), front porch (110), sync pulse (40), and back porch (220). |

## Running Individual Tests & Viewing Waveforms

To simulate an individual module and dump FST waveforms for GTKWave:

```bash
# Run a specific testbench with waveforms enabled
make -C sim/cocotb test_scaler WAVES=1

# Open in GTKWave
gtkwave sim/cocotb/sim_build_scaler/scaler_5x.fst
```

Available make targets:
- `make -C sim/cocotb test_scaler`
- `make -C sim/cocotb test_uart_tx`
- `make -C sim/cocotb test_uart_rx`
- `make -C sim/cocotb test_jpeg_huffman`
- `make -C sim/cocotb test_mjpeg_parser`
- `make -C sim/cocotb test_button_debounce`
- `make -C sim/cocotb test_hdmi_timing`
- `make -C sim/cocotb clean`
