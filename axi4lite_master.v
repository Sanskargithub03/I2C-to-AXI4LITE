// =============================================================================
// Module: axi4lite_master.v
// Description: AXI4-Lite Master Controller
//   Issues AXI4-Lite Read / Write transactions on behalf of the I2C slave.
//   Implements the full AXI4-Lite handshake with timeout protection.
// =============================================================================

`timescale 1ns/1ps

module axi4lite_master (
    input  wire        aclk,
    input  wire        aresetn,

    // Command interface (from I2C slave ctrl)
    input  wire [31:0] cmd_addr,
    input  wire [31:0] cmd_wdata,
    input  wire [3:0]  cmd_wstrb,
    input  wire        cmd_wr_req,
    input  wire        cmd_rd_req,
    output reg  [31:0] cmd_rdata,
    output reg         cmd_wr_done,
    output reg         cmd_rd_done,
    output reg         cmd_error,

    // AXI4-Lite Write Address Channel
    output reg  [31:0] m_axi_awaddr,
    output reg  [2:0]  m_axi_awprot,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // AXI4-Lite Write Data Channel
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // AXI4-Lite Write Response Channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,

    // AXI4-Lite Read Address Channel
    output reg  [31:0] m_axi_araddr,
    output reg  [2:0]  m_axi_arprot,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,

    // AXI4-Lite Read Data Channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);

// -----------------------------------------------------------------------
// State machine
// -----------------------------------------------------------------------
localparam  ST_IDLE    = 3'd0,
            ST_WR_ADDR = 3'd1,
            ST_WR_DATA = 3'd2,
            ST_WR_RESP = 3'd3,
            ST_RD_ADDR = 3'd4,
            ST_RD_DATA = 3'd5,
            ST_DONE    = 3'd6;

reg [2:0] state;

// Timeout counter (prevent lockup if slave never responds)
localparam TIMEOUT_VAL = 16'd65535;
reg [15:0] timeout_cnt;
wire       timeout = (timeout_cnt == TIMEOUT_VAL);

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        state          <= ST_IDLE;
        m_axi_awaddr   <= 32'd0;
        m_axi_awprot   <= 3'd0;
        m_axi_awvalid  <= 1'b0;
        m_axi_wdata    <= 32'd0;
        m_axi_wstrb    <= 4'hF;
        m_axi_wvalid   <= 1'b0;
        m_axi_bready   <= 1'b0;
        m_axi_araddr   <= 32'd0;
        m_axi_arprot   <= 3'd0;
        m_axi_arvalid  <= 1'b0;
        m_axi_rready   <= 1'b0;
        cmd_rdata      <= 32'd0;
        cmd_wr_done    <= 1'b0;
        cmd_rd_done    <= 1'b0;
        cmd_error      <= 1'b0;
        timeout_cnt    <= 16'd0;
    end else begin
        // Default one-cycle pulses
        cmd_wr_done <= 1'b0;
        cmd_rd_done <= 1'b0;
        cmd_error   <= 1'b0;

        case (state)
            // ----------------------------------------------------------
            ST_IDLE: begin
                timeout_cnt <= 16'd0;
                if (cmd_wr_req) begin
                    m_axi_awaddr  <= cmd_addr;
                    m_axi_awprot  <= 3'd0;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata   <= cmd_wdata;
                    m_axi_wstrb   <= cmd_wstrb;
                    m_axi_wvalid  <= 1'b1;
                    state         <= ST_WR_ADDR;
                end else if (cmd_rd_req) begin
                    m_axi_araddr  <= cmd_addr;
                    m_axi_arprot  <= 3'd0;
                    m_axi_arvalid <= 1'b1;
                    state         <= ST_RD_ADDR;
                end
            end

            // ----------------------------------------------------------
            // Write: Wait for address handshake
            ST_WR_ADDR: begin
                timeout_cnt <= timeout_cnt + 1'b1;
                if (timeout) begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    cmd_error     <= 1'b1;
                    state         <= ST_IDLE;
                end else begin
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 1'b0;
                        state         <= ST_WR_DATA;
                        timeout_cnt   <= 16'd0;
                    end
                end
            end

            // ----------------------------------------------------------
            // Write: Wait for data handshake
            ST_WR_DATA: begin
                timeout_cnt <= timeout_cnt + 1'b1;
                if (timeout) begin
                    m_axi_wvalid <= 1'b0;
                    cmd_error    <= 1'b1;
                    state        <= ST_IDLE;
                end else begin
                    if (m_axi_wready && m_axi_wvalid) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= ST_WR_RESP;
                        timeout_cnt  <= 16'd0;
                    end
                end
            end

            // ----------------------------------------------------------
            // Write: Wait for response
            ST_WR_RESP: begin
                timeout_cnt <= timeout_cnt + 1'b1;
                if (timeout) begin
                    m_axi_bready <= 1'b0;
                    cmd_error    <= 1'b1;
                    state        <= ST_IDLE;
                end else begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        if (m_axi_bresp == 2'b00)
                            cmd_wr_done <= 1'b1;
                        else
                            cmd_error   <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            // ----------------------------------------------------------
            // Read: Wait for address handshake
            ST_RD_ADDR: begin
                timeout_cnt <= timeout_cnt + 1'b1;
                if (timeout) begin
                    m_axi_arvalid <= 1'b0;
                    cmd_error     <= 1'b1;
                    state         <= ST_IDLE;
                end else begin
                    if (m_axi_arready && m_axi_arvalid) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= ST_RD_DATA;
                        timeout_cnt   <= 16'd0;
                    end
                end
            end

            // ----------------------------------------------------------
            // Read: Wait for data
            ST_RD_DATA: begin
                timeout_cnt <= timeout_cnt + 1'b1;
                if (timeout) begin
                    m_axi_rready <= 1'b0;
                    cmd_error    <= 1'b1;
                    state        <= ST_IDLE;
                end else begin
                    if (m_axi_rvalid) begin
                        m_axi_rready <= 1'b0;
                        cmd_rdata    <= m_axi_rdata;
                        if (m_axi_rresp == 2'b00)
                            cmd_rd_done <= 1'b1;
                        else
                            cmd_error   <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
