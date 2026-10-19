# FPGA Motion-JPEG Video Player (Verilog-2001)

[![CI](https://github.com/SushantSaks/FPGA-MJPEG-Video-Player/actions/workflows/ci.yml/badge.svg)](https://github.com/SushantSaks/FPGA-MJPEG-Video-Player/actions/workflows/ci.yml)

A complete, fully synthesizable hardware Motion-JPEG (MJPEG) video player designed for the AMD Spartan-7 FPGA on the RealDigital Boolean Board. The system decodes baseline JPEG frames in real time from onboard QSPI NOR flash memory and displays 60 Hz 720p HD video over native HDMI/DVI.

The entire RTL implementation is written in strict, portable **Verilog-2001** and includes a complete PC-to-FPGA video preparation and UART upload workflow.

---

## 1. Project Overview

This repository contains the pure Verilog-2001 port of an FPGA-based hardware video player capable of streaming and decoding Motion-JPEG video sequences without a softcore CPU. The hardware architecture features a streaming pipeline from non-volatile flash storage through entropy decoding, inverse DCT, and color-space conversion into a double-buffered BRAM framebuffer, scaled 5x to 720p 60 Hz video.

### End-to-End Pipeline
```
[PC Video File] (MP4/MKV/AVI)
       |
       v  host/convert_video.py (ffmpeg + Pillow standard Annex K 4:2:0)
[MJPEG Stream] (256x144 @ 15 FPS)
       |
       v  host/upload_video.py (UART 921,600 baud, CRC32 verification)
[FPGA UART Upload Engine]
       |
       v  SPI Mode 0 Page Program (256B/page)
[16 MB Winbond W25Q128 QSPI Flash]
       |
       v  Continuous Playback Streaming
[MJPEG Stream Parser] (SOI 0xFFD8 / EOI 0xFFD9 boundary detection)
       |
       v  64-bit Bit Buffer + Annex K Huffman LUT + Dequantization
[Hardware JPEG Decoder Core]
       |
       v  Pipelined 2D IDCT (Chen/AAH Algorithm)
[Spatial Block Reconstruct] (8x8 Luminance & Chrominance)
       |
       v  4:2:0 YCbCr to RGB565 Converter
[Double-Buffered Framebuffer] (144 KB BRAM, atomic VSYNC toggle)
       |
       v  5x Nearest-Neighbor Video Scaler (256x144 -> 1280x720)
[HDMI/DVI TMDS Subsystem] (74.25 MHz pixel clock, OSERDES/ODDR 10:1 DDR serialization)
       |
       v
[720p 60 Hz HDMI Display]
```

---

## 2. Key Hardware Features

- **Pure Synthesizable Verilog-2001:** Standard-compliant RTL across all 27 hardware modules, free of SystemVerilog constructs.
- **Hardware Baseline JPEG Decoder:** Full ISO/IEC 10918-1 baseline decode path supporting YCbCr 4:2:0 subsampling, standard ITU-T Annex K Huffman tables, 8-bit precision, and marker parsing.
- **Pipelined 2D IDCT Engine:** Fixed-point 2-dimensional inverse discrete cosine transform using the Chen/AAH factorization for high throughput and precision timing closure.
- **Color Space Converter:** 2-stage DSP-pipelined matrix multiplication converting 16x16 macroblock samples from YCbCr to 16-bit RGB565.
- **Double-Buffered Framebuffer:** 144 KB dual-port BRAM buffer (2 banks of 256x144 16-bit words) with atomic buffer swapping synchronized to vertical blanking (VSYNC) to eliminate display tearing.
- **Zero-Border Integer Scaler:** 5x nearest-neighbor scaler mapping 256x144 video exactly to 1280x720 active video (256 x 5 = 1280, 144 x 5 = 720) with zero letterboxing or border artifacts.
- **HDMI/DVI Video Output:** CEA-861 compliant 720p @ 60 Hz video timing generator, DVI 1.0 DC-balanced TMDS 8b/10b encoder, and 10:1 DDR serialization using Spartan-7 primitives.
- **High-Speed UART Upload Engine:** 921,600 baud receiver with 2 KB FIFO, hardware IEEE 802.3 CRC32 verification, sector erase/page write automation, and post-write flash readback verification.
- **Onboard QSPI NOR Flash Controller:** Dedicated controller for 16 MB Winbond W25Q128 supporting continuous streaming playback, sector erases, and page programming via FPGA `STARTUPE2` primitive.

---

## 3. Target FPGA and Board

| Parameter | Specification |
|:---|:---|
| **FPGA Part** | AMD / Xilinx Spartan-7 `xc7s50csga324-1` |
| **Development Board** | RealDigital Boolean Board |
| **Primary Clock** | 100.0 MHz onboard oscillator (Pin `F14`) |
| **Pixel Clock** | 74.25 MHz (generated via MMCM) |
| **Serial TMDS Clock** | 371.25 MHz (5x serial clock for DDR 10:1 serialization) |
| **Flash Memory** | Winbond W25Q128 (16 MB SPI/QSPI NOR Flash) |
| **Video Output** | Native HDMI Type-A connector (TMDS 3.3V) |
| **Host Interface** | FTDI USB-UART Bridge (`V12` RX, `U11` TX) @ 921,600 Baud |

---

## 4. Hardware Architecture

### Clocking Domains and CDC
1. **System Clock Domain (100.0 MHz):**
   - UART upload receiver and CRC32 verification engine.
   - QSPI flash controller and erase/program/read FSMs.
   - MJPEG stream parser and JPEG hardware decoder core.
   - Framebuffer write port.
2. **Pixel Clock Domain (74.25 MHz):**
   - CEA-861 720p timing generator.
   - Framebuffer read port and 5x coordinate scaler.
   - TMDS 8b/10b encoders and DVI serialization logic.
3. **Serial Clock Domain (371.25 MHz):**
   - TMDS 10:1 DDR serializer and differential `OBUFDS` line drivers.
4. **Clock-Domain Crossing (CDC):**
   - Toggle-based handshake synchronizers for frame decode completion.
   - Dual-port asynchronous BRAM framebuffer crossing between write and read clock domains.
   - Asynchronous reset synchronizers with glitch-filtered debouncers.

### Video Resolution & Memory Footprint
- Native source resolution: 256 x 144 pixels.
- Pixel format: RGB565 (16 bits per pixel).
- Single frame size: $256 \times 144 \times 2 = 73,728\text{ bytes}$ (36,864 words).
- Double-buffer capacity: $147,456\text{ bytes}$ ($\approx 144\text{ KB}$), mapped into internal Spartan-7 36 Kb Block RAMs.
- Display output: 1280 x 720 @ 60.0 Hz.

---

## 5. Directory Structure

```
mjpeg_fpga_player_verilog/
├── README.md                      # Project documentation and reproduction guide
├── .gitignore                     # Git exclusion rules for build outputs and caches
├── build.tcl                      # Vivado batch synthesis and implementation script
├── program.tcl                    # Hardware Manager JTAG programming script
├── constraints/
│   └── boolean.xdc                # Pinout, I/O standards, and timing constraints
├── host/
│   ├── convert_video.py           # Universal video converter (MP4/MKV to 256x144 MJPEG)
│   ├── upload_video.py            # High-speed UART uploader with CRC32 verification
│   └── requirements.txt           # Python host package dependencies (pyserial, Pillow)
├── rtl/
│   ├── mjpeg_player_top.v         # Top-level SoC integration and clock management
│   ├── button_debounce.v          # Glitch filter and edge generator for controls
│   ├── framebuffer/
│   │   ├── bram_dual_port.v       # True dual-port Spartan-7 BRAM primitive wrapper
│   │   ├── framebuffer_double_buffer.v # 144 KB double buffer with atomic VSYNC swap
│   │   └── scaler_5x.v            # 5x nearest-neighbor scaler and RGB565-to-RGB888
│   ├── hdmi/
│   │   ├── hdmi_timing_gen.v      # 720p 60Hz CEA-861 video timing generator
│   │   ├── hdmi_test_pattern.v    # Diagnostic SMPTE color bars and test patterns
│   │   ├── tmds_encoder.v         # DVI 1.0 TMDS 8b/10b DC-balanced encoder
│   │   ├── tmds_serializer.v      # 10:1 DDR serializer with ODDR and OBUFDS
│   │   └── hdmi_tx_top.v          # Integrated HDMI transmitter subsystem
│   ├── jpeg/
│   │   ├── jpeg_bit_buffer.v      # 64-bit barrel shifter with byte unstuffing
│   │   ├── jpeg_decoder_core.v    # Baseline JPEG parsing and decode FSM
│   │   ├── jpeg_decoder_top.v     # FIFO-buffered decoder integration wrapper
│   │   ├── jpeg_huffman_lut.v     # Annex K single-cycle Huffman decoder LUT
│   │   ├── jpeg_idct_2d.v         # Pipelined 2D inverse DCT arithmetic engine
│   │   ├── jpeg_qtable_mem.v      # Dual 64-byte quantization table memories
│   │   └── jpeg_ycbcr_to_rgb.v    # 4:2:0 YCbCr to RGB565 converter pipeline
│   ├── mjpeg/
│   │   ├── mjpeg_playback_controller.v # 15 FPS cadence pacing and play/pause logic
│   │   ├── mjpeg_playback_top.v   # Integrated playback subsystem
│   │   └── mjpeg_stream_parser.v  # SOI/EOI frame boundary detector
│   ├── qspi/
│   │   ├── qspi_controller.v      # W25Q128 Flash SPI/QSPI command & page engine
│   │   └── qspi_playback_reader.v # Continuous video stream playback reader
│   └── uart/
│       ├── uart_rx.v              # 8N1 UART receiver with midpoint sampling
│       ├── uart_rx_fifo.v         # 2 KB BRAM FIFO buffer
│       ├── uart_tx.v              # 8N1 UART transmitter
│       ├── uart_upload_parser.v   # Command parser and CRC32 verification engine
│       └── uart_upload_top.v      # Integrated UART upload subsystem
└── sim/
    ├── tb_mjpeg_subsystems.v      # Verilog-2001 verification testbench for core units
    └── cocotb/                    # Modern Python Cocotb verification suite (pytest & Make)
        ├── Makefile               # Batch and individual test target runner
        ├── test_runner.py         # Pytest test suite orchestrator
        ├── test_scaler_5x.py      # 5x Scaler & RGB565->888 color expansion
        ├── test_uart_tx.py        # 8N1 UART transmitter baud & framing verification
        ├── test_uart_rx.py        # 8N1 UART receiver midpoint sampling & framing errors
        ├── test_jpeg_huffman.py   # Annex K Huffman variable-length decoder LUT
        ├── test_mjpeg_parser.py   # SOI/EOI stream parser & backpressure flow control
        ├── test_button_debounce.py# Pushbutton glitch filter & edge pulse generator
        ├── test_hdmi_timing.py    # CEA-861 720p 60Hz timing generator intervals
        └── README.md              # Detailed Cocotb documentation and waveform guide
```

---

## 6. Required Development Tools

- **AMD Vivado:** Vivado 2020.2 or newer (tested with Vivado 2026.1 on Ubuntu 22.04 LTS).
- **Simulator:** Vivado Simulator (`xsim`), Icarus Verilog (`iverilog` v11+), or Verilator.
- **Python Verification:** Python 3.8+, `cocotb` (v2.0+), `pytest`.
- **FFmpeg:** `ffmpeg` and `ffprobe` (for video transcoding).

---

## 7. Building the Bitstream

Build the complete FPGA bitstream in batch mode using the provided Tcl script:

```bash
vivado -mode batch -source build.tcl
```

The script automatically executes:
1. RTL elaboration and synthesis targeting the Spartan-7 `xc7s50csga324-1`.
2. Logic optimization (`opt_design -directive Explore`).
3. Placement (`place_design -directive Explore`).
4. Physical logic optimization (`phys_opt_design -directive Explore`).
5. Detailed routing (`route_design -directive Explore`).
6. Timing verification, DRC checks, and utilization report generation.
7. Bitstream generation (`mjpeg_player_top.bit` and `mjpeg_player_top.bin`).

All build products are placed in `build_output/` with comprehensive reports in `build_output/reports/`.

---

## 8. Programming the FPGA

Connect the Boolean Board via USB and program the generated bitstream via JTAG:

```bash
vivado -mode batch -source program.tcl
```

Alternatively, open Vivado Hardware Manager and program `build_output/mjpeg_player_top.bit` directly to the `xc7s50` target.

---

## 9. Python Environment Setup

Install the required host dependencies in a clean virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r host/requirements.txt
```

Verify that `ffmpeg` is available on your system PATH:

```bash
ffmpeg -version
```

---

## 10. Video Preparation

Any common video file (MP4, MKV, AVI, WebM) must be converted into the hardware-compatible MJPEG stream before uploading.

Run the converter:

```bash
python3 host/convert_video.py input_movie.mp4 -o videos/movie.mjpeg --quality 80
```

### Video Preparation Parameters
- Resolution: Resized to exact 256x144 pixels (default fit mode: `pad` with black letterboxing to preserve aspect ratio).
- Frame Rate: Paced to 15.0 FPS (corresponds to an atomic buffer swap every 4 VSYNC intervals at 60 Hz).
- Chroma Subsampling: 4:2:0 planar YCbCr.
- Huffman Tables: Standard ITU-T Annex K baseline tables (enforced via `optimize=False`).
- Maximum Duration: Supports up to 12 MB of video (accommodating several minutes of continuous video in the 16 MB onboard flash).

---

## 11. PC-to-FPGA Video Upload

Upload the prepared video over the onboard USB-UART bridge at 921,600 baud:

```bash
python3 host/upload_video.py videos/movie.mjpeg --port /dev/ttyUSB1
```

### Upload Protocol Sequence
1. **Header Handshake:** The host transmits a 14-byte binary header containing magic bytes (`"MJPG"`), video payload length, resolution, and target frame rate.
2. **Flash Erase:** The FPGA calculates the required number of 4 KB sectors and issues hardware sector erase commands to the W25Q128 Flash.
3. **Paged Streaming:** Video data is streamed in 256-byte chunks with hardware-matched flow pacing.
4. **CRC32 Checksum:** Host transmits the IEEE 802.3 CRC32 checksum and completion delimiter (`"END!"`).
5. **Readback Verification:** The FPGA independently reads back all written data from the physical flash memory, computes an internal CRC32, and returns a status byte:
   - `0x06` (ACK): Flash verified successfully; video ready for playback.
   - `0x15` (NAK): Flash readback CRC mismatch.
   - `0x16` (NAK): UART transmission CRC mismatch.
   - `0x17` (NAK): Protocol delimiter error.

---

## 12. Playback Instructions

Once programmed and loaded, video playback is controlled via onboard pushbuttons and switches:

| Control | Location | Function |
|:---|:---|:---|
| **`rst_btn_n`** | Pushbutton Down (`H2`) | System active-low hardware reset |
| **`btn_play_pause`** | Pushbutton Up (`J2`) | Toggle video playback / pause |
| **`btn_restart`** | Pushbutton Right (`J1`) | Restart playback from frame 0 (loop start) |
| **`sw[0]`** | Slide Switch 0 (`V2`) | Video Source: `0` = HDMI Diagnostic Color Bars, `1` = Live Flash Video |
| **`sw[1]`** | Slide Switch 1 (`U2`) | Reserved / Diagnostic test pattern select |

### Diagnostic Status LEDs (`led[15:0]`)
- `led[0]`: Upload active indicator (UART upload FSM busy).
- `led[1]`: Upload success indicator (QSPI readback verified with ACK).
- `led[2]`: Video playing.
- `led[3]`: Video paused.
- `led[11:4]`: Current playback frame counter `[7:0]`.
- `led[15:12]`: Hardware decoded frames counter `[3:0]`.

---

## 13. Verification Methodology

The Verilog-2001 port underwent multi-tier verification:

1. **Syntax & Standard Compliance:**
   - Evaluated with strict Verilog-2001 compliance under `iverilog -g2001` and Vivado `xvlog`.
   - Verified zero SystemVerilog keywords (`logic`, `always_ff`, `always_comb`, `typedef`, `enum`, unpacked array ports).
2. **Subsystem Verilog Simulation:**
   - Self-checking testbench (`sim/tb_mjpeg_subsystems.v`) validates the Annex K Huffman LUT, coordinate transformations, 5x scaler mapping, and UART 921,600 baud loopback under Icarus Verilog (`vvp`) and Vivado Simulator (`xsim`).
3. **Cocotb Testbenches (Python):**
   - Unit tests in `sim/cocotb/` using Cocotb and Icarus Verilog:
     - `test_scaler_5x.py`: 5x downsampling math & RGB565->RGB888 bit replication.
     - `test_uart_tx.py`: 921,600 baud serial framing and bit timing.
     - `test_uart_rx.py`: Midpoint sampling and framing error detection.
     - `test_jpeg_huffman.py`: Annex K DC/AC LUT decoding and marker lookup.
     - `test_mjpeg_parser.py`: SOI/EOI boundary detection and ready/valid flow control.
     - `test_button_debounce.py`: Glitch rejection and 1-cycle edge pulse output.
     - `test_hdmi_timing.py`: 720p 60Hz scanline timing and blanking intervals.
   - Run all tests:
     ```bash
     make -C sim/cocotb
     # or
     pytest -v sim/cocotb/test_runner.py
     ```
   - Dump waveforms for GTKWave:
     ```bash
     make -C sim/cocotb test_scaler WAVES=1
     gtkwave sim/cocotb/sim_build_scaler/scaler_5x.fst
     ```
4. **Elaboration & Hierarchy Verification:**
   - Full top-level elaboration (`xelab -L unisims_ver work.mjpeg_player_top`) confirmed clean integration across all 27 modules with Xilinx primitives (`MMCME2_ADV`, `STARTUPE2`, `ODDR`, `OBUFDS`).
5. **Synthesis & Implementation Closure:**
   - Executed through AMD Vivado batch flow to verify timing closure, DSP/BRAM inference, and bitstream generation.

---

## 14. Known Limitations

- **Chroma Subsampling:** The hardware decoder core specifically decodes baseline JPEG images with 4:2:0 chroma subsampling. Progressive JPEG streams, arithmetic coding, and 4:4:4/4:2:2 formats are not supported in hardware. Always use `host/convert_video.py` to prepare streams.
- **Audio:** The pipeline implements video-only playback; audio streams are omitted.
- **Flash Storage Limit:** The W25Q128 Flash provides 16 MB total storage. Flash offset `0x000000` to `0x3FFFFF` is reserved for FPGA SPI configuration bitstream; user MJPEG video is mapped to offset `0x400000` (12 MB maximum video payload).

---

## 15. Build and Validation Status

| Milestone | Status | Details |
|:---|:---:|:---|
| **Verilog-2001 RTL Port** | **PASSED** | 27 modules ported, strictly Verilog-2001 synthesizable |
| **Subsystem Testbench** | **PASSED** | 0 errors in behavioral simulation (`iverilog` & `xsim`) |
| **Cocotb Test Suite** | **PASSED** | 7 unit tests passed via `pytest` and Icarus |
| **CI (GitHub Actions)** | **ACTIVE** | Automated test suite running on push & PR |
| **Top-Level Elaboration** | **PASSED** | Clean snapshot built with Xilinx unisim primitives |
| **Synthesis & Implementation** | **PASSED** | Positive slack, zero setup/hold timing violations on Spartan-7 |
| **Bitstream Generation** | **PASSED** | Generated `mjpeg_player_top.bit` and `.bin` |
| **Host Utilities** | **PASSED** | Paced uploader with CRC32 verification and Pillow converter ready |

---

## License

This project is released for academic, evaluation, and engineering portfolio demonstration purposes. All rights to the original architectural implementation belong to the respective authors.
