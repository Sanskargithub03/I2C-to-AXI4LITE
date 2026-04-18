# =============================================================================
# Constraints File: i2c_to_axi4lite.xdc
# Target Board: Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
# Description: Pin assignments for I2C-to-AXI4-Lite Bridge FPGA demo
# =============================================================================

# ---- Clock (100 MHz onboard oscillator) ----
set_property PACKAGE_PIN E3      [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# ---- Active-low Reset (Button BTNC) ----
set_property PACKAGE_PIN N17     [get_ports rst_n]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_n]

# ---- I2C Signals (PMOD JA connector) ----
# JA1 = SCL,  JA2 = SDA
set_property PACKAGE_PIN C17     [get_ports scl_i]
set_property IOSTANDARD  LVCMOS33 [get_ports scl_i]

set_property PACKAGE_PIN D18     [get_ports sda_i]
set_property IOSTANDARD  LVCMOS33 [get_ports sda_i]

set_property PACKAGE_PIN E18     [get_ports sda_o]
set_property IOSTANDARD  LVCMOS33 [get_ports sda_o]

set_property PACKAGE_PIN G17     [get_ports sda_oe]
set_property IOSTANDARD  LVCMOS33 [get_ports sda_oe]

# ---- Debug LEDs ----
# LED[0] = AXI write in progress, LED[1] = AXI read in progress
# LED[2] = AXI error, LED[3] = DUT ready
# (Connect in wrapper if needed)

# ---- Timing constraints ----
# I2C is asynchronous input - treat as false path for timing
set_false_path -from [get_ports scl_i]
set_false_path -from [get_ports sda_i]
set_false_path -to   [get_ports sda_o]
set_false_path -to   [get_ports sda_oe]

# ---- Configuration ----
set_property CFGBVS         VCCO [current_design]
set_property CONFIG_VOLTAGE  3.3  [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
