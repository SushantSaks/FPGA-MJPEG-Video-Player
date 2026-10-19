"""
Cocotb Testbench: Pushbutton Glitch Filter & Edge Detector
Module: button_debounce.v

Verifies:
1. Reset conditions (btn_state=0, btn_pulse=0)
2. Glitch immunity: pulses shorter than debounce threshold are filtered out
3. Stable assertion: button held longer than threshold asserts btn_state
4. Single-cycle pulse generation (btn_pulse is high for exactly 1 clock period)
5. Clean release back to idle
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 10.0  # 100 MHz clock


@cocotb.test()
async def test_debounce_reset(dut):
    """Test 1: Verify reset conditions."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.btn_in.value = 1
    await ClockCycles(dut.clk, 5)

    assert dut.btn_state.value == 0, "btn_state must be 0 during reset"
    assert dut.btn_pulse.value == 0, "btn_pulse must be 0 during reset"

    dut.rst_n.value = 1
    dut.btn_in.value = 0
    await ClockCycles(dut.clk, 5)


@cocotb.test()
async def test_glitch_rejection(dut):
    """Test 2: Inject rapid glitches (< debounce window) and verify they are suppressed."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.btn_in.value = 0
    await ClockCycles(dut.clk, 10)

    # Inject 2-cycle high glitch (threshold is 5 cycles in test configuration)
    dut._log.info("Injecting short glitch (2 clock cycles)...")
    dut.btn_in.value = 1
    await ClockCycles(dut.clk, 2)
    dut.btn_in.value = 0
    await ClockCycles(dut.clk, 10)

    assert dut.btn_state.value == 0, "btn_state must remain 0 after short glitch"
    assert dut.btn_pulse.value == 0, "btn_pulse must not trigger on short glitch"
    dut._log.info("Glitch successfully filtered out.")


@cocotb.test()
async def test_stable_press_and_single_pulse(dut):
    """Test 3: Apply stable press, verify state change and exact 1-cycle pulse."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.btn_in.value = 0
    await ClockCycles(dut.clk, 5)

    # Press and hold button stably (10 cycles > 5 cycle threshold)
    dut._log.info("Holding button stably high...")
    dut.btn_in.value = 1

    pulse_count = 0
    # Monitor for 15 cycles
    for _ in range(15):
        await RisingEdge(dut.clk)
        if dut.btn_pulse.value == 1:
            pulse_count += 1
            assert dut.btn_state.value == 1, "btn_state must be 1 when pulse is produced"

    assert pulse_count == 1, f"Expected exactly 1-cycle pulse, detected {pulse_count} cycles"
    assert dut.btn_state.value == 1, "btn_state must stay 1 while button is held"
    dut._log.info("Stable press detected with exact 1-cycle edge pulse.")

    # Release button
    dut.btn_in.value = 0
    await ClockCycles(dut.clk, 15)
    assert dut.btn_state.value == 0, "btn_state must return to 0 after release"
    assert dut.btn_pulse.value == 0, "btn_pulse must remain 0 on release"
    dut._log.info("Button release verified.")
