"""
Cocotb Testbench: Baseline JPEG Annex K Huffman Variable-Length Decoder LUT
Module: jpeg_huffman_lut.v

Verifies:
1. ISO/IEC 10918-1 Annex K Table K.3 (DC Luminance)
2. ISO/IEC 10918-1 Annex K Table K.4 (DC Chrominance)
3. Table K.5 / K.6 AC End-Of-Block (EOB) and Zero-Run-Length (ZRL) codes
4. Prefix invariance: trailing 'don't care' bits in bit_window do not corrupt prefix decoding
"""

import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def test_dc_luminance_table(dut):
    """Test 1: Verify all 12 standard DC Luminance Huffman codewords."""
    dut.is_chroma.value = 0
    dut.is_ac.value = 0

    # (prefix_bits, prefix_len, expected_symbol)
    dc_lum_table = [
        ("00", 2, 0x00),
        ("010", 3, 0x01),
        ("011", 3, 0x02),
        ("100", 3, 0x03),
        ("101", 3, 0x04),
        ("110", 3, 0x05),
        ("1110", 4, 0x06),
        ("11110", 5, 0x07),
        ("111110", 6, 0x08),
        ("1111110", 7, 0x09),
        ("11111110", 8, 0x0A),
        ("111111110", 9, 0x0B),
    ]

    for prefix, expected_len, expected_sym in dc_lum_table:
        # Align prefix to MSB of 16-bit window, fill remaining bits with 0
        bit_str = prefix.ljust(16, "0")
        dut.bit_window.value = int(bit_str, 2)
        await Timer(1, units="ns")

        actual_len = int(dut.code_len.value)
        actual_sym = int(dut.symbol.value)

        assert actual_len == expected_len, (
            f"DC Lum {prefix} length mismatch: expected {expected_len}, got {actual_len}"
        )
        assert actual_sym == expected_sym, (
            f"DC Lum {prefix} symbol mismatch: expected 0x{expected_sym:02X}, got 0x{actual_sym:02X}"
        )

    dut._log.info("All 12 DC Luminance codewords decoded correctly.")


@cocotb.test()
async def test_dc_chrominance_table(dut):
    """Test 2: Verify all 12 standard DC Chrominance Huffman codewords."""
    dut.is_chroma.value = 1
    dut.is_ac.value = 0

    dc_chroma_table = [
        ("00", 2, 0x00),
        ("01", 2, 0x01),
        ("10", 2, 0x02),
        ("110", 3, 0x03),
        ("1110", 4, 0x04),
        ("11110", 5, 0x05),
        ("111110", 6, 0x06),
        ("1111110", 7, 0x07),
        ("11111110", 8, 0x08),
        ("111111110", 9, 0x09),
        ("1111111110", 10, 0x0A),
        ("11111111110", 11, 0x0B),
    ]

    for prefix, expected_len, expected_sym in dc_chroma_table:
        bit_str = prefix.ljust(16, "0")
        dut.bit_window.value = int(bit_str, 2)
        await Timer(1, units="ns")

        actual_len = int(dut.code_len.value)
        actual_sym = int(dut.symbol.value)

        assert actual_len == expected_len, (
            f"DC Chroma {prefix} len mismatch: expected {expected_len}, got {actual_len}"
        )
        assert actual_sym == expected_sym, (
            f"DC Chroma {prefix} symbol mismatch: expected 0x{expected_sym:02X}, got 0x{actual_sym:02X}"
        )

    dut._log.info("All 12 DC Chrominance codewords decoded correctly.")


@cocotb.test()
async def test_ac_markers_and_prefix_invariance(dut):
    """Test 3: Verify AC EOB/ZRL markers and test prefix robustness across random suffixes."""
    # AC Luminance EOB is 1010 (len 4, symbol 0x00)
    dut.is_chroma.value = 0
    dut.is_ac.value = 1

    # Vary the remaining 12 bits to ensure prefix isolation
    for suffix in [0x000, 0xFFF, 0x555, 0xAAA, 0x123]:
        window_val = (0b1010 << 12) | suffix
        dut.bit_window.value = window_val
        await Timer(1, units="ns")

        assert dut.code_len.value == 4, f"AC Lum EOB length must be 4 (suffix=0x{suffix:03X})"
        assert dut.symbol.value == 0x00, f"AC Lum EOB symbol must be 0x00 (suffix=0x{suffix:03X})"

    # AC Luminance ZRL (16 zeros) is 11111111001 (len 11, symbol 0xF0)
    for suffix in [0x00, 0x1F, 0x10, 0x0A]:
        window_val = (0b11111111001 << 5) | suffix
        dut.bit_window.value = window_val
        await Timer(1, units="ns")

        assert dut.code_len.value == 11, "AC Lum ZRL length must be 11"
        assert dut.symbol.value == 0xF0, "AC Lum ZRL symbol must be 0xF0"

    # AC Chrominance EOB is 00 (len 2, symbol 0x00)
    dut.is_chroma.value = 1
    dut.is_ac.value = 1
    dut.bit_window.value = 0b0011111111111111
    await Timer(1, units="ns")
    assert dut.code_len.value == 2, "AC Chroma EOB length must be 2"
    assert dut.symbol.value == 0x00, "AC Chroma EOB symbol must be 0x00"

    dut._log.info("AC EOB and ZRL decoding and prefix invariance verified.")
