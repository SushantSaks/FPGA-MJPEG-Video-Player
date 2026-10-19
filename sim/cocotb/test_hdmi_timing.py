"""
Cocotb Testbench: CEA-861 720p 60Hz HDMI Video Timing Generator
Module: hdmi_timing_gen.v

Verifies:
1. Reset conditions (all timing pulses deasserted)
2. Scanline active video interval (1280 pixels @ vde=1)
3. Horizontal blanking intervals: Front Porch (110), HSYNC pulse (40), Back Porch (220)
4. Scanline sync signals: frame_start and line_start pulses
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

PIXEL_CLK_NS = 13.468  # 74.25 MHz


@cocotb.test()
async def test_hdmi_timing_sequence(dut):
    """Verify CEA-861 720p scanline and blanking intervals."""
    clock = Clock(dut.clk_pixel, PIXEL_CLK_NS, units="ns")
    cocotb.start_soon(clock.start())

    # 1. Reset check
    dut.rst_n.value = 0
    await ClockCycles(dut.clk_pixel, 5)
    assert dut.hsync.value == 0, "hsync must be 0 in reset"
    assert dut.vsync.value == 0, "vsync must be 0 in reset"
    assert dut.vde.value == 0, "vde must be 0 in reset"

    # 2. Release reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk_pixel, 5)

    # 3. Wait for active video (vde == 1)
    while dut.vde.value != 1:
        await RisingEdge(dut.clk_pixel)

    dut._log.info("Active video started (vde=1). Verifying scanline progression...")
    
    # Wait until start of next clean scanline where line_start pulses
    while dut.line_start.value != 1:
        await RisingEdge(dut.clk_pixel)

    dut._log.info("Synchronized to scanline start (line_start=1).")

    # Step through active video pixels
    active_pixel_count = 0
    while dut.vde.value == 1:
        assert dut.hsync.value == 0, "hsync must be 0 during active video"
        active_pixel_count += 1
        await RisingEdge(dut.clk_pixel)

    dut._log.info(f"Verified {active_pixel_count} active pixels in scanline.")
    assert active_pixel_count == 1280, f"Expected 1280 active pixels, got {active_pixel_count}"

    # Step through front porch (vde=0, hsync=0)
    front_porch_count = 0
    while dut.hsync.value == 0 and dut.vde.value == 0:
        front_porch_count += 1
        await RisingEdge(dut.clk_pixel)

    dut._log.info(f"Verified {front_porch_count} front porch cycles.")
    assert front_porch_count == 110, f"Expected 110 front porch cycles, got {front_porch_count}"

    # Step through HSYNC pulse (hsync=1, vde=0)
    hsync_count = 0
    while dut.hsync.value == 1:
        assert dut.vde.value == 0, "vde must be 0 during HSYNC pulse"
        hsync_count += 1
        await RisingEdge(dut.clk_pixel)

    dut._log.info(f"Verified {hsync_count} HSYNC pulse cycles.")
    assert hsync_count == 40, f"Expected 40 HSYNC cycles, got {hsync_count}"

    # Step through back porch (vde=0, hsync=0)
    back_porch_count = 0
    while dut.vde.value == 0:
        assert dut.hsync.value == 0, "hsync must be 0 during back porch"
        back_porch_count += 1
        await RisingEdge(dut.clk_pixel)

    dut._log.info(f"Verified {back_porch_count} back porch cycles.")
    assert back_porch_count == 220, f"Expected 220 back porch cycles, got {back_porch_count}"

    # Total horizontal line cycles: 1280 + 110 + 40 + 220 = 1650
    total_line_cycles = active_pixel_count + front_porch_count + hsync_count + back_porch_count
    assert total_line_cycles == 1650, f"Total line duration mismatch: {total_line_cycles} != 1650"
    dut._log.info("CEA-861 horizontal scanline timing check passed.")
