"""
Cocotb Testbench: 5x Nearest-Neighbor Video Scaler & RGB565 -> RGB888 Expansion
Module: scaler_5x.v

Verifies:
1. Coordinate downsampling: fb_rd_x = hdmi_pixel_x / 5, fb_rd_y = hdmi_pixel_y / 5
2. 1-clock pipeline latency alignment between control signals and pixel data
3. Color space bit expansion: 16-bit RGB565 -> 24-bit RGB888 with bit replication
4. Output blanking when vde is low (inactive video / blanking interval)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def rgb565_to_rgb888_ref(rgb565: int) -> int:
    """Golden reference for RGB565 -> RGB888 bit replication."""
    r5 = (rgb565 >> 11) & 0x1F
    g6 = (rgb565 >> 5) & 0x3F
    b5 = rgb565 & 0x1F

    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)

    return (r8 << 16) | (g8 << 8) | b8


@cocotb.test()
async def test_scaler_reset(dut):
    """Test 1: Verify synchronous/asynchronous reset behavior."""
    clock = Clock(dut.clk_pixel, 13.468, units="ns")  # ~74.25 MHz
    cocotb.start_soon(clock.start())

    dut.rst_pixel_n.value = 0
    dut.hdmi_pixel_x.value = 100
    dut.hdmi_pixel_y.value = 50
    dut.hdmi_hsync.value = 1
    dut.hdmi_vsync.value = 1
    dut.hdmi_vde.value = 1
    dut.fb_rd_rgb565.value = 0xFFFF

    await RisingEdge(dut.clk_pixel)
    await RisingEdge(dut.clk_pixel)

    assert dut.vde_out.value == 0, "vde_out must be 0 while in reset"
    assert dut.pixel_x_out.value == 0, "pixel_x_out must be 0 while in reset"
    assert dut.rgb888_out.value == 0, "rgb888_out must be 0 while in reset"

    dut.rst_pixel_n.value = 1
    await RisingEdge(dut.clk_pixel)
    dut._log.info("Reset test passed.")


@cocotb.test()
async def test_coordinate_mapping(dut):
    """Test 2: Verify 5x downscaling coordinate calculation across display boundary."""
    clock = Clock(dut.clk_pixel, 13.468, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_pixel_n.value = 1
    dut.hdmi_vde.value = 1
    dut.hdmi_hsync.value = 0
    dut.hdmi_vsync.value = 0
    dut.fb_rd_rgb565.value = 0

    test_coords = [
        (0, 0),
        (4, 0),
        (5, 0),
        (9, 4),
        (10, 5),
        (255, 140),
        (1275, 715),
        (1279, 719),
    ]

    for x, y in test_coords:
        dut.hdmi_pixel_x.value = x
        dut.hdmi_pixel_y.value = y
        await Timer(1, units="ns")  # Combinational evaluation

        expected_fb_x = x // 5
        expected_fb_y = y // 5

        assert dut.fb_rd_x.value == expected_fb_x, (
            f"fb_rd_x mismatch for hdmi_x={x}: expected {expected_fb_x}, got {int(dut.fb_rd_x.value)}"
        )
        assert dut.fb_rd_y.value == expected_fb_y, (
            f"fb_rd_y mismatch for hdmi_y={y}: expected {expected_fb_y}, got {int(dut.fb_rd_y.value)}"
        )
        assert dut.fb_rd_en.value == 1, "fb_rd_en should match hdmi_vde"

    dut._log.info(f"Verified {len(test_coords)} coordinate transformation vectors.")


@cocotb.test()
async def test_color_expansion_and_pipeline(dut):
    """Test 3: Verify 1-cycle pipeline latency & RGB565->RGB888 bit replication."""
    clock = Clock(dut.clk_pixel, 13.468, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_pixel_n.value = 0
    await RisingEdge(dut.clk_pixel)
    dut.rst_pixel_n.value = 1
    await RisingEdge(dut.clk_pixel)

    test_vectors = [
        # (rgb565, vde, description)
        (0xF800, 1, "Pure Red"),
        (0x07E0, 1, "Pure Green"),
        (0x001F, 1, "Pure Blue"),
        (0xFFFF, 1, "Pure White"),
        (0x0000, 1, "Pure Black"),
        (0x52AA, 1, "Mid-tone pattern 1"),
        (0xA555, 1, "Mid-tone pattern 2"),
        (0x1234, 0, "Blanking active (vde=0)"),
    ]

    for rgb565, vde, desc in test_vectors:
        dut.hdmi_vde.value = vde
        dut.hdmi_pixel_x.value = 100
        dut.hdmi_pixel_y.value = 50
        dut.fb_rd_rgb565.value = rgb565

        await RisingEdge(dut.clk_pixel)
        await Timer(1, units="ns")  # Wait for register update

        if vde:
            expected_rgb888 = rgb565_to_rgb888_ref(rgb565)
            assert dut.vde_out.value == 1, f"vde_out should be 1 for {desc}"
            assert dut.rgb888_out.value == expected_rgb888, (
                f"{desc} expansion mismatch: expected 0x{expected_rgb888:06X}, got 0x{int(dut.rgb888_out.value):06X}"
            )
        else:
            assert dut.vde_out.value == 0, "vde_out should be 0 when vde=0"
            assert dut.rgb888_out.value == 0x000000, (
                f"rgb888_out should be blanked to 0 when vde=0, got 0x{int(dut.rgb888_out.value):06X}"
            )

        dut._log.info(f"Verified color vector: {desc} -> 0x{int(dut.rgb888_out.value):06X}")
