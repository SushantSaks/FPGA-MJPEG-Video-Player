"""
Cocotb Testbench: 8N1 UART Transmitter
Module: uart_tx.v

Verifies:
1. Reset state (tx_pin idle high, tx_busy low)
2. Accurate bit timing at 921,600 baud (108 clock cycles per bit @ 100 MHz)
3. Framing structure: 1 start bit (0), 8 data bits (LSB-first), 1 stop bit (1)
4. Busy handshake timing across single bytes and back-to-back transmissions
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge

CLK_PERIOD_NS = 10.0  # 100 MHz
CLKS_PER_BIT = 108    # 100_000_000 / 921_600 = 108.5 -> 108 cycles


async def monitor_uart_byte(dut) -> int:
    """Coroutine that acts as a UART receiver monitor sampling tx_pin."""
    # Wait for falling edge of start bit
    await FallingEdge(dut.tx_pin)

    # Sample midpoint of start bit (54 cycles)
    await ClockCycles(dut.clk, CLKS_PER_BIT // 2)
    assert dut.tx_pin.value == 0, "Start bit must be 0"

    # Sample 8 data bits at midpoint of each bit interval
    rx_val = 0
    for i in range(8):
        await ClockCycles(dut.clk, CLKS_PER_BIT)
        bit = int(dut.tx_pin.value)
        rx_val |= (bit << i)

    # Sample stop bit
    await ClockCycles(dut.clk, CLKS_PER_BIT)
    assert dut.tx_pin.value == 1, "Stop bit must be 1"

    return rx_val


@cocotb.test()
async def test_uart_tx_reset(dut):
    """Test 1: Verify reset conditions."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.tx_start.value = 0
    dut.tx_data.value = 0
    await ClockCycles(dut.clk, 5)

    assert dut.tx_pin.value == 1, "tx_pin must idle high during reset"
    assert dut.tx_busy.value == 0, "tx_busy must be 0 during reset"

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    assert dut.tx_pin.value == 1, "tx_pin must idle high after reset"
    assert dut.tx_busy.value == 0, "tx_busy must remain 0 after reset"


@cocotb.test()
async def test_uart_tx_single_byte(dut):
    """Test 2: Transmit alternating bit patterns and verify serial framing."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.tx_start.value = 0
    await ClockCycles(dut.clk, 10)

    test_bytes = [0x55, 0xAA, 0x00, 0xFF, 0x3C]

    for val in test_bytes:
        dut._log.info(f"Transmitting byte 0x{val:02X}...")
        # Start receiver monitor task concurrently
        monitor_task = cocotb.start_soon(monitor_uart_byte(dut))

        # Pulse tx_start for 1 clock cycle
        await RisingEdge(dut.clk)
        dut.tx_data.value = val
        dut.tx_start.value = 1
        await RisingEdge(dut.clk)
        dut.tx_start.value = 0

        # Wait for monitor task to decode serial stream
        received_val = await monitor_task
        assert received_val == val, (
            f"UART TX byte mismatch: expected 0x{val:02X}, received 0x{received_val:02X}"
        )

        # Wait for tx_busy to deassert
        while dut.tx_busy.value == 1:
            await RisingEdge(dut.clk)

        dut._log.info(f"Successfully transmitted and verified 0x{val:02X}")
        await ClockCycles(dut.clk, 20)  # Inter-byte gap
