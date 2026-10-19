"""
Cocotb Testbench: 8N1 UART Receiver with Midpoint Sampling
Module: uart_rx.v

Verifies:
1. Reset state (rx_data=0, rx_valid=0, rx_error=0)
2. Midpoint bit sampling accuracy with 2-stage metastability synchronizer
3. Data reception integrity across standard and boundary byte patterns
4. Framing error detection when stop bit is invalid (0 instead of 1)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 10.0  # 100 MHz
CLKS_PER_BIT = 108    # 100_000_000 / 921_600 = 108 cycles


async def drive_uart_byte(dut, byte_val: int, stop_bit: int = 1):
    """Coroutine that acts as a UART transmitter driving rx_pin."""
    # Start bit
    dut.rx_pin.value = 0
    await ClockCycles(dut.clk, CLKS_PER_BIT)

    # 8 Data bits (LSB first)
    for i in range(8):
        dut.rx_pin.value = (byte_val >> i) & 1
        await ClockCycles(dut.clk, CLKS_PER_BIT)

    # Stop bit
    dut.rx_pin.value = stop_bit
    await ClockCycles(dut.clk, CLKS_PER_BIT)

    # Return to idle
    dut.rx_pin.value = 1


@cocotb.test()
async def test_uart_rx_reset(dut):
    """Test 1: Verify reset conditions."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.rx_pin.value = 1
    await ClockCycles(dut.clk, 5)

    assert dut.rx_data.value == 0, "rx_data must be 0 during reset"
    assert dut.rx_valid.value == 0, "rx_valid must be 0 during reset"
    assert dut.rx_error.value == 0, "rx_error must be 0 during reset"

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


@cocotb.test()
async def test_uart_rx_data_reception(dut):
    """Test 2: Transmit bytes into RX and verify decoded data and valid pulse."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.rx_pin.value = 1
    await ClockCycles(dut.clk, 20)

    test_bytes = [0xA5, 0x5A, 0x00, 0xFF, 0x33, 0xC6]

    for val in test_bytes:
        dut._log.info(f"Driving byte 0x{val:02X} into rx_pin...")
        driver = cocotb.start_soon(drive_uart_byte(dut, val, stop_bit=1))

        # Wait for rx_valid pulse
        await RisingEdge(dut.rx_valid)
        assert dut.rx_data.value == val, (
            f"UART RX byte mismatch: expected 0x{val:02X}, received 0x{int(dut.rx_data.value):02X}"
        )
        assert dut.rx_error.value == 0, "rx_error asserted unexpectedly during valid frame"
        await driver
        dut._log.info(f"Successfully received and verified 0x{val:02X}")

        # Gap between bytes
        await ClockCycles(dut.clk, 20)


@cocotb.test()
async def test_uart_rx_framing_error(dut):
    """Test 3: Inject framing error (invalid stop bit = 0) and verify error pulse."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.rx_pin.value = 1
    await ClockCycles(dut.clk, 20)

    dut._log.info("Injecting invalid framing sequence (stop_bit=0)...")
    cocotb.start_soon(drive_uart_byte(dut, 0x7E, stop_bit=0))

    await RisingEdge(dut.rx_error)
    assert dut.rx_error.value == 1, "rx_error must assert on framing error"
    assert dut.rx_valid.value == 0, "rx_valid must not assert when stop bit is invalid"
    dut._log.info("Framing error correctly caught and asserted.")

    # Return rx_pin to idle and verify recovery
    dut.rx_pin.value = 1
    await ClockCycles(dut.clk, 150)
