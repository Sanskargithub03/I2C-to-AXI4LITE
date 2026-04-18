# =============================================================================
# ModelSim Simulation Script: compile_and_sim.do
# Usage: From ModelSim console: do compile_and_sim.do
# =============================================================================

# ---- Quit any existing simulation ----
quit -sim

# ---- Create and map work library ----
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# ---- Compile RTL sources ----
echo "Compiling RTL sources..."
vlog -work work -timescale "1ns/1ps" +incdir+. \
    i2c_slave_ctrl.v         \
    axi4lite_master.v        \
    i2c_to_axi4lite_top.v    \
    axi4lite_slave_ram.v

# ---- Compile Testbench ----
echo "Compiling Testbench..."
vlog -work work -timescale "1ns/1ps" \
    tb_i2c_to_axi4lite.v

# ---- Start simulation ----
echo "Starting simulation..."
vsim -t 1ns -lib work tb_i2c_to_axi4lite \
    -voptargs="+acc"

# ---- Add waveform signals ----
add wave -divider "=== CLOCK & RESET ==="
add wave -radix binary  sim:/tb_i2c_to_axi4lite/clk
add wave -radix binary  sim:/tb_i2c_to_axi4lite/rst_n

add wave -divider "=== I2C BUS ==="
add wave -radix binary  sim:/tb_i2c_to_axi4lite/scl_tb
add wave -radix binary  sim:/tb_i2c_to_axi4lite/sda_tb
add wave -radix binary  sim:/tb_i2c_to_axi4lite/sda_oe_dut
add wave -radix binary  sim:/tb_i2c_to_axi4lite/sda

add wave -divider "=== I2C SLAVE CTRL STATE ==="
add wave -radix unsigned sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/state
add wave -radix hex      sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/shift_reg
add wave -radix unsigned sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/bit_cnt
add wave -radix unsigned sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/byte_cnt
add wave -radix hex      sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/addr_buf
add wave -radix hex      sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/wdata_buf

add wave -divider "=== AXI COMMAND INTERFACE ==="
add wave -radix hex     sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_addr
add wave -radix hex     sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_wdata
add wave -radix binary  sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_wr_req
add wave -radix binary  sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_rd_req
add wave -radix hex     sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_rdata
add wave -radix binary  sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_wr_done
add wave -radix binary  sim:/tb_i2c_to_axi4lite/dut/u_i2c_slave/axi_rd_done

add wave -divider "=== AXI4-LITE MASTER STATE ==="
add wave -radix unsigned sim:/tb_i2c_to_axi4lite/dut/u_axi_master/state

add wave -divider "=== AXI4-LITE BUS (Write) ==="
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_awaddr
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_awvalid
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_awready
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_wdata
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_wstrb
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_wvalid
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_wready
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_bvalid
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_bready
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_bresp

add wave -divider "=== AXI4-LITE BUS (Read) ==="
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_araddr
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_arvalid
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_arready
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_rdata
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_rvalid
add wave -radix binary  sim:/tb_i2c_to_axi4lite/m_rready
add wave -radix hex     sim:/tb_i2c_to_axi4lite/m_rresp

add wave -divider "=== RAM CONTENTS (word 0-5) ==="
add wave -radix hex     sim:/tb_i2c_to_axi4lite/u_ram/mem[0]
add wave -radix hex     sim:/tb_i2c_to_axi4lite/u_ram/mem[1]
add wave -radix hex     sim:/tb_i2c_to_axi4lite/u_ram/mem[2]
add wave -radix hex     sim:/tb_i2c_to_axi4lite/u_ram/mem[3]
add wave -radix hex     sim:/tb_i2c_to_axi4lite/u_ram/mem[4]
add wave -radix hex     sim:/tb_i2c_to_axi4lite/u_ram/mem[5]

# ---- Configure and run ----
configure wave -namecolwidth 260
configure wave -valuecolwidth 120
configure wave -justifyvalue left
configure wave -signalnamewidth 1

run -all

# ---- Zoom to fit ----
wave zoom full

echo "Simulation complete. Check transcript for PASS/FAIL results."
