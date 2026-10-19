# ==============================================================================
# File: build.tcl
# Description: Automated Vivado Batch Implementation Script for FPGA MJPEG Player
# Target Board: RealDigital Boolean Board (AMD Spartan-7 XC7S50-CSGA324-1)
# Flow: Synthesis -> Optimization -> Placement -> Physical Opt -> Route -> Bitstream
# Language: Pure Verilog-2001
# Usage: vivado -mode batch -source build.tcl
# ==============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set PROJ_ROOT  $SCRIPT_DIR

if {[info exists env(BUILD_DIR)]} {
    set OUTPUT_DIR [file normalize $env(BUILD_DIR)]
} else {
    set OUTPUT_DIR "$PROJ_ROOT/build_output"
}

set REPORT_DIR "$OUTPUT_DIR/reports"
file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

set PART_NAME "xc7s50csga324-1"
set TOP_NAME  "mjpeg_player_top"

puts "=========================================================================="
puts " Starting Vivado Build Flow for $TOP_NAME on $PART_NAME"
puts " Project Root: $PROJ_ROOT"
puts " Output Dir:   $OUTPUT_DIR"
puts "=========================================================================="

# ------------------------------------------------------------------------------
# 1. Read Design Sources (Pure Verilog-2001)
# ------------------------------------------------------------------------------
puts "\n>> Reading Verilog-2001 RTL Sources..."
set RTL_FILES [list \
    "$PROJ_ROOT/rtl/button_debounce.v" \
    "$PROJ_ROOT/rtl/framebuffer/bram_dual_port.v" \
    "$PROJ_ROOT/rtl/framebuffer/framebuffer_double_buffer.v" \
    "$PROJ_ROOT/rtl/framebuffer/scaler_5x.v" \
    "$PROJ_ROOT/rtl/hdmi/hdmi_timing_gen.v" \
    "$PROJ_ROOT/rtl/hdmi/hdmi_test_pattern.v" \
    "$PROJ_ROOT/rtl/hdmi/tmds_encoder.v" \
    "$PROJ_ROOT/rtl/hdmi/tmds_serializer.v" \
    "$PROJ_ROOT/rtl/hdmi/hdmi_tx_top.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_bit_buffer.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_qtable_mem.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_huffman_lut.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_idct_2d.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_ycbcr_to_rgb.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_decoder_core.v" \
    "$PROJ_ROOT/rtl/jpeg/jpeg_decoder_top.v" \
    "$PROJ_ROOT/rtl/mjpeg/mjpeg_playback_controller.v" \
    "$PROJ_ROOT/rtl/mjpeg/mjpeg_stream_parser.v" \
    "$PROJ_ROOT/rtl/mjpeg/mjpeg_playback_top.v" \
    "$PROJ_ROOT/rtl/qspi/qspi_controller.v" \
    "$PROJ_ROOT/rtl/qspi/qspi_playback_reader.v" \
    "$PROJ_ROOT/rtl/uart/uart_rx.v" \
    "$PROJ_ROOT/rtl/uart/uart_rx_fifo.v" \
    "$PROJ_ROOT/rtl/uart/uart_tx.v" \
    "$PROJ_ROOT/rtl/uart/uart_upload_parser.v" \
    "$PROJ_ROOT/rtl/uart/uart_upload_top.v" \
    "$PROJ_ROOT/rtl/mjpeg_player_top.v" \
]

foreach f $RTL_FILES {
    if {[file exists $f]} {
        read_verilog $f
    } else {
        puts "ERROR: Source file not found: $f"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# 2. Read Physical and Timing Constraints
# ------------------------------------------------------------------------------
puts "\n>> Reading Constraints..."
set XDC_FILE "$PROJ_ROOT/constraints/boolean.xdc"
if {[file exists $XDC_FILE]} {
    read_xdc $XDC_FILE
} else {
    puts "ERROR: Constraints file not found: $XDC_FILE"
    exit 1
}

# ------------------------------------------------------------------------------
# 3. Synthesis
# ------------------------------------------------------------------------------
puts "\n>> Running Synthesis ($TOP_NAME)..."
if {[catch {synth_design -top $TOP_NAME -part $PART_NAME -flatten_hierarchy rebuilt -retiming} err]} {
    puts "ERROR: Synthesis failed: $err"
    exit 1
}

write_checkpoint -force "$OUTPUT_DIR/post_synth.dcp"
report_utilization -file "$REPORT_DIR/post_synth_utilization.rpt"
report_timing_summary -file "$REPORT_DIR/post_synth_timing.rpt"
puts ">> Post-Synthesis Utilization and Timing reports generated."

# ------------------------------------------------------------------------------
# 4. Logic Optimization
# ------------------------------------------------------------------------------
puts "\n>> Running Logic Optimization (opt_design)..."
if {[catch {opt_design -directive Explore} err]} {
    puts "ERROR: opt_design failed: $err"
    exit 1
}

# ------------------------------------------------------------------------------
# 5. Placement
# ------------------------------------------------------------------------------
puts "\n>> Running Placement (place_design)..."
if {[catch {place_design -directive Explore} err]} {
    puts "ERROR: place_design failed: $err"
    exit 1
}

write_checkpoint -force "$OUTPUT_DIR/post_place.dcp"
report_clock_utilization -file "$REPORT_DIR/post_place_clock_utilization.rpt"

# ------------------------------------------------------------------------------
# 6. Physical Logic Optimization
# ------------------------------------------------------------------------------
puts "\n>> Running Physical Optimization (phys_opt_design)..."
catch {phys_opt_design -directive Explore}

# ------------------------------------------------------------------------------
# 7. Routing
# ------------------------------------------------------------------------------
puts "\n>> Running Routing (route_design)..."
if {[catch {route_design -directive Explore} err]} {
    puts "ERROR: route_design failed: $err"
    exit 1
}

# Check setup timing slack
set post_route_slack [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts ">> Post-Route Setup Slack: $post_route_slack ns"
if {$post_route_slack < 0} {
    puts ">> Running Post-Route Physical Optimization to close timing..."
    catch {phys_opt_design -directive Explore}
    catch {route_design -directive Explore}
}

write_checkpoint -force "$OUTPUT_DIR/post_route.dcp"

# ------------------------------------------------------------------------------
# 8. Detailed Timing, Utilization, and DRC Reporting
# ------------------------------------------------------------------------------
puts "\n>> Generating Post-Route Reports..."
report_timing_summary -max_paths 10 -report_unconstrained -file "$REPORT_DIR/timing_summary.rpt"
report_utilization -hierarchical -file "$REPORT_DIR/utilization_hierarchical.rpt"
report_utilization -file "$REPORT_DIR/utilization.rpt"
report_power -file "$REPORT_DIR/power.rpt"
report_drc -file "$REPORT_DIR/drc.rpt"

# ------------------------------------------------------------------------------
# 9. Bitstream Generation
# ------------------------------------------------------------------------------
puts "\n>> Generating Bitstream..."
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set BITSTREAM_FILE "$OUTPUT_DIR/${TOP_NAME}.bit"
if {[catch {write_bitstream -force -bin_file $BITSTREAM_FILE} err]} {
    puts "ERROR: Bitstream generation failed: $err"
    exit 1
}

puts "\n=========================================================================="
puts " BUILD COMPLETE!"
puts " Bitstream: $BITSTREAM_FILE"
puts " Reports:   $REPORT_DIR"
puts "=========================================================================="
