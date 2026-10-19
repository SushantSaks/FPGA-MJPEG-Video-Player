"""
Cocotb Testbench: Motion-JPEG Stream Delimiter & Boundary Detector
Module: mjpeg_stream_parser.v

Verifies:
1. Pre-frame junk byte filtering during SOI seek (0xFF 0xD8)
2. Streaming payload passthrough with accurate byte counting
3. EOI (0xFF 0xD9) frame completion pulse and frame_count increment
4. Downstream backpressure handling (out_ready throttling without data loss)
5. Asynchronous stream abort / seek reset behavior
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 10.0  # 100 MHz


@cocotb.test()
async def test_parser_reset(dut):
    """Test 1: Verify reset conditions and initial idle state."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start_frame.value = 0
    dut.abort_stream.value = 0
    dut.in_valid.value = 0
    dut.in_data.value = 0
    dut.out_ready.value = 1

    await ClockCycles(dut.clk, 5)
    assert dut.frame_active.value == 0, "frame_active must be 0 in reset"
    assert dut.frame_complete.value == 0, "frame_complete must be 0 in reset"
    assert dut.frame_count.value == 0, "frame_count must be 0 in reset"
    assert dut.out_valid.value == 0, "out_valid must be 0 in reset"

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    assert dut.in_ready.value == 0, "in_ready must be 0 while in ST_IDLE before start_frame"


@cocotb.test()
async def test_frame_detection_and_streaming(dut):
    """Test 2: Stream JPEG frame preceded by noise, verify SOI/EOI parsing & byte count."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.start_frame.value = 0
    dut.abort_stream.value = 0
    dut.in_valid.value = 0
    dut.in_data.value = 0
    dut.out_ready.value = 1
    await ClockCycles(dut.clk, 5)

    # Trigger frame decode
    await RisingEdge(dut.clk)
    dut.start_frame.value = 1
    await RisingEdge(dut.clk)
    dut.start_frame.value = 0

    # Stream containing:
    # 1. Inter-frame noise (0x00, 0xFF, 0x11)
    # 2. SOI (0xFF, 0xD8)
    # 3. Payload (0xFF, 0xDB, 0x00, 0x43, 0x12, 0x34)
    # 4. EOI (0xFF, 0xD9)
    noise_bytes = [0x00, 0xFF, 0x11, 0x22]
    jpeg_payload = [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x12, 0x34, 0xFF, 0xD9]
    input_stream = noise_bytes + jpeg_payload

    received_bytes = []

    # Monitor coroutine collecting downstream bytes
    async def output_collector():
        while True:
            await RisingEdge(dut.clk)
            if dut.out_valid.value and dut.out_ready.value:
                received_bytes.append(int(dut.out_data.value))
                if len(received_bytes) == len(jpeg_payload):
                    break

    collector_task = cocotb.start_soon(output_collector())

    async def send_byte(b: int):
        dut.in_data.value = b
        dut.in_valid.value = 1
        while True:
            await RisingEdge(dut.clk)
            if dut.in_ready.value:
                break
        dut.in_valid.value = 0

    # Feed input stream with handshake
    for byte in input_stream:
        await send_byte(byte)

    await collector_task
    assert received_bytes == jpeg_payload, (
        f"Filtered output payload mismatch: expected {jpeg_payload}, got {received_bytes}"
    )

    # Verify frame counters and status
    await ClockCycles(dut.clk, 2)
    assert dut.frame_count.value == 1, f"Expected frame_count=1, got {int(dut.frame_count.value)}"
    assert dut.frame_byte_len.value == len(jpeg_payload), (
        f"Expected frame_byte_len={len(jpeg_payload)}, got {int(dut.frame_byte_len.value)}"
    )
    assert dut.frame_active.value == 0, "frame_active should return to 0 after EOI"
    dut._log.info(f"Extracted {len(received_bytes)} byte frame cleanly.")


@cocotb.test()
async def test_downstream_backpressure(dut):
    """Test 3: Throttled downstream consumer (out_ready toggling) preserves all frame data."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.start_frame.value = 1
    await RisingEdge(dut.clk)
    dut.start_frame.value = 0

    frame = [0xFF, 0xD8, 0x10, 0x20, 0x30, 0x40, 0xFF, 0xD9]
    received = []

    # Downstream consumer toggling out_ready every 2 cycles
    async def throttled_consumer():
        while len(received) < len(frame):
            await RisingEdge(dut.clk)
            dut.out_ready.value = 0
            await RisingEdge(dut.clk)
            dut.out_ready.value = 1
            if dut.out_valid.value:
                received.append(int(dut.out_data.value))

    consumer_task = cocotb.start_soon(throttled_consumer())

    for b in frame:
        dut.in_data.value = b
        dut.in_valid.value = 1
        while True:
            await RisingEdge(dut.clk)
            if dut.in_ready.value:
                break

    dut.in_valid.value = 0
    await consumer_task
    assert received == frame, f"Throttled transfer mismatch: expected {frame}, got {received}"
    dut._log.info("Backpressure flow control verified under throttling.")


@cocotb.test()
async def test_stream_abort(dut):
    """Test 4: Abort active stream mid-frame and verify clean return to idle."""
    clock = Clock(dut.clk, CLK_PERIOD_NS, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 1
    dut.start_frame.value = 1
    await RisingEdge(dut.clk)
    dut.start_frame.value = 0

    # Send SOI
    for b in [0xFF, 0xD8, 0x01, 0x02]:
        dut.in_data.value = b
        dut.in_valid.value = 1
        while True:
            await RisingEdge(dut.clk)
            if dut.in_ready.value:
                break
    dut.in_valid.value = 0

    assert dut.frame_active.value == 1, "frame_active should be high during active stream"

    # Pulse abort
    await RisingEdge(dut.clk)
    dut.abort_stream.value = 1
    await RisingEdge(dut.clk)
    dut.abort_stream.value = 0
    await ClockCycles(dut.clk, 2)

    assert dut.frame_active.value == 0, "frame_active must clear immediately on abort"
    dut._log.info("Stream abort verified.")
