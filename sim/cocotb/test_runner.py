"""
Pytest Test Suite Runner for FPGA MJPEG Video Player Cocotb Testbenches
Executes all self-checking Cocotb testbenches using standard pytest / CI workflow.
"""

from pathlib import Path
import pytest
from cocotb_tools.runner import get_runner

PROJ_ROOT = Path(__file__).resolve().parent.parent.parent
RTL_DIR = PROJ_ROOT / "rtl"
SIM_DIR = PROJ_ROOT / "sim" / "cocotb"


@pytest.fixture(scope="session")
def sim():
    return get_runner("icarus")


def test_scaler_5x(sim):
    """Verify 5x Nearest-Neighbor Scaler & RGB565 -> RGB888 expansion."""
    build_dir = SIM_DIR / "sim_build_scaler"
    sim.build(
        sources=[RTL_DIR / "framebuffer" / "scaler_5x.v"],
        hdl_toplevel="scaler_5x",
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="scaler_5x",
        hdl_toplevel_lang="verilog",
        test_module="test_scaler_5x",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )


def test_uart_tx(sim):
    """Verify 8N1 UART transmitter baud timing and framing at 921,600 baud."""
    build_dir = SIM_DIR / "sim_build_uart_tx"
    sim.build(
        sources=[RTL_DIR / "uart" / "uart_tx.v"],
        hdl_toplevel="uart_tx",
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="uart_tx",
        hdl_toplevel_lang="verilog",
        test_module="test_uart_tx",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )


def test_uart_rx(sim):
    """Verify 8N1 UART receiver midpoint sampling and framing error detection."""
    build_dir = SIM_DIR / "sim_build_uart_rx"
    sim.build(
        sources=[RTL_DIR / "uart" / "uart_rx.v"],
        hdl_toplevel="uart_rx",
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="uart_rx",
        hdl_toplevel_lang="verilog",
        test_module="test_uart_rx",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )


def test_jpeg_huffman_lut(sim):
    """Verify JPEG Annex K variable-length prefix decoding tables."""
    build_dir = SIM_DIR / "sim_build_jpeg_huffman"
    sim.build(
        sources=[RTL_DIR / "jpeg" / "jpeg_huffman_lut.v"],
        hdl_toplevel="jpeg_huffman_lut",
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="jpeg_huffman_lut",
        hdl_toplevel_lang="verilog",
        test_module="test_jpeg_huffman",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )


def test_mjpeg_stream_parser(sim):
    """Verify MJPEG SOI/EOI frame boundary detector and backpressure flow control."""
    build_dir = SIM_DIR / "sim_build_mjpeg_parser"
    sim.build(
        sources=[RTL_DIR / "mjpeg" / "mjpeg_stream_parser.v"],
        hdl_toplevel="mjpeg_stream_parser",
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="mjpeg_stream_parser",
        hdl_toplevel_lang="verilog",
        test_module="test_mjpeg_parser",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )


def test_button_debounce(sim):
    """Verify pushbutton glitch filter and 1-cycle edge detector."""
    build_dir = SIM_DIR / "sim_build_button_debounce"
    sim.build(
        sources=[RTL_DIR / "button_debounce.v"],
        hdl_toplevel="button_debounce",
        parameters={"CLK_FREQ_HZ": 1000, "DEBOUNCE_MS": 5},
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="button_debounce",
        hdl_toplevel_lang="verilog",
        test_module="test_button_debounce",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )


def test_hdmi_timing_gen(sim):
    """Verify CEA-861 720p 60Hz video timing generator and scanline sync."""
    build_dir = SIM_DIR / "sim_build_hdmi_timing"
    sim.build(
        sources=[RTL_DIR / "hdmi" / "hdmi_timing_gen.v"],
        hdl_toplevel="hdmi_timing_gen",
        build_dir=build_dir,
        clean=True,
    )
    sim.test(
        hdl_toplevel="hdmi_timing_gen",
        hdl_toplevel_lang="verilog",
        test_module="test_hdmi_timing",
        test_dir=SIM_DIR,
        build_dir=build_dir,
    )
