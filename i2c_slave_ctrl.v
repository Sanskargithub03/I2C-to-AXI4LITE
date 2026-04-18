// =============================================================================
// Module: i2c_slave_ctrl.v
// Description: I2C Slave Controller
//   Receives I2C transactions and decodes address, data, and read/write.
//   Protocol: 7-bit I2C address, then 32-bit AXI address (4 bytes),
//             then data bytes for write; read returns data from AXI.
//
//   I2C Frame Format (Write):
//     [START] [DEV_ADDR(7b)+W] [ACK] [AXI_ADDR_B3] [ACK] [AXI_ADDR_B2] [ACK]
//             [AXI_ADDR_B1] [ACK] [AXI_ADDR_B0] [ACK]
//             [DATA_B3] [ACK] [DATA_B2] [ACK] [DATA_B1] [ACK] [DATA_B0] [ACK] [STOP]
//
//   I2C Frame Format (Read):
//     [START] [DEV_ADDR(7b)+W] [ACK] [AXI_ADDR_B3..B0 x4 bytes] [ACK]...
//     [RSTART] [DEV_ADDR(7b)+R] [ACK] [DATA_B3] [ACK]...[DATA_B0] [NACK] [STOP]
// =============================================================================

`timescale 1ns/1ps

module i2c_slave_ctrl #(
    parameter SLAVE_ADDR = 7'h50    // Default I2C slave address
)(
    input  wire        clk,
    input  wire        rst_n,

    // I2C Interface (open-drain modeled as in/out/oe)
    input  wire        scl_i,
    input  wire        sda_i,
    output reg         sda_oe,     // 1 = drive SDA low (open-drain)

    // AXI4-Lite Master command interface
    output reg  [31:0] axi_addr,
    output reg  [31:0] axi_wdata,
    output reg  [3:0]  axi_wstrb,
    output reg         axi_wr_req,
    output reg         axi_rd_req,
    input  wire [31:0] axi_rdata,
    input  wire        axi_wr_done,
    input  wire        axi_rd_done,
    input  wire        axi_error
);

// -----------------------------------------------------------------------
// Synchronise SDA/SCL into local clock domain (2FF)
// -----------------------------------------------------------------------
reg [1:0] scl_sync, sda_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin scl_sync <= 2'b11; sda_sync <= 2'b11; end
    else begin
        scl_sync <= {scl_sync[0], scl_i};
        sda_sync <= {sda_sync[0], sda_i};
    end
end

wire scl = scl_sync[1];
wire sda = sda_sync[1];

// Edge detect
reg scl_d, sda_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin scl_d <= 1'b1; sda_d <= 1'b1; end
    else begin scl_d <= scl; sda_d <= sda; end
end

wire scl_rise  = ( scl && !scl_d);
wire scl_fall  = (!scl &&  scl_d);
wire start_det = (!sda &&  sda_d && scl);   // SDA fall while SCL high
wire stop_det  = ( sda && !sda_d && scl);   // SDA rise while SCL high

// -----------------------------------------------------------------------
// State machine
// -----------------------------------------------------------------------
localparam  ST_IDLE        = 4'd0,
            ST_DEV_ADDR    = 4'd1,
            ST_DEV_ACK     = 4'd2,
            ST_AXI_ADDR    = 4'd3,
            ST_AXI_ADDR_ACK= 4'd4,
            ST_WR_DATA     = 4'd5,
            ST_WR_ACK      = 4'd6,
            ST_AXI_WR      = 4'd7,
            ST_AXI_RD      = 4'd8,
            ST_RD_DATA     = 4'd9,
            ST_RD_ACK      = 4'd10,
            ST_RSTART_WAIT = 4'd11;

reg [3:0]  state;
reg [2:0]  bit_cnt;        // counts 0..7
reg [7:0]  shift_reg;      // shift register for incoming byte
reg        rw_bit;         // 0=write, 1=read from first byte
reg [1:0]  byte_cnt;       // counts address/data bytes (0..3)
reg [31:0] addr_buf;
reg [31:0] wdata_buf;

// -----------------------------------------------------------------------
// Main FSM (SCL-edge driven)
// -----------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= ST_IDLE;
        bit_cnt    <= 3'd0;
        shift_reg  <= 8'd0;
        rw_bit     <= 1'b0;
        byte_cnt   <= 2'd0;
        addr_buf   <= 32'd0;
        wdata_buf  <= 32'd0;
        sda_oe     <= 1'b0;
        axi_addr   <= 32'd0;
        axi_wdata  <= 32'd0;
        axi_wstrb  <= 4'hF;
        axi_wr_req <= 1'b0;
        axi_rd_req <= 1'b0;
    end else begin
        // Default: deassert one-cycle pulses
        axi_wr_req <= 1'b0;
        axi_rd_req <= 1'b0;

        // ---- STOP / START overrides ----
        if (stop_det) begin
            state   <= ST_IDLE;
            sda_oe  <= 1'b0;
        end else if (start_det) begin
            // Could be START or repeated START
            state   <= ST_DEV_ADDR;
            bit_cnt <= 3'd7;
            sda_oe  <= 1'b0;
        end else begin
            case (state)
                // --------------------------------------------------
                ST_IDLE: ; // wait for start_det

                // --------------------------------------------------
                // Receive 7-bit slave address + R/W bit
                ST_DEV_ADDR: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda};
                        if (bit_cnt == 3'd0) begin
                            // Full byte received
                            if (shift_reg[7:1] == SLAVE_ADDR) begin
                                rw_bit  <= shift_reg[0];
                                state   <= ST_DEV_ACK;
                                sda_oe  <= 1'b1;  // pull SDA low for ACK
                            end else begin
                                state   <= ST_IDLE; // not our address
                            end
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                    if (scl_fall && state == ST_DEV_ACK) begin
                        sda_oe  <= 1'b0;  // release after ACK clock
                        bit_cnt <= 3'd7;
                        if (rw_bit) begin
                            // READ: transmit data
                            state    <= ST_AXI_RD;
                        end else begin
                            // WRITE: receive AXI address
                            byte_cnt <= 2'd3;
                            state    <= ST_AXI_ADDR;
                        end
                    end
                end

                // --------------------------------------------------
                // ACK for device address
                ST_DEV_ACK: begin
                    // Handled above in scl_fall of ST_DEV_ADDR
                end

                // --------------------------------------------------
                // Receive 4-byte AXI address (MSB first)
                ST_AXI_ADDR: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda};
                        if (bit_cnt == 3'd0) begin
                            addr_buf <= {addr_buf[23:0], shift_reg[6:0], sda};
                            state    <= ST_AXI_ADDR_ACK;
                            sda_oe   <= 1'b1;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                    if (scl_fall && state == ST_AXI_ADDR_ACK) begin
                        sda_oe  <= 1'b0;
                        bit_cnt <= 3'd7;
                        if (byte_cnt == 2'd0) begin
                            // All 4 address bytes received
                            axi_addr <= addr_buf;
                            byte_cnt <= 2'd3;
                            state    <= ST_WR_DATA;
                        end else begin
                            byte_cnt <= byte_cnt - 1'b1;
                            state    <= ST_AXI_ADDR;
                        end
                    end
                end

                ST_AXI_ADDR_ACK: ; // handled in scl_fall above

                // --------------------------------------------------
                // Receive 4-byte write data
                ST_WR_DATA: begin
                    if (scl_rise) begin
                        shift_reg <= {shift_reg[6:0], sda};
                        if (bit_cnt == 3'd0) begin
                            wdata_buf <= {wdata_buf[23:0], shift_reg[6:0], sda};
                            state     <= ST_WR_ACK;
                            sda_oe    <= 1'b1;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                    if (scl_fall && state == ST_WR_ACK) begin
                        sda_oe  <= 1'b0;
                        bit_cnt <= 3'd7;
                        if (byte_cnt == 2'd0) begin
                            axi_wdata  <= wdata_buf;
                            axi_wstrb  <= 4'hF;
                            state      <= ST_AXI_WR;
                        end else begin
                            byte_cnt <= byte_cnt - 1'b1;
                            state    <= ST_WR_DATA;
                        end
                    end
                end

                ST_WR_ACK: ; // handled above

                // --------------------------------------------------
                // Issue AXI write, wait for done
                ST_AXI_WR: begin
                    axi_wr_req <= 1'b1;
                    if (axi_wr_done || axi_error)
                        state <= ST_IDLE;
                end

                // --------------------------------------------------
                // Issue AXI read, wait for data
                ST_AXI_RD: begin
                    axi_rd_req <= 1'b1;
                    if (axi_rd_done || axi_error) begin
                        wdata_buf <= axi_rdata;
                        byte_cnt  <= 2'd3;
                        bit_cnt   <= 3'd7;
                        state     <= ST_RD_DATA;
                    end
                end

                // --------------------------------------------------
                // Transmit 4-byte read data (MSB first)
                ST_RD_DATA: begin
                    // On each SCL fall we shift out next bit
                    if (scl_fall) begin
                        // Determine current bit to output
                        case (byte_cnt)
                            2'd3: sda_oe <= ~wdata_buf[{bit_cnt}+24];
                            2'd2: sda_oe <= ~wdata_buf[{bit_cnt}+16];
                            2'd1: sda_oe <= ~wdata_buf[{bit_cnt}+8];
                            2'd0: sda_oe <= ~wdata_buf[{bit_cnt}];
                        endcase
                        // After sending 8 bits, release for ACK
                        if (bit_cnt == 3'd0) begin
                            sda_oe  <= 1'b0;
                            state   <= ST_RD_ACK;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end

                // --------------------------------------------------
                // Sample ACK from master after each read byte
                ST_RD_ACK: begin
                    if (scl_rise) begin
                        if (sda || byte_cnt == 2'd0) begin
                            // NACK or last byte -> done
                            state <= ST_IDLE;
                        end else begin
                            byte_cnt <= byte_cnt - 1'b1;
                            bit_cnt  <= 3'd7;
                            state    <= ST_RD_DATA;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
end

endmodule
