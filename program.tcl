# ==============================================================================
# File: program.tcl
# Description: Automated Hardware Manager script to program the bitstream to
#              the RealDigital Boolean Board (Spartan-7 XC7S50) via JTAG.
# Usage: vivado -mode batch -source program.tcl
# ==============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set PROJ_ROOT  $SCRIPT_DIR

if {[info exists env(BUILD_DIR)]} {
    set BIT_FILE [file normalize "$env(BUILD_DIR)/mjpeg_player_top.bit"]
} else {
    set BIT_FILE "$PROJ_ROOT/build_output/mjpeg_player_top.bit"
}

if {![file exists $BIT_FILE]} {
    puts "ERROR: Bitstream file not found at: $BIT_FILE"
    puts "Please run build.tcl first (vivado -mode batch -source build.tcl)."
    exit 1
}

puts "=========================================================================="
puts " Connecting to Hardware Server and Programming Spartan-7 XC7S50..."
puts " Bitstream: $BIT_FILE"
puts "=========================================================================="

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices xc7s50_*] 0]
if {$device eq ""} {
    puts "ERROR: No XC7S50 target device detected on JTAG chain!"
    disconnect_hw_server
    close_hw_manager
    exit 1
}

current_hw_device $device
refresh_hw_device [current_hw_device]

set_property PROGRAM.FILE $BIT_FILE [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

puts "\n=========================================================================="
puts " FPGA PROGRAMMING SUCCESSFUL!"
puts " Boolean Board is now running the Verilog-2001 MJPEG Video Player pipeline."
puts "=========================================================================="

close_hw_target
disconnect_hw_server
close_hw_manager
