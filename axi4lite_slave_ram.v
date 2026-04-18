// =============================================================================
// Module: axi4lite_slave_ram.v
// Description: Simple AXI4-Lite Slave with 256x32-bit RAM
//   Used as the target memory in simulation / FPGA testing.
// =============================================================================

`timescale 1ns/1ps

module axi4lite_slave_ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,   // 1K address space (byte-addressed, 256 words)
    parameter MEM_DEPTH  = 256
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // Write Address
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    // Write Data
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [3:0]             s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    // Write Response
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    // Read Address
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    // Read Data
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready
);

// -----------------------------------------------------------------------
// Internal RAM
// -----------------------------------------------------------------------
reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

integer i;
initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1)
        mem[i] = 32'hDEAD_0000 + i; // Initialize with known pattern
end

// Word index from byte address
wire [7:0] wr_word_addr = s_axi_awaddr[9:2];
wire [7:0] rd_word_addr = s_axi_araddr[9:2];

// -----------------------------------------------------------------------
// Write FSM
// -----------------------------------------------------------------------
localparam WR_IDLE = 2'd0, WR_DATA = 2'd1, WR_RESP = 2'd2;
reg [1:0] wr_state;
reg [7:0] wr_addr_latch;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        s_axi_bresp   <= 2'b00;
        wr_state      <= WR_IDLE;
        wr_addr_latch <= 8'd0;
    end else begin
        case (wr_state)
            WR_IDLE: begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                if (s_axi_awvalid && s_axi_awready) begin
                    wr_addr_latch <= wr_word_addr;
                    s_axi_awready <= 1'b0;
                    wr_state      <= WR_DATA;
                end
            end
            WR_DATA: begin
                if (s_axi_wvalid && s_axi_wready) begin
                    // Byte-enable write
                    if (s_axi_wstrb[0]) mem[wr_addr_latch][ 7: 0] <= s_axi_wdata[ 7: 0];
                    if (s_axi_wstrb[1]) mem[wr_addr_latch][15: 8] <= s_axi_wdata[15: 8];
                    if (s_axi_wstrb[2]) mem[wr_addr_latch][23:16] <= s_axi_wdata[23:16];
                    if (s_axi_wstrb[3]) mem[wr_addr_latch][31:24] <= s_axi_wdata[31:24];
                    s_axi_wready <= 1'b0;
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp  <= 2'b00; // OKAY
                    wr_state     <= WR_RESP;
                end
            end
            WR_RESP: begin
                if (s_axi_bready && s_axi_bvalid) begin
                    s_axi_bvalid <= 1'b0;
                    wr_state     <= WR_IDLE;
                end
            end
        endcase
    end
end

// -----------------------------------------------------------------------
// Read FSM
// -----------------------------------------------------------------------
localparam RD_IDLE = 1'b0, RD_DATA = 1'b1;
reg rd_state;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rdata   <= 32'd0;
        s_axi_rresp   <= 2'b00;
        rd_state      <= RD_IDLE;
    end else begin
        case (rd_state)
            RD_IDLE: begin
                s_axi_arready <= 1'b1;
                if (s_axi_arvalid && s_axi_arready) begin
                    s_axi_arready <= 1'b0;
                    s_axi_rdata   <= mem[rd_word_addr];
                    s_axi_rvalid  <= 1'b1;
                    s_axi_rresp   <= 2'b00;
                    rd_state      <= RD_DATA;
                end
            end
            RD_DATA: begin
                if (s_axi_rready && s_axi_rvalid) begin
                    s_axi_rvalid <= 1'b0;
                    rd_state     <= RD_IDLE;
                end
            end
        endcase
    end
end

endmodule
