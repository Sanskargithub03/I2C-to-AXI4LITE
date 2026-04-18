# I2C to AXI4-Lite Bridge

## 📌 Overview
This project implements a bridge between I2C and AXI4-Lite protocol using Verilog.

## ⚙️ Features
- I2C Slave Interface
- AXI4-Lite Master Interface
- FSM-based control
- Read/Write support

## 🧠 Working
1. I2C master sends data
2. I2C slave decodes it
3. Converted into AXI4-Lite transaction
4. Response returned

## 🏗️ Modules
- i2c_slave.v
- axi4_lite_master.v
- bridge_top.v
- 
## 🚀 Future Work
- Burst support
- Error handling
