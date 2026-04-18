// =============================================================================
// Module: i2c_to_axi4lite_top.v
// Description: Top-Level I2C to AXI4-Lite Bridge
//
//   Connects the I2C Slave Controller with the AXI4-Lite Master Controller.
//   Includes clock domain crossing (CDC) between I2C (low freq) and AXI clock.
//
//   Pin Description:
//     clk        - System / AXI clock (e.g. 100 MHz)
//     rst_n      - Active-low reset (synchronous to clk)
//     scl_i      - I2C clock input  (open-drain: external pull-up required)
//     sda_i      - I2C data  input
//     sda_o      - I2C data  output (drive low when sda_oe=1)
//     sda_oe     - SDA output enable (active-high → drive SDA=0)
//     m_axi_*    - AXI4-Lite master interface
// =============================================================================

`timescale 1ns/1ps

module i2c_to_axi4lite_top #(
    parameter SLAVE_ADDR = 7'h50
)(
    // Clock & Reset
    input  wire        clk,
    input  wire        rst_n,

    // I2C Interface
    input  wire        scl_i,
    input  wire        sda_i,
    output wire        sda_o,     // always 0 (tied low when enabled)
    output wire        sda_oe,    // 1 = drive sda_o onto the bus

    // AXI4-Lite Master Interface
    output wire [31:0] m_axi_awaddr,
    output wire [2:0]  m_axi_awprot,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,

    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,

    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    output wire [31:0] m_axi_araddr,
    output wire [2:0]  m_axi_arprot,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,

    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);

// SDA is always driven low when output-enabled (open-drain model)
assign sda_o = 1'b0;

// Internal wires between sub-modules
wire [31:0] axi_addr;
wire [31:0] axi_wdata;
wire [3:0]  axi_wstrb;
wire        axi_wr_req;
wire        axi_rd_req;
wire [31:0] axi_rdata;
wire        axi_wr_done;
wire        axi_rd_done;
wire        axi_error;

// -----------------------------------------------------------------------
// I2C Slave Controller
// -----------------------------------------------------------------------
i2c_slave_ctrl #(
    .SLAVE_ADDR (SLAVE_ADDR)
) u_i2c_slave (
    .clk        (clk),
    .rst_n      (rst_n),
    .scl_i      (scl_i),
    .sda_i      (sda_i),
    .sda_oe     (sda_oe),
    .axi_addr   (axi_addr),
    .axi_wdata  (axi_wdata),
    .axi_wstrb  (axi_wstrb),
    .axi_wr_req (axi_wr_req),
    .axi_rd_req (axi_rd_req),
    .axi_rdata  (axi_rdata),
    .axi_wr_done(axi_wr_done),
    .axi_rd_done(axi_rd_done),
    .axi_error  (axi_error)
);

// -----------------------------------------------------------------------
// AXI4-Lite Master Controller
// -----------------------------------------------------------------------
axi4lite_master u_axi_master (
    .aclk          (clk),
    .aresetn        (rst_n),
    .cmd_addr       (axi_addr),
    .cmd_wdata      (axi_wdata),
    .cmd_wstrb      (axi_wstrb),
    .cmd_wr_req     (axi_wr_req),
    .cmd_rd_req     (axi_rd_req),
    .cmd_rdata      (axi_rdata),
    .cmd_wr_done    (axi_wr_done),
    .cmd_rd_done    (axi_rd_done),
    .cmd_error      (axi_error),
    .m_axi_awaddr   (m_axi_awaddr),
    .m_axi_awprot   (m_axi_awprot),
    .m_axi_awvalid  (m_axi_awvalid),
    .m_axi_awready  (m_axi_awready),
    .m_axi_wdata    (m_axi_wdata),
    .m_axi_wstrb    (m_axi_wstrb),
    .m_axi_wvalid   (m_axi_wvalid),
    .m_axi_wready   (m_axi_wready),
    .m_axi_bresp    (m_axi_bresp),
    .m_axi_bvalid   (m_axi_bvalid),
    .m_axi_bready   (m_axi_bready),
    .m_axi_araddr   (m_axi_araddr),
    .m_axi_arprot   (m_axi_arprot),
    .m_axi_arvalid  (m_axi_arvalid),
    .m_axi_arready  (m_axi_arready),
    .m_axi_rdata    (m_axi_rdata),
    .m_axi_rresp    (m_axi_rresp),
    .m_axi_rvalid   (m_axi_rvalid),
    .m_axi_rready   (m_axi_rready)
);

endmodule
