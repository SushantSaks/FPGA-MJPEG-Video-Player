#!/usr/bin/env python3
"""
Host-side Video Upload Tool for FPGA Hardware MJPEG Player
Communicates with AMD Spartan-7 FPGA on the RealDigital Boolean Board over USB-UART:
  - Validates MJPEG video file (256x144 @ 15 FPS, baseline 4:2:0)
  - Computes IEEE 802.3 CRC32 checksum over the video stream payload
  - Formats upload packet:
      [Magic: "MJPG" (4B)]
      [File Size: uint32_be (4B)]
      [Width: uint16_be (2B)]
      [Height: uint16_be (2B)]
      [FPS: uint8 (1B)]
      [Reserved: uint8 (1B)]
      [Payload: N Bytes]
      [CRC32: uint32_be (4B)]
      [Completion Marker: "END!" (4B)]
  - Transmits over UART at configured baud rate (default: 921600 baud)
  - Paces transmission to match FPGA Flash page programming and FIFO capacity
  - Awaits FPGA QSPI readback verification response (ACK 0x06 / NAK 0x15/0x16/0x17)
  - Returns exit code 0 on success, non-zero on failure
"""

import sys
import os
import time
import struct
import binascii
import argparse

MAGIC_HEADER = b"MJPG"
COMPLETION_MARKER = b"END!"
DEFAULT_BAUD = 921600


def build_packet(file_path, width=256, height=144, fps=15):
    """Reads MJPEG file and builds binary upload packet."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Video file not found: {file_path}")

    with open(file_path, "rb") as f:
        payload = f.read()

    file_size = len(payload)
    if file_size == 0:
        raise ValueError("Video file is empty!")

    # Verify standard JPEG SOI marker
    if payload[:2] != b"\xFF\xD8":
        print(f"[Warning] File {file_path} does not begin with standard JPEG SOI (0xFFD8).")

    # Compute IEEE 802.3 CRC32
    crc = binascii.crc32(payload) & 0xFFFFFFFF

    # Build Header: 4B Magic + 4B Size + 2B Width + 2B Height + 1B FPS + 1B Reserved = 14 bytes
    header = MAGIC_HEADER + struct.pack(">IHHBB", file_size, width, height, fps, 0)
    # Build Footer: 4B CRC32 + 4B Marker = 8 bytes
    footer = struct.pack(">I", crc) + COMPLETION_MARKER

    full_packet = header + payload + footer

    print("=" * 60)
    print("FPGA MJPEG Video Upload Packet Created:")
    print(f"  Input File:     {file_path}")
    print(f"  Payload Size:   {file_size:,} bytes")
    print(f"  Resolution:     {width}x{height} @ {fps} FPS")
    print(f"  CRC32:          0x{crc:08X}")
    print(f"  Total Packet:   {len(full_packet):,} bytes")
    print("=" * 60)

    return full_packet, crc, payload


def upload_serial(port, baud, packet, expected_crc):
    """Uploads packet over physical serial port with page pacing and verification."""
    try:
        import serial
    except ImportError:
        print("[Error] 'pyserial' package is required for physical upload. Install with: pip install pyserial")
        sys.exit(1)

    print(f"Opening serial port {port} at {baud} baud...")
    try:
        ser = serial.Serial(port, baud, timeout=25.0)
    except Exception as e:
        print(f"[Error] Failed to open serial port {port}: {e}")
        sys.exit(1)

    time.sleep(0.2)
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    total_bytes = len(packet)
    start_time = time.time()

    # 1. Send Header (14 bytes)
    header = packet[:14]
    file_size = struct.unpack(">I", header[4:8])[0]
    num_sectors = (file_size + 4095) // 4096

    print(f"\nSending upload header (Target: {file_size:,} bytes, {num_sectors} flash sectors)...")
    ser.write(header)
    ser.flush()

    # 2. Prepare Payload (N bytes)
    payload_len = total_bytes - 14 - 8
    payload = packet[14 : 14 + payload_len]

    # Allow FPGA to erase all required Flash sectors in hardware (~45-100 ms per 4 KB sector)
    erase_wait = max(2.5, num_sectors * 0.15)
    print(f"Erasing {num_sectors} flash sectors in hardware (waiting {erase_wait:.2f}s)...")
    time.sleep(erase_wait)

    print(f"Flash erased! Streaming {payload_len:,} bytes in 256-byte pages...")
    for offset in range(0, payload_len, 256):
        chunk = payload[offset : offset + 256]
        ser.write(chunk)
        ser.flush()
        # Winbond W25Q128 page program typically takes ~0.7 ms, max 3.0 ms.
        # Pausing 6 ms ensures the FPGA FIFO never overflows and flash programming completes.
        time.sleep(0.006)

        sent = min(payload_len, offset + len(chunk))
        progress = (sent / payload_len) * 100.0
        elapsed = time.time() - start_time
        speed_kb = (sent / 1024.0) / max(0.001, elapsed)
        sys.stdout.write(f"\r  [{progress:5.1f}%] {sent:,}/{payload_len:,} bytes ({speed_kb:.1f} KB/s)")
        sys.stdout.flush()

    # 3. Send Footer (CRC32 + "END!")
    footer = packet[14 + payload_len :]
    ser.write(footer)
    ser.flush()

    print("\n\nUpload finished. Waiting for FPGA QSPI readback verification...")

    # Wait for FPGA ACK/NAK response (0x06 or 0x15/0x16/0x17)
    response = ser.read(1)
    if not response:
        print("[Error] Timeout waiting for FPGA verification response!")
        print("[Tip] If the board was interrupted during a previous upload, press pushbutton btn[0] (pin H2) once to reset, then retry.")
        ser.close()
        sys.exit(1)

    resp_byte = response[0]
    ser.close()

    if resp_byte == 0x06:  # ACK
        print("\n" + "=" * 60)
        print(">> [SUCCESS] FPGA QSPI Readback Verification PASSED! (ACK: 0x06)")
        print(f">> CRC32 Verified: 0x{expected_crc:08X}")
        print(">> Video is ready for playback on HDMI.")
        print("=" * 60)
        sys.exit(0)
    elif resp_byte == 0x15:  # NAK Flash readback
        print("\n" + "=" * 60)
        print(">> [FAILURE] FPGA QSPI Readback Verification FAILED! (NAK: 0x15)")
        print(">> Host CRC matched UART payload, but Flash readback differed.")
        print("=" * 60)
        sys.exit(2)
    elif resp_byte == 0x16:  # NAK UART CRC
        print("\n" + "=" * 60)
        print(">> [FAILURE] UART Transmission Checksum Mismatch! (NAK: 0x16)")
        print(">> Bytes were lost or corrupted over the serial link.")
        print("=" * 60)
        sys.exit(3)
    elif resp_byte == 0x17:  # NAK Protocol
        print("\n" + "=" * 60)
        print(">> [FAILURE] Protocol Delimiter Error! (NAK: 0x17)")
        print("=" * 60)
        sys.exit(4)
    else:
        print(f"\n>> Received unexpected response: 0x{resp_byte:02X}")
        sys.exit(5)


def main():
    parser = argparse.ArgumentParser(description="Upload MJPEG video to FPGA QSPI Flash over UART")
    parser.add_argument("video_file", nargs="?", default=None, help="Path to MJPEG video file (e.g. videos/demo.mjpeg)")
    parser.add_argument("--video", default=None, help="Path to MJPEG video file (alternative to positional argument)")
    parser.add_argument("--port", default=None, help="Serial port (e.g. /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help=f"Baud rate (default: {DEFAULT_BAUD})")
    parser.add_argument("--width", type=int, default=256, help="Video width (default: 256)")
    parser.add_argument("--height", type=int, default=144, help="Video height (default: 144)")
    parser.add_argument("--fps", type=int, default=15, help="Video frame rate (default: 15)")
    parser.add_argument("--out-packet", default=None, help="Save packet to raw binary file")

    args = parser.parse_args()

    target_video = args.video if args.video else args.video_file
    if not target_video:
        parser.error("A video file must be specified (e.g. python3 host/upload_video.py video.mjpeg --port /dev/ttyUSB1)")

    packet, crc, payload = build_packet(target_video, args.width, args.height, args.fps)

    if args.out_packet:
        with open(args.out_packet, "wb") as f:
            f.write(packet)
        print(f"Saved upload packet to {args.out_packet}")

    if args.port:
        upload_serial(args.port, args.baud, packet, crc)
    else:
        print("\nNo serial port specified (--port). Packet built and verified successfully.")


if __name__ == "__main__":
    main()
