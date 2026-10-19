# ==============================================================================
# Constraints File for AMD Spartan-7 XC7S50-CSGA324-1
# Board: RealDigital Boolean Board
# Project: FPGA Hardware MJPEG Video Player (1280x720 @ 60 Hz HDMI)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Primary Clock (100 MHz Onboard Oscillator)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports { clk_100mhz }];

# ------------------------------------------------------------------------------
# 2. Pushbuttons & Reset
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { rst_btn_n }];      # Btn Down (Active-Low Reset)
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { btn_play_pause }];  # Btn Up (Play/Pause)
set_property -dict { PACKAGE_PIN J1    IOSTANDARD LVCMOS33 } [get_ports { btn_restart }];     # Btn Right (Restart / Loop)

# ------------------------------------------------------------------------------
# 2b. Slide Switches
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]; # SW0: 0=Color Bars, 1=Live Video
set_property -dict { PACKAGE_PIN U2    IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]; # SW1: Reserved / Pattern Select

# ------------------------------------------------------------------------------
# 3. 16 User Status LEDs
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { led[0] }];  # Upload Active
set_property -dict { PACKAGE_PIN G2    IOSTANDARD LVCMOS33 } [get_ports { led[1] }];  # Upload Success (CRC Verified)
set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { led[2] }];  # Video Playing
set_property -dict { PACKAGE_PIN F2    IOSTANDARD LVCMOS33 } [get_ports { led[3] }];  # Video Paused
set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { led[4] }];  # Frame Num [0]
set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { led[5] }];  # Frame Num [1]
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { led[6] }];  # Frame Num [2]
set_property -dict { PACKAGE_PIN E5    IOSTANDARD LVCMOS33 } [get_ports { led[7] }];  # Frame Num [3]
set_property -dict { PACKAGE_PIN E6    IOSTANDARD LVCMOS33 } [get_ports { led[8] }];  # Frame Num [4]
set_property -dict { PACKAGE_PIN C3    IOSTANDARD LVCMOS33 } [get_ports { led[9] }];  # Frame Num [5]
set_property -dict { PACKAGE_PIN B2    IOSTANDARD LVCMOS33 } [get_ports { led[10] }]; # Frame Num [6]
set_property -dict { PACKAGE_PIN A2    IOSTANDARD LVCMOS33 } [get_ports { led[11] }]; # Frame Num [7]
set_property -dict { PACKAGE_PIN B3    IOSTANDARD LVCMOS33 } [get_ports { led[12] }]; # Decoded Frames [0]
set_property -dict { PACKAGE_PIN A3    IOSTANDARD LVCMOS33 } [get_ports { led[13] }]; # Decoded Frames [1]
set_property -dict { PACKAGE_PIN B4    IOSTANDARD LVCMOS33 } [get_ports { led[14] }]; # Decoded Frames [2]
set_property -dict { PACKAGE_PIN A4    IOSTANDARD LVCMOS33 } [get_ports { led[15] }]; # Decoded Frames [3]

# ------------------------------------------------------------------------------
# 4. USB-UART Bridge Interface (921,600 Baud)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { uart_rx_pin }];     # FPGA RX (From PC)
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { uart_tx_pin }];     # FPGA TX (To PC - Primary Pin)
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { uart_tx_alt_pin }]; # FPGA TX (To PC - Redundant Pin)

# ------------------------------------------------------------------------------
# 5. Onboard 16 MB Winbond W25Q128 QSPI Flash Memory
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { qspi_cs_n }];
# Note: SCK (CCLK) is driven via internal STARTUPE2 primitive on Spartan-7
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports { qspi_io0_do }]; # MOSI / IO0
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { qspi_io1_di }]; # MISO / IO1
set_property -dict { PACKAGE_PIN L14   IOSTANDARD LVCMOS33 } [get_ports { qspi_io2_do }]; # WP#  / IO2
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports { qspi_io3_do }]; # HOLD#/ IO3

# ------------------------------------------------------------------------------
# 6. HDMI Transmitter Output (1280x720 @ 60 Hz CEA-861, TMDS 3.3V)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R14   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_p }];  # Clock + (P-side: R14)
set_property -dict { PACKAGE_PIN T14   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_clk_n }];  # Clock - (N-side: T14)
set_property -dict { PACKAGE_PIN R15   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_data_p[0] }]; # D0 (Blue) + (P-side: R15)
set_property -dict { PACKAGE_PIN T15   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_data_n[0] }]; # D0 (Blue) - (N-side: T15)
set_property -dict { PACKAGE_PIN R16   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_data_p[1] }]; # D1 (Green) + (P-side: R16)
set_property -dict { PACKAGE_PIN R17   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_data_n[1] }]; # D1 (Green) - (N-side: R17)
set_property -dict { PACKAGE_PIN N15   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_data_p[2] }]; # D2 (Red) + (P-side: N15)
set_property -dict { PACKAGE_PIN P16   IOSTANDARD TMDS_33 } [get_ports { hdmi_tx_data_n[2] }]; # D2 (Red) - (N-side: P16)

# ------------------------------------------------------------------------------
# 7. Configuration & Bitstream Generation Settings
# ------------------------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# ------------------------------------------------------------------------------
# 8. Clock Domain Crossing (CDC) & Timing Constraints
# ------------------------------------------------------------------------------
# Primary 100 MHz clock and MMCM generated pixel clocks are asynchronous
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk_pin] \
    -group [get_clocks -include_generated_clocks {clk_pixel_unbuf clk_pixel_5x_unbuf clk_fb}]

# TMDS serializer multicycle path (74.25 MHz parallel to 371.25 MHz serial domain)
set_multicycle_path 2 -setup -from [get_clocks clk_pixel_unbuf] -to [get_clocks clk_pixel_5x_unbuf]
set_multicycle_path 1 -hold  -from [get_clocks clk_pixel_unbuf] -to [get_clocks clk_pixel_5x_unbuf]

# TMDS toggle CDC false path
set_false_path -to [get_cells -hier -filter {NAME =~ *toggle_sync_reg* && IS_SEQUENTIAL}]
