// Description: Testbench for operand_mem
//   Covers MEM-01 through MEM-08 from verification_spec.md §5.5.
//   MEM-06 is verified by an assertion that fires $fatal on conflict.
//   MEM-08 is informational only (BRAM not reset — X is expected in simulation).
`timescale 1ns / 1ps

module tb_operand_mem;

  // -----------------------------------------------------------------
  // Parameters
  // -----------------------------------------------------------------
  localparam int CLK_HALF = 5;     // 10 ns period = 100 MHz
  localparam int DEPTH    = 1024;
  localparam int AW       = 10;    // $clog2(1024) = 10

  // -----------------------------------------------------------------
  // Clock / reset
  // -----------------------------------------------------------------
  logic clk, rst_n;
  initial clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  logic          a_we_i;
  logic [AW-1:0] a_addr_i;
  logic [31:0]   a_wdata_i;
  logic [31:0]   a_rdata_o;

  logic          b_we_i;
  logic [AW-1:0] b_addr_i;
  logic [31:0]   b_wdata_i;
  logic [31:0]   b_rdata_o;

  operand_mem #(.WordWidth(32), .Depth(DEPTH)) dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .a_we_i    (a_we_i),
    .a_addr_i  (a_addr_i),
    .a_wdata_i (a_wdata_i),
    .a_rdata_o (a_rdata_o),
    .b_we_i    (b_we_i),
    .b_addr_i  (b_addr_i),
    .b_wdata_i (b_wdata_i),
    .b_rdata_o (b_rdata_o)
  );

  // -----------------------------------------------------------------
  // Waveform dump
  // -----------------------------------------------------------------
  initial begin
    $dumpfile("tb_operand_mem.vcd");
    $dumpvars(0, tb_operand_mem);
  end

  // -----------------------------------------------------------------
  // Pass / fail counters (module-level for visibility in all tasks)
  // -----------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  // -----------------------------------------------------------------
  // MEM-06: concurrent write to same address assertion
  //   Fires $fatal if both ports write the same address simultaneously.
  //   This is design-prohibited (guaranteed by rsa_top FSM).
  // -----------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (a_we_i && b_we_i && (a_addr_i == b_addr_i)) begin
      $fatal(1, "ASSERT MEM-06  simultaneous write conflict at addr=0x%03h", a_addr_i);
    end
  end

  // -----------------------------------------------------------------
  // Task: write one word via Port A
  // -----------------------------------------------------------------
  task automatic write_a(input logic [AW-1:0] addr, input logic [31:0] data);
    a_we_i    = 1'b1;
    a_addr_i  = addr;
    a_wdata_i = data;
    @(posedge clk); #1;
    a_we_i = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // Task: write one word via Port B
  // -----------------------------------------------------------------
  task automatic write_b(input logic [AW-1:0] addr, input logic [31:0] data);
    b_we_i    = 1'b1;
    b_addr_i  = addr;
    b_wdata_i = data;
    @(posedge clk); #1;
    b_we_i = 1'b0;
  endtask

  // -----------------------------------------------------------------
  // Task: read one word via Port A (data stable 1 cycle after address)
  // -----------------------------------------------------------------
  task automatic read_a(input logic [AW-1:0] addr, output logic [31:0] data);
    a_addr_i = addr;
    @(posedge clk); #1;
    data = a_rdata_o;
  endtask

  // -----------------------------------------------------------------
  // Task: read one word via Port B
  // -----------------------------------------------------------------
  task automatic read_b(input logic [AW-1:0] addr, output logic [31:0] data);
    b_addr_i = addr;
    @(posedge clk); #1;
    data = b_rdata_o;
  endtask

  // -----------------------------------------------------------------
  // Task: compare 32-bit result, update counters
  // -----------------------------------------------------------------
  task automatic check32(
    input logic [31:0] got,
    input logic [31:0] exp,
    input string       label
  );
    if (got === exp) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL %-14s got=0x%08h  exp=0x%08h", label, got, exp);
    end
  endtask

  // -----------------------------------------------------------------
  // Main test sequence
  // -----------------------------------------------------------------
  initial begin : main
    logic [31:0] rdata, rdata_a, rdata_b;

    // -- Initialise signals
    a_we_i    = 1'b0; a_addr_i  = '0; a_wdata_i = '0;
    b_we_i    = 1'b0; b_addr_i  = '0; b_wdata_i = '0;
    rst_n     = 1'b0;
    repeat (4) @(posedge clk); #1;
    rst_n = 1'b1;
    @(posedge clk); #1;

    // ==================================================================
    // MEM-01: Port A write → read (5 cases)
    // ==================================================================
    write_a(10'd10,  32'hDEAD_BEEF); read_a(10'd10,  rdata); check32(rdata, 32'hDEAD_BEEF, "MEM-01");
    write_a(10'd20,  32'h0000_0001); read_a(10'd20,  rdata); check32(rdata, 32'h0000_0001, "MEM-01");
    write_a(10'd100, 32'hFFFF_FFFF); read_a(10'd100, rdata); check32(rdata, 32'hFFFF_FFFF, "MEM-01");
    write_a(10'd255, 32'h1234_5678); read_a(10'd255, rdata); check32(rdata, 32'h1234_5678, "MEM-01");
    write_a(10'd512, 32'hA5A5_A5A5); read_a(10'd512, rdata); check32(rdata, 32'hA5A5_A5A5, "MEM-01");

    // ==================================================================
    // MEM-02: Port B write → read (5 cases)
    // ==================================================================
    write_b(10'd11,  32'hCAFE_BABE); read_b(10'd11,  rdata); check32(rdata, 32'hCAFE_BABE, "MEM-02");
    write_b(10'd21,  32'hBEEF_CAFE); read_b(10'd21,  rdata); check32(rdata, 32'hBEEF_CAFE, "MEM-02");
    write_b(10'd101, 32'h0000_0000); read_b(10'd101, rdata); check32(rdata, 32'h0000_0000, "MEM-02");
    write_b(10'd256, 32'hF0F0_F0F0); read_b(10'd256, rdata); check32(rdata, 32'hF0F0_F0F0, "MEM-02");
    write_b(10'd513, 32'h0101_0101); read_b(10'd513, rdata); check32(rdata, 32'h0101_0101, "MEM-02");

    // ==================================================================
    // MEM-03: 1-cycle read latency
    //   Write to addr 200, then present read address and check that
    //   a_rdata_o is valid exactly 1 posedge later.
    // ==================================================================
    write_a(10'd200, 32'hC0DE_C0DE);
    a_addr_i = 10'd200;           // present read address
    @(posedge clk); #1;           // exactly 1 cycle
    if (a_rdata_o === 32'hC0DE_C0DE) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL MEM-03     1-cycle latency: got=0x%08h  exp=0x%08h",
               a_rdata_o, 32'hC0DE_C0DE);
    end

    // ==================================================================
    // MEM-04: Port A/B different addresses simultaneous write (5 cases)
    // ==================================================================
    for (int i = 0; i < 5; i++) begin
      // Simultaneous write to different addresses (MEM-06 assertion: addr_a != addr_b)
      a_we_i    = 1'b1; a_addr_i  = 10'(300 + i); a_wdata_i = 32'hAAAA_0000 | 32'(i);
      b_we_i    = 1'b1; b_addr_i  = 10'(400 + i); b_wdata_i = 32'hBBBB_0000 | 32'(i);
      @(posedge clk); #1;
      a_we_i = 1'b0; b_we_i = 1'b0;
      read_a(10'(300 + i), rdata_a); check32(rdata_a, 32'hAAAA_0000 | 32'(i), "MEM-04-A");
      read_b(10'(400 + i), rdata_b); check32(rdata_b, 32'hBBBB_0000 | 32'(i), "MEM-04-B");
    end

    // ==================================================================
    // MEM-05: Port A/B same address simultaneous read (3 cases)
    //   Both rdata outputs must return the same value.
    // ==================================================================
    write_a(10'd500, 32'h1111_1111);
    a_addr_i = 10'd500; b_addr_i = 10'd500;
    @(posedge clk); #1;
    if (a_rdata_o === b_rdata_o) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL MEM-05     addr=500: a_rdata=0x%08h != b_rdata=0x%08h",
               a_rdata_o, b_rdata_o);
    end

    write_a(10'd501, 32'h2222_2222);
    a_addr_i = 10'd501; b_addr_i = 10'd501;
    @(posedge clk); #1;
    if (a_rdata_o === b_rdata_o) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL MEM-05     addr=501: a_rdata=0x%08h != b_rdata=0x%08h",
               a_rdata_o, b_rdata_o);
    end

    write_a(10'd502, 32'h3333_3333);
    a_addr_i = 10'd502; b_addr_i = 10'd502;
    @(posedge clk); #1;
    if (a_rdata_o === b_rdata_o) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL MEM-05     addr=502: a_rdata=0x%08h != b_rdata=0x%08h",
               a_rdata_o, b_rdata_o);
    end

    // ==================================================================
    // MEM-07: Boundary addresses (addr=0, addr=Depth-1=1023)
    //   Both Port A and Port B are verified at addr=1023.
    // ==================================================================
    write_a(10'd0,    32'hBEEF_0000); read_a(10'd0,    rdata); check32(rdata, 32'hBEEF_0000, "MEM-07-A-lo");
    write_a(10'd1023, 32'hBEEF_A3FF); read_a(10'd1023, rdata); check32(rdata, 32'hBEEF_A3FF, "MEM-07-A-hi");
    write_b(10'd1023, 32'hBEEF_B3FF); read_b(10'd1023, rdata); check32(rdata, 32'hBEEF_B3FF, "MEM-07-B-hi");

    // ==================================================================
    // MEM-08: Post-reset content (informational — BRAM not reset)
    //   addr=999 is never written in this test; rdata is X in simulation.
    //   No pass/fail counted; waveform inspection confirms X is expected.
    // ==================================================================
    a_addr_i = 10'd999;
    @(posedge clk); #1;
    $display("INFO MEM-08     uninit read addr=999 rdata=0x%08h  (X expected in simulation)",
             a_rdata_o);

    // ==================================================================
    // Final report
    // ==================================================================
    $display("");
    $display("==================================================");
    if (fail_cnt == 0) begin
      $display("TEST PASSED  %0d / %0d checks", pass_cnt, pass_cnt);
    end else begin
      $display("TEST FAILED  pass=%0d  fail=%0d", pass_cnt, fail_cnt);
    end
    $display("==================================================");
    $finish;
  end

  // -----------------------------------------------------------------
  // Timeout watchdog (prevent infinite loop on DUT hang)
  // -----------------------------------------------------------------
  initial begin
    #(5000 * 2 * CLK_HALF);
    $display("TIMEOUT: simulation exceeded limit");
    $finish;
  end

endmodule
