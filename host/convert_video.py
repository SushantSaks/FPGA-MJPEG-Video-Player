#!/usr/bin/env python3
"""
Video to FPGA MJPEG Converter
Converts arbitrary video files (MP4, MKV, AVI, WebM, etc.) into the exact
hardware-compliant Motion-JPEG stream expected by the FPGA player:
  - Resolution: 256x144 pixels (matches 144 KB dual-buffer BRAM framebuffer)
  - Framerate:  15 FPS (matches 60 Hz / 4 atomic VSYNC buffer swap cadence)
  - Color:      Baseline JPEG (SOF0), YUV 4:2:0 subsampling, standard ITU-T Annex K Huffman
  - Container:  Raw concatenated JPEG stream (0xFFD8...0xFFD9) without wrapper headers
  - Max Size:   <= 12 MB (fits inside Winbond W25Q128 Flash storage space)
"""

import os
import sys
import argparse
import subprocess
import shutil
import io
import time

try:
    from PIL import Image
except ImportError:
    print("[Error] Pillow is required: run 'pip install pillow'")
    sys.exit(1)

FPGA_WIDTH = 256
FPGA_HEIGHT = 144
DEFAULT_FPS = 15
DEFAULT_QUALITY = 80
FLASH_MAX_BYTES = 12 * 1024 * 1024  # 12 MB maximum video space in W25Q128


def check_ffmpeg():
    """Verify ffmpeg is installed."""
    if not shutil.which("ffmpeg"):
        print("[Error] 'ffmpeg' is not found in system PATH. Install with: sudo apt install ffmpeg")
        sys.exit(1)


def convert_video(input_path, output_path, fps=15, quality=80, fit_mode="pad",
                  duration=None, max_frames=None):
    """
    Decodes video with ffmpeg and re-encodes each frame as standard baseline
    4:2:0 JPEG with Pillow, streaming directly to output .mjpeg.
    """
    check_ffmpeg()

    if not os.path.exists(input_path):
        print(f"[Error] Input video file '{input_path}' not found!")
        sys.exit(1)

    print("=" * 65)
    print("FPGA MJPEG Video Converter")
    print(f"  Input Video:      {input_path}")
    print(f"  Target Spec:      {FPGA_WIDTH}x{FPGA_HEIGHT} @ {fps} FPS (Baseline 4:2:0)")
    print(f"  JPEG Quality:     {quality}")
    print(f"  Aspect Ratio Fit: {fit_mode}")
    print("=" * 65)

    # Build ffmpeg video filter for scaling / letterboxing
    if fit_mode == "pad":
        vf = f"scale={FPGA_WIDTH}:{FPGA_HEIGHT}:force_original_aspect_ratio=decrease,pad={FPGA_WIDTH}:{FPGA_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black"
    elif fit_mode == "crop":
        vf = f"scale={FPGA_WIDTH}:{FPGA_HEIGHT}:force_original_aspect_ratio=increase,crop={FPGA_WIDTH}:{FPGA_HEIGHT}"
    else:  # "stretch"
        vf = f"scale={FPGA_WIDTH}:{FPGA_HEIGHT}"

    ffmpeg_cmd = [
        "ffmpeg", "-y", "-v", "error",
        "-i", input_path
    ]

    if duration:
        ffmpeg_cmd.extend(["-t", str(duration)])

    ffmpeg_cmd.extend([
        "-vf", vf,
        "-r", str(fps),
        "-pix_fmt", "rgb24",
        "-f", "rawvideo",
        "-"
    ])

    print("\nExtracting and re-encoding video frames...")
    proc = subprocess.Popen(ffmpeg_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    frame_bytes_len = FPGA_WIDTH * FPGA_HEIGHT * 3
    frame_count = 0
    total_mjpeg_bytes = 0
    t0 = time.time()

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    with open(output_path, "wb") as out_f:
        while True:
            raw_rgb = proc.stdout.read(frame_bytes_len)
            if len(raw_rgb) < frame_bytes_len:
                break

            # Create PIL image from raw RGB buffer
            img = Image.frombytes("RGB", (FPGA_WIDTH, FPGA_HEIGHT), raw_rgb)

            # Save as standard baseline 4:2:0 JPEG with standard Annex K tables
            buf = io.BytesIO()
            img.save(
                buf,
                format="JPEG",
                quality=quality,
                subsampling=2,   # 4:2:0 chroma subsampling (essential for FPGA hardware decoder)
                optimize=False   # Guarantees standard ITU-T Annex K Huffman tables
            )
            jpeg_data = buf.getvalue()

            out_f.write(jpeg_data)
            total_mjpeg_bytes += len(jpeg_data)
            frame_count += 1

            elapsed = max(0.001, time.time() - t0)
            fps_proc = frame_count / elapsed
            sys.stdout.write(f"\r  Frames encoded: {frame_count:4d} | Size: {total_mjpeg_bytes / 1024.0:6.1f} KB ({fps_proc:4.1f} fps)")
            sys.stdout.flush()

            if max_frames and frame_count >= max_frames:
                break

    proc.stdout.close()
    proc.wait()

    print("\n")
    if frame_count == 0:
        print("[Error] No frames were decoded from the input video!")
        sys.exit(1)

    avg_frame_size = total_mjpeg_bytes // frame_count
    playback_duration = frame_count / float(fps)
    sectors = (total_mjpeg_bytes + 4095) // 4096
    flash_pct = (total_mjpeg_bytes / float(FLASH_MAX_BYTES)) * 100.0

    print("=" * 65)
    print("Conversion Complete!")
    print(f"  Output File:        {output_path}")
    print(f"  Total Frames:       {frame_count:,} frames ({playback_duration:.2f} seconds)")
    print(f"  Total File Size:    {total_mjpeg_bytes:,} bytes ({total_mjpeg_bytes / (1024*1024):.2f} MB)")
    print(f"  Average Frame Size: {avg_frame_size:,} bytes")
    print(f"  Flash Memory Use:   {sectors} sectors ({flash_pct:.1f}% of 12 MB Flash)")
    print("=" * 65)

    if total_mjpeg_bytes > FLASH_MAX_BYTES:
        print(f"\n[Warning] File size ({total_mjpeg_bytes:,} B) exceeds 12 MB Flash capacity!")
        print("Reduce video duration using '--duration <seconds>' or '--quality <1-100>'.")

    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Convert video (MP4, MKV, AVI, etc.) to FPGA-compatible MJPEG stream"
    )
    parser.add_argument("input_video", help="Path to input video file")
    parser.add_argument("-o", "--output", default="output.mjpeg", help="Output MJPEG file path (default: output.mjpeg)")
    parser.add_argument("--fps", type=int, default=DEFAULT_FPS, help=f"Target playback FPS (default: {DEFAULT_FPS})")
    parser.add_argument("--quality", type=int, default=DEFAULT_QUALITY, help=f"JPEG quality 1-100 (default: {DEFAULT_QUALITY})")
    parser.add_argument("--fit", choices=["pad", "crop", "stretch"], default="pad",
                        help="Aspect ratio fit mode: 'pad' (letterbox), 'crop' (fill), 'stretch'")
    parser.add_argument("-d", "--duration", type=float, default=None, help="Limit video duration in seconds")
    parser.add_argument("-n", "--max-frames", type=int, default=None, help="Limit maximum number of frames")
    parser.add_argument("--upload", action="store_true", help="Automatically upload video to FPGA after conversion")
    parser.add_argument("--port", default="/dev/ttyUSB1", help="Serial port for FPGA upload (default: /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=921600, help="Baud rate for upload (default: 921600)")

    args = parser.parse_args()

    out_file = convert_video(
        input_path=args.input_video,
        output_path=args.output,
        fps=args.fps,
        quality=args.quality,
        fit_mode=args.fit,
        duration=args.duration,
        max_frames=args.max_frames
    )

    if args.upload:
        print(f"\nProceeding to FPGA Upload over {args.port} at {args.baud} baud...")
        script_dir = os.path.dirname(os.path.abspath(__file__))
        upload_script = os.path.join(script_dir, "upload_video.py")
        upload_cmd = [
            sys.executable, upload_script, out_file,
            "--port", args.port,
            "--baud", str(args.baud)
        ]
        res = subprocess.call(upload_cmd)
        if res != 0:
            sys.exit(res)


if __name__ == "__main__":
    main()
