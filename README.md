# I2C to AXI4-Lite Protocol Bridge

> Synthesizable RTL bridge — Verilog HDL | ModelSim 2020 | Nexys A7 FPGA

A fully synthesizable **I2C Slave to AXI4-Lite Master bridge** implemented in
Verilog HDL (IEEE 1364-2001). Enables any I2C master device (MCU, Arduino,
sensor hub) to read and write 32-bit registers over a standard 2-wire I2C bus
mapped to an AXI4-Lite memory-mapped fabric.

Designed, simulated, and debugged as part of the **Zoho SETU Project-Based
Internship — 6th Semester, IIIT Nagpur (2025-26)**.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [I2C Frame Protocol](#i2c-frame-protocol)
- [File Structure](#file-structure)
- [FSM Details](#fsm-details)
- [Simulation — ModelSim](#simulation--modelsim)
- [Test Cases](#test-cases)
- [Bugs Found and Fixed](#bugs-found-and-fixed)
- [FPGA Implementation](#fpga-implementation)
- [How to Run](#how-to-run)
- [Standards Compliance](#standards-compliance)
- [Author](#author)

---

## Overview

| Parameter       | Value                                      |
|-----------------|--------------------------------------------|
| Language        | Verilog HDL (IEEE 1364-2001)               |
| Simulation Tool | ModelSim Intel FPGA Starter Edition 2020.1 |
| FPGA Target     | Digilent Nexys A7-100T (Artix-7 XC7A100T) |
| System Clock    | 100 MHz                                    |
| I2C Speed       | 100 kHz (Standard Mode)                    |
| I2C Slave Addr  | 0x50 (parameterizable)                     |
| AXI Data Width  | 32-bit                                     |
| AXI Addr Width  | 32-bit                                     |
| LUT Estimate    | ~180 (of 63,400 available on Artix-7)      |
| FF Estimate     | ~150                                       |
| Test Cases      | 6 — PASS: 5, FAIL: 0                       |

---

## Architecture
              ┌────────────────────────────────────────────┐
I2C Master       │        i2c_to_axi4lite_top                  │
(MCU/Arduino)    │                                             │
│  ┌──────────────────┐  ┌────────────────┐  │
SCL ────────────►│  │  i2c_slave_ctrl  │  │ axi4lite_master│  │  AXI4-Lite
SDA ◄───────────►│  │  13-state FSM    │─►│  6-state FSM   │──┼──► Fabric
│  │  2FF synchronizer│  │  5-ch handshake│  │   (RAM/IP)
│  └──────────────────┘  └────────────────┘  │
└────────────────────────────────────────────┘
clk: 100 MHz  |  rst_n: active-low  |  SLAVE_ADDR: 7'h50
### Signal Flow

**Write path:**
`I2C START → device address → 4 AXI address bytes → 4 data bytes → STOP`
→ i2c_slave_ctrl assembles addr + data → pulses `axi_wr_req` (1 cycle)
→ axi4lite_master drives AW + W + B channels → returns `wr_done`

**Read path:**
`I2C START → device address + addr bytes → Repeated START → device address (R)`
→ i2c_slave_ctrl pulses `axi_rd_req` (1 cycle)
→ axi4lite_master drives AR + R channels → returns `rd_done` + `rdata`
→ i2c_slave_ctrl shifts out 4 data bytes on SDA

---

## I2C Frame Protocol

### Write Transaction
[START]
[SLAVE_ADDR (7-bit = 0x50) + W=0] [ACK]
[AXI_ADDR Byte3 (MSB)]            [ACK]
[AXI_ADDR Byte2]                  [ACK]
[AXI_ADDR Byte1]                  [ACK]
[AXI_ADDR Byte0 (LSB)]            [ACK]
[DATA Byte3 (MSB)]                [ACK]
[DATA Byte2]                      [ACK]
[DATA Byte1]                      [ACK]
[DATA Byte0 (LSB)]                [ACK]
[STOP]
### Read Transaction (uses Repeated START)
Phase 1 — Send AXI address:
[START]
[SLAVE_ADDR + W=0]                [ACK]
[AXI_ADDR Byte3..Byte0 × 4]      [ACK each]
Phase 2 — Read data (no STOP between phases!):
[Repeated START]
[SLAVE_ADDR + R=1]                [ACK]
[DATA Byte3]                      [ACK]
[DATA Byte2]                      [ACK]
[DATA Byte1]                      [ACK]
[DATA Byte0]                      [NACK]
[STOP]
> **Important:** A Repeated START (not STOP + START) is used between
> phases so the slave FSM retains the latched AXI address.

---

## File Structure
i2c_to_axi4lite/
├── rtl/
│   ├── i2c_slave_ctrl.v          I2C slave FSM (13 states)
│   ├── axi4lite_master.v         AXI4-Lite master FSM (6 states)
│   ├── i2c_to_axi4lite_top.v     Top-level integration wrapper
│   └── axi4lite_slave_ram.v      256×32-bit AXI4-Lite slave RAM
├── tb/
│   └── tb_i2c_to_axi4lite.v      Self-checking testbench (6 TCs)
├── sim/
│   └── compile_and_sim.do        ModelSim TCL script
├── constraints/
│   └── i2c_to_axi4lite.xdc       Vivado XDC (Nexys A7-100T)
├── docs/
│   └── SETU_Project_Report.pdf   Full project report
└── README.md

---

## FSM Details

### I2C Slave Controller — 13 States

| State            | Encoding | Description                              |
|------------------|----------|------------------------------------------|
| `ST_IDLE`        | 4'd0     | Wait for START condition                 |
| `ST_DEV_ADDR`    | 4'd1     | Receive 8 bits: 7-bit address + R/W bit  |
| `ST_DEV_ACK`     | 4'd2     | Hold SDA low for ACK; decode R/W         |
| `ST_AXI_ADDR`    | 4'd3     | Receive 4-byte AXI address MSB first     |
| `ST_AXI_ADDR_ACK`| 4'd4     | ACK each address byte                    |
| `ST_WR_DATA`     | 4'd5     | Receive 4-byte write data MSB first      |
| `ST_WR_ACK`      | 4'd6     | ACK each data byte                       |
| `ST_AXI_WR`      | 4'd7     | Pulse `axi_wr_req` for exactly one clock |
| `ST_AXI_WR_WAIT` | 4'd8     | Wait for `axi_wr_done` or `axi_error`    |
| `ST_AXI_RD`      | 4'd9     | Pulse `axi_rd_req` for exactly one clock |
| `ST_AXI_RD_WAIT` | 4'd10    | Wait for `axi_rd_done`, capture RDATA    |
| `ST_RD_DATA`     | 4'd11    | Transmit 4 data bytes MSB first on SDA   |
| `ST_RD_ACK`      | 4'd12    | Sample ACK/NACK from I2C master          |

### AXI4-Lite Master — 6 States

| State         | Action                                          |
|---------------|-------------------------------------------------|
| `ST_IDLE`     | Wait for `cmd_wr_req` or `cmd_rd_req`           |
| `ST_WR_ADDR`  | Assert AWVALID, wait for AWREADY handshake      |
| `ST_WR_DATA`  | Assert WVALID, wait for WREADY handshake        |
| `ST_WR_RESP`  | Assert BREADY, wait for BVALID, check BRESP     |
| `ST_RD_ADDR`  | Assert ARVALID, wait for ARREADY handshake      |
| `ST_RD_DATA`  | Assert RREADY, wait for RVALID, capture RDATA   |

---

## Simulation — ModelSim

### Environment

| Parameter       | Value                                      |
|-----------------|--------------------------------------------|
| Tool            | ModelSim Intel FPGA Starter Edition 2020.1 |
| Timescale       | 1ns / 1ps                                  |
| System Clock    | 100 MHz (10 ns period)                     |
| I2C SCL         | 100 kHz (SCL_HALF = 5000 ns)               |
| Slave Address   | 0x50 (7-bit)                               |
| Simulation Time | ~100 ms max (watchdog protected)           |

### Waveform Screenshot

![ModelSim Wave Window](docs/sim_waveform.png)

*SCL/SDA I2C bus activity and AXI4-Lite channel signals visible*

![ModelSim Transcript](docs/sim_transcript.png)

*Transcript showing PASS/FAIL results, objects panel, and dataflow view*

---

## Test Cases

| TC  | Operation       | AXI Address  | Data            | Result           |
|-----|-----------------|--------------|-----------------|------------------|
| TC1 | Write           | 0x00000004   | 0xDEADBEEF      | AXI write OK     |
| TC2 | Read back       | 0x00000004   | —               | Returns DEADBEEF |
| TC3 | Write           | 0x00000008   | 0xCAFEBABE      | AXI write OK     |
| TC4 | Read back       | 0x00000008   | —               | Returns CAFEBABE |
| TC5 | Write + Read    | 0x00000000   | 0x12345678      | Returns 12345678 |
| TC6 | Back-to-back WR | 0x10 / 0x14  | ABCD1234 / 5678EFAB | Both correct |

### Expected Transcript Output
==========================================================
I2C to AXI4-Lite Bridge Simulation
Slave Addr: 0x50 | CLK: 100 MHz | SCL: 100 kHz
[TC1] Write 0xDEADBEEF to addr 0x00000004
[TC2] Read back from addr 0x00000004
READ result: 0xDEADBEEF
[PASS] TC2 ReadBack got=0xDEADBEEF expected=0xDEADBEEF
[TC3] Write 0xCAFEBABE to addr 0x00000008
[TC4] Read from addr 0x00000008
[PASS] TC4 ReadBack got=0xCAFEBABE expected=0xCAFEBABE
[TC5] Write 0x12345678 to addr 0x00000000
[PASS] TC5 Addr0 got=0x12345678 expected=0x12345678
[TC6] Back-to-back writes / reads
[PASS] TC6 addr0x10 got=0xABCD1234 expected=0xABCD1234
[PASS] TC6 addr0x14 got=0x5678EFAB expected=0x5678EFAB
==========================================================
SIMULATION COMPLETE
PASS: 5 | FAIL: 0
ALL TESTS PASSED

---

## Bugs Found and Fixed

Five RTL bugs were identified during simulation and corrected.
All fixes maintain IEEE 1364-2001 Verilog compliance.

### Bug 1 — Non-blocking assignment race on last bit

**Location:** `ST_DEV_ADDR` in `i2c_slave_ctrl.v`

**Problem:** On the last bit (`bit_cnt == 0`), `shift_reg` was checked
immediately after `shift_reg <= {shift_reg[6:0], sda}`. Due to Verilog
non-blocking semantics, `shift_reg` still held the *old* value — the last
SDA bit was never included in the comparison. Address match always failed.

```verilog
// WRONG
shift_reg <= {shift_reg[6:0], sda};
if (shift_reg[7:1] == SLAVE_ADDR)  // OLD value — last bit missing!
```

```verilog
// CORRECT — use the concatenated live value directly
byte_in <= {shift_reg[6:0], sda};
if (byte_in[7:1] == SLAVE_ADDR)   // checked in ST_DEV_ACK after assignment
```

---

### Bug 2 — ACK deasserted one SCL cycle too early

**Location:** `ST_DEV_ACK` in `i2c_slave_ctrl.v`

**Problem:** `sda_oe` was deasserted on the *first* SCL fall after asserting
ACK — which happened before the 9th (ACK) SCL pulse even began. The master
sampled NACK on every byte.

**Fix:** Dedicated `ST_DEV_ACK` state. `sda_oe` is asserted on the
*rising edge* of the last data bit so SDA is already low when the 9th SCL
clock rises. `sda_oe` is deasserted only after that 9th SCL falls.

---

### Bug 3 — STOP between read phases reset slave FSM

**Location:** `i2c_read_32` task in `tb_i2c_to_axi4lite.v`

**Problem:** A full STOP was sent between the address-write phase and the
data-read phase. This triggered `stop_det`, moved the slave FSM to
`ST_IDLE`, and cleared the latched `axi_addr`.

**Fix:** Use a **Repeated START** (no STOP) between phases — as specified
in the NXP I2C standard for combined write-then-read transactions.

---

### Bug 4 — Illegal variable part-select (ModelSim 2020)

**Location:** `ST_RD_DATA` in `i2c_slave_ctrl.v`

**Problem:** `wdata_buf[rd_bit_idx]` — variable index on a reg array —
is rejected by ModelSim Intel FPGA Edition 2020 with:
`Error: Illegal part-select expression`

**Fix:** Verilog `function get_rdata_bit()` with an explicit 32-entry
`case` statement enumerating all bit positions. IEEE 1364-2001 compliant
and synthesisable on all tools.

```verilog
function get_rdata_bit;
    input [31:0] data;
    input [1:0]  bcnt;
    input [2:0]  bbit;
    reg [4:0] idx;
    begin
        case (bcnt)
            2'd3: idx = 5'd24 + {2'b00, bbit};
            2'd2: idx = 5'd16 + {2'b00, bbit};
            2'd1: idx = 5'd8  + {2'b00, bbit};
            default: idx = {2'b00, bbit};
        endcase
        case (idx)
            5'd0:  get_rdata_bit = data[0];
            // ... 5'd1 to 5'd30 ...
            default: get_rdata_bit = data[31];
        endcase
    end
endfunction
```

---

### Bug 5 — AXI request pulse held high every clock

**Location:** `ST_AXI_WR` in `i2c_slave_ctrl.v`

**Problem:** `axi_wr_req <= 1'b1` was inside `ST_AXI_WR` with no
immediate state change, causing the AXI master to see a multi-cycle
high signal and re-trigger on every clock edge.

**Fix:** Added `ST_AXI_WR_WAIT` state. `axi_wr_req` pulses HIGH for
exactly one clock, then the FSM moves to wait state. Default assignment
`axi_wr_req <= 1'b0` at the top of the `always` block ensures automatic
deassertion.

```verilog
ST_AXI_WR: begin
    axi_wr_req <= 1'b1;           // single-cycle pulse
    state      <= ST_AXI_WR_WAIT; // immediately move to wait
end
ST_AXI_WR_WAIT: begin
    if (axi_wr_done || axi_error)
        state <= ST_IDLE;
end
```

---

## FPGA Implementation

### Target Board

| Parameter      | Value                                  |
|----------------|----------------------------------------|
| Board          | Digilent Nexys A7-100T                 |
| Device         | Xilinx Artix-7 XC7A100T-1CSG324C      |
| Synthesis Tool | Xilinx Vivado 2020.x                   |
| Clock Pin      | E3 (100 MHz onboard oscillator)        |
| Reset Pin      | N17 (BTNC, active-low)                 |
| SCL Pin        | C17 (PMOD JA Pin 1)                    |
| SDA Pin        | D18 (PMOD JA Pin 2)                    |

### Resource Utilisation Estimate

| Resource | Estimated | Available (100T) |
|----------|-----------|------------------|
| LUT      | ~180      | 63,400           |
| FF       | ~150      | 126,800          |
| BRAM     | 0         | 135              |
| DSP      | 0         | 240              |
| IOB      | 4         | 210              |

### Hardware Connection
MCU / Arduino                 Nexys A7-100T
(I2C Master)                  PMOD JA connector
│                        ┌──────────────────┐
SCL ─┼────── 4.7kΩ to 3.3V ──► JA1 (Pin C17)    │
SDA ◄┼──────────────────────►  JA2 (Pin D18)    │
GND ─┼────────────────────── ► GND              │
│                        └──────────────────┘

> **Note:** Both SCL and SDA require external 4.7 kΩ pull-up resistors
> to 3.3 V for correct open-drain operation.

For FPGA open-drain SDA:
```verilog
assign SDA_PAD = sda_oe ? 1'b0 : 1'bz;  // tri-state / IOBUF primitive
```

---

## How to Run

### Method A — ModelSim GUI (Recommended)

Open ModelSim
File → New → Project → Enter name → OK
Add Existing File → select all 5 .v files → Open
Compile → Compile All  (all files should show green ✓)
Simulate → Start Simulation → expand work → select tb_i2c_to_axi4lite → OK
In sim tab: right-click tb → Add → To Wave → All items in region
Click Run -All  (or Simulate → Run → Run -All)
Check transcript: PASS: 5 | FAIL: 0
Press F in Wave window to zoom full


### Method B — TCL Script

```tcl
cd /path/to/project
do sim/compile_and_sim.do
```

### Clean Rebuild

```tcl
quit -sim
vdel -lib work -all
vlib work
vmap work work
```
Then **Compile → Compile All**.

---

## Standards Compliance

| Standard             | Reference                  | Compliance                              |
|----------------------|----------------------------|-----------------------------------------|
| I2C Bus Spec         | NXP UM10204 Rev.7, 2021    | 7-bit, open-drain, ACK/NACK, START/STOP |
| AXI4-Lite Protocol   | ARM IHI0022F, 2013         | All 5 channels, BRESP/RRESP handling    |
| Verilog HDL          | IEEE Std 1364-2001         | Pure Verilog 2001, no SystemVerilog     |
| FPGA Constraints     | Xilinx UG908 / UG761       | Vivado XDC, false-paths for async I2C   |

---

## Author

**Sanskar Yede**
Roll No: BT23ECE057
Department of Electronics & Communication Engineering
IIIT Nagpur

Project submitted as part of **Zoho SETU Project-Based Internship**
6th Semester | Academic Year 2025–26 | Submission: 30 March 2026

---

## References

1. NXP Semiconductors, *UM10204 I2C-bus specification*, Rev. 7, 2021
2. ARM Limited, *AMBA AXI and ACE Protocol Specification*, IHI0022F, 2013
3. Xilinx/AMD, *Vivado Design Suite User Guide*, UG908
4. Xilinx/AMD, *AXI Reference Guide*, UG761
5. IEEE Std 1364-2001, *Verilog Hardware Description Language*
6. Digilent Inc., *Nexys A7 Reference Manual*, 2019
7. ModelSim Intel FPGA Edition User Manual, 2020

---

> *Pure Verilog 2001 — synthesizable on Vivado, Quartus, and all
> major FPGA toolchains. Simulated on ModelSim Intel FPGA Edition 2020.1.*
