// Testbench: tb_i2c_to_axi4lite.v  (FIXED v2)
//
// BUG FIXES vs v1:
//
//  FIX-A  i2c_send_byte: SCL was falling in the middle of SDA setup.
//         Corrected bit-loop so SDA is always stable before SCL rises.
//         Specifically the extra half-period after SCL fall was removed
//         from the bit loop and folded into the SCL-low phase.
//
//  FIX-B  i2c_send_byte ACK sampling: the original code sampled 'sda'
//         at SCL_HALF/2 into the SCL-high phase.  Because sda_oe is
//         registered in the slave (one clk delay after SCL rise), we now
//         wait a full SCL_HALF before sampling — guaranteeing the slave
//         has had many clock cycles to assert sda_oe.
//
//  FIX-C  i2c_read_32: the original sent a full STOP between the
//         address-write phase and the data-read phase.  A STOP resets
//         the slave FSM so it loses the latched axi_addr.  The fix
//         uses a REPEATED START (no STOP) exactly as the I2C spec requires
//         for combined write-then-read transactions.
//
//  FIX-D  i2c_recv_byte: SCL timing corrected to be symmetric and to
//         give the slave sufficient setup time before sampling.
//
//  FIX-E  Added inter-transaction idle gap (10 × SCL_HALF) to allow the
//         AXI write/read to complete before the next I2C frame begins.
//
// =============================================================================

`timescale 1ns/1ps

module tb_i2c_to_axi4lite;

// Parameters
parameter CLK_PERIOD = 10;        // 100 MHz system clock (ns)
parameter SCL_HALF   = 5000;      // 100 kHz SCL → half-period = 5 µs
parameter SLAVE_ADDR = 7'h50;

// DUT signals
reg  clk, rst_n;

// I2C lines (testbench drives scl_tb / sda_tb)
reg  scl_tb, sda_tb;
wire sda_oe_dut;          // DUT open-drain pull-down

// Wired-AND model of open-drain I2C bus
wire scl = scl_tb;
wire sda = sda_tb & ~sda_oe_dut;   // DUT can pull low

// AXI4-Lite interconnect (DUT master ↔ slave RAM)
wire [31:0] m_awaddr;  wire [2:0] m_awprot;  wire m_awvalid; wire m_awready;
wire [31:0] m_wdata;   wire [3:0] m_wstrb;   wire m_wvalid;  wire m_wready;
wire [1:0]  m_bresp;   wire m_bvalid;         wire m_bready;
wire [31:0] m_araddr;  wire [2:0] m_arprot;  wire m_arvalid; wire m_arready;
wire [31:0] m_rdata;   wire [1:0] m_rresp;   wire m_rvalid;  wire m_rready;

// DUT — I2C-to-AXI4-Lite bridge
i2c_to_axi4lite_top #(.SLAVE_ADDR(SLAVE_ADDR)) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .scl_i        (scl),
    .sda_i        (sda),
    .sda_o        (),
    .sda_oe       (sda_oe_dut),
    .m_axi_awaddr (m_awaddr),   .m_axi_awprot (m_awprot),
    .m_axi_awvalid(m_awvalid),  .m_axi_awready(m_awready),
    .m_axi_wdata  (m_wdata),    .m_axi_wstrb  (m_wstrb),
    .m_axi_wvalid (m_wvalid),   .m_axi_wready (m_wready),
    .m_axi_bresp  (m_bresp),    .m_axi_bvalid (m_bvalid),
    .m_axi_bready (m_bready),
    .m_axi_araddr (m_araddr),   .m_axi_arprot (m_arprot),
    .m_axi_arvalid(m_arvalid),  .m_axi_arready(m_arready),
    .m_axi_rdata  (m_rdata),    .m_axi_rresp  (m_rresp),
    .m_axi_rvalid (m_rvalid),   .m_axi_rready (m_rready)
);

// AXI4-Lite slave RAM
axi4lite_slave_ram u_ram (
    .aclk         (clk),        .aresetn       (rst_n),
    .s_axi_awaddr (m_awaddr[9:0]), .s_axi_awprot(m_awprot),
    .s_axi_awvalid(m_awvalid),  .s_axi_awready (m_awready),
    .s_axi_wdata  (m_wdata),    .s_axi_wstrb   (m_wstrb),
    .s_axi_wvalid (m_wvalid),   .s_axi_wready  (m_wready),
    .s_axi_bresp  (m_bresp),    .s_axi_bvalid  (m_bvalid),
    .s_axi_bready (m_bready),
    .s_axi_araddr (m_araddr[9:0]), .s_axi_arprot(m_arprot),
    .s_axi_arvalid(m_arvalid),  .s_axi_arready (m_arready),
    .s_axi_rdata  (m_rdata),    .s_axi_rresp   (m_rresp),
    .s_axi_rvalid (m_rvalid),   .s_axi_rready  (m_rready)
);

// Clock
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// I2C primitive tasks

// START condition: SDA falls while SCL is high
task i2c_start;
    begin
        scl_tb = 1; sda_tb = 1; #(SCL_HALF);
        sda_tb = 0;             #(SCL_HALF);   // SDA low → START
        scl_tb = 0;             #(SCL_HALF);   // SCL low; master ready to clock first bit
    end
endtask

// STOP condition: SDA rises while SCL is high
task i2c_stop;
    begin
        sda_tb = 0; scl_tb = 0; #(SCL_HALF);
        scl_tb = 1;             #(SCL_HALF);
        sda_tb = 1;             #(SCL_HALF);   // SDA high → STOP
    end
endtask


task i2c_send_byte;
    input [7:0] data;
    output      ack;
    integer j;
    begin
        for (j = 7; j >= 0; j = j - 1) begin
            scl_tb = 0;
            sda_tb = data[j];
            #(SCL_HALF);        // SDA stable, SCL low
            scl_tb = 1;
            #(SCL_HALF);        // Slave samples SDA here
            scl_tb = 0;
            // No extra delay here; next loop iteration begins SCL=0 phase
        end
        // ACK/NACK phase (9th clock)
        sda_tb = 1;             // Release SDA so slave can pull it low
        #(SCL_HALF);            // SCL=0, slave drives SDA
        scl_tb = 1;
        #(SCL_HALF);            // SCL=1 — sample SDA now (slave should have ack)
        ack = sda;              // 0 = ACK (slave pulled low), 1 = NACK
        scl_tb = 0;
        #(SCL_HALF);            // Complete the 9th SCL low phase
    end
endtask

// Receive one byte, MSB first.
// FIX-D: Symmetric SCL timing; sample SDA mid-SCL-high.
task i2c_recv_byte;
    output [7:0] data;
    input        ack_val;
    integer j;
    begin
        data   = 8'h00;
        sda_tb = 1;        // Release SDA — slave will drive it
        for (j = 7; j >= 0; j = j - 1) begin
            scl_tb = 0;
            #(SCL_HALF);   // Slave sets SDA during SCL low
            scl_tb = 1;
            #(SCL_HALF/2); // Wait half of SCL high for SDA to settle
            data[j] = sda; // Sample
            #(SCL_HALF/2); // Finish SCL high
            scl_tb = 0;
        end
        // Send ACK/NACK
        scl_tb = 0;
        sda_tb = ~ack_val; // ACK=0 → drive SDA low; NACK=1 → release SDA
        #(SCL_HALF);
        scl_tb = 1;
        #(SCL_HALF);
        scl_tb = 0;
        sda_tb = 1;        // Release SDA
        #(SCL_HALF);
    end
endtask

// High-level WRITE: START + addr+W + 4B AXI addr + 4B data + STOP
task i2c_write_32;
    input [31:0] axi_addr;
    input [31:0] axi_data;
    reg          ack;
    begin
        $display("TB [%0t] I2C WRITE: addr=0x%08X  data=0x%08X", $time, axi_addr, axi_data);
        i2c_start;
        i2c_send_byte({SLAVE_ADDR, 1'b0}, ack);
        if (ack !== 1'b0) $display("  WARNING: No ACK for DEV_ADDR (write)");

        i2c_send_byte(axi_addr[31:24], ack);
        i2c_send_byte(axi_addr[23:16], ack);
        i2c_send_byte(axi_addr[15: 8], ack);
        i2c_send_byte(axi_addr[ 7: 0], ack);

        i2c_send_byte(axi_data[31:24], ack);
        i2c_send_byte(axi_data[23:16], ack);
        i2c_send_byte(axi_data[15: 8], ack);
        i2c_send_byte(axi_data[ 7: 0], ack);

        i2c_stop;
        // FIX-E: wait for AXI write to complete before next transaction
        #(SCL_HALF * 10);
    end
endtask

task i2c_read_32;
    input  [31:0] axi_addr;
    output [31:0] axi_data;
    reg    [7:0]  b3, b2, b1, b0;
    reg           ack;
    begin
        $display("TB [%0t] I2C READ:  addr=0x%08X", $time, axi_addr);

        // ---- Phase 1: write AXI address into slave ----
        i2c_start;
        i2c_send_byte({SLAVE_ADDR, 1'b0}, ack);   // addr + W
        if (ack !== 1'b0) $display("  WARNING: No ACK for DEV_ADDR (read phase-1)");

        i2c_send_byte(axi_addr[31:24], ack);
        i2c_send_byte(axi_addr[23:16], ack);
        i2c_send_byte(axi_addr[15: 8], ack);
        i2c_send_byte(axi_addr[ 7: 0], ack);

        // ---- Phase 2: REPEATED START then read ----
        i2c_start;                                 // repeated START
        i2c_send_byte({SLAVE_ADDR, 1'b1}, ack);   // addr + R
        if (ack !== 1'b0) $display("  WARNING: No ACK for DEV_ADDR (read phase-2)");

        i2c_recv_byte(b3, 1'b0);   // byte 3 (MSB), send ACK
        i2c_recv_byte(b2, 1'b0);   // byte 2, send ACK
        i2c_recv_byte(b1, 1'b0);   // byte 1, send ACK
        i2c_recv_byte(b0, 1'b1);   // byte 0 (LSB), send NACK (last byte)

        i2c_stop;
        #(SCL_HALF * 10);          // inter-transaction idle

        axi_data = {b3, b2, b1, b0};
        $display("  READ result: 0x%08X", axi_data);
    end
endtask

// Pass/fail tracking
integer pass_count, fail_count;

task check;
    input [31:0]  got;
    input [31:0]  exp;
    input [127:0] test_name;
    begin
        if (got === exp) begin
            $display("  [PASS] %s  got=0x%08X  expected=0x%08X", test_name, got, exp);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %s  got=0x%08X  expected=0x%08X", test_name, got, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// Main test sequence
reg [31:0] rd_data;

initial begin
    $dumpfile("i2c_to_axi4lite.vcd");
    $dumpvars(0, tb_i2c_to_axi4lite);

    pass_count = 0;
    fail_count = 0;

    scl_tb = 1;
    sda_tb = 1;
    rst_n  = 0;
    #(CLK_PERIOD * 20);
    rst_n = 1;
    #(CLK_PERIOD * 10);

    $display("==========================================================");
    $display(" I2C to AXI4-Lite Bridge Simulation  (FIXED testbench)");
    $display(" Slave Addr: 0x%02X | CLK: 100 MHz | SCL: 100 kHz", SLAVE_ADDR);
    $display("==========================================================");

    // TC1: Write 0xDEADBEEF → addr 0x00000004
    $display("\n[TC1] Write 0xDEADBEEF to addr 0x00000004");
    i2c_write_32(32'h00000004, 32'hDEADBEEF);

    // TC2: Read back from addr 0x00000004  (expect 0xDEADBEEF)
    $display("\n[TC2] Read back from addr 0x00000004");
    i2c_read_32(32'h00000004, rd_data);
    check(rd_data, 32'hDEADBEEF, "TC2 ReadBack");

    // TC3: Write 0xCAFEBABE → addr 0x00000008
    $display("\n[TC3] Write 0xCAFEBABE to addr 0x00000008");
    i2c_write_32(32'h00000008, 32'hCAFEBABE);

    // TC4: Read back from addr 0x00000008  (expect 0xCAFEBABE)
    $display("\n[TC4] Read from addr 0x00000008");
    i2c_read_32(32'h00000008, rd_data);
    check(rd_data, 32'hCAFEBABE, "TC4 ReadBack");

    // TC5: Write and read addr 0x00000000
    $display("\n[TC5] Write 0x12345678 to addr 0x00000000");
    i2c_write_32(32'h00000000, 32'h12345678);
    $display("[TC5] Read back from addr 0x00000000");
    i2c_read_32(32'h00000000, rd_data);
    check(rd_data, 32'h12345678, "TC5 Addr0");

    // TC6: Back-to-back writes then reads
    $display("\n[TC6] Back-to-back writes");
    i2c_write_32(32'h00000010, 32'hABCD1234);
    i2c_write_32(32'h00000014, 32'h5678EFAB);
    $display("[TC6] Reads");
    i2c_read_32(32'h00000010, rd_data);
    check(rd_data, 32'hABCD1234, "TC6 addr0x10");
    i2c_read_32(32'h00000014, rd_data);
    check(rd_data, 32'h5678EFAB, "TC6 addr0x14");

    $display("\n==========================================================");
    $display(" SIMULATION COMPLETE");
    $display(" PASS: %0d  |  FAIL: %0d", pass_count, fail_count);
    $display("==========================================================");
    if (fail_count == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" SOME TESTS FAILED");

    #(SCL_HALF * 10);
    $finish;
end

// Watchdog (100 ms — generous for 6 transactions at 100 kHz)
initial begin
    #100_000_000;
    $display("ERROR: Simulation watchdog timeout!");
    $finish;
end

endmodule
