// Description: Dual-port BRAM operand storage
//   Stores all operands, intermediate values, and computation results.
//   Port A: used by io_controller / crt_controller (read/write)
//   Port B: used by mont_mul (read/write)

module operand_mem #(
  parameter int unsigned WordWidth = 32,
  parameter int unsigned Depth     = 1024
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,
  // Port A (read/write — used by io_controller / crt_controller)
  input  logic                       a_we_i,
  input  logic [$clog2(Depth)-1:0]   a_addr_i,
  input  logic [WordWidth-1:0]       a_wdata_i,
  output logic [WordWidth-1:0]       a_rdata_o,
  // Port B (read/write — used by mont_mul)
  input  logic                       b_we_i,
  input  logic [$clog2(Depth)-1:0]   b_addr_i,
  input  logic [WordWidth-1:0]       b_wdata_i,
  output logic [WordWidth-1:0]       b_rdata_o
);

  // BRAM array
  logic [WordWidth-1:0] mem [Depth];

  // Port A: synchronous read/write
  always_ff @(posedge clk_i) begin
    if (a_we_i) begin
      mem[a_addr_i] <= a_wdata_i;
    end
    a_rdata_o <= mem[a_addr_i];
  end

  // Port B: synchronous read/write
  always_ff @(posedge clk_i) begin
    if (b_we_i) begin
      mem[b_addr_i] <= b_wdata_i;
    end
    b_rdata_o <= mem[b_addr_i];
  end

  // rst_ni does not reset memory contents in BRAM (convention for FPGA BRAM)
  // No reset logic is included so the synthesis tool can infer BRAM primitives

endmodule
