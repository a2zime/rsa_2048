// Minimal debug testbench for mod_exp — no VCD, direct $display diagnostics
`timescale 1ns / 1ps

module tb_mod_exp_debug;

  import rsa_pkg::*;

  localparam int CLK_HALF = 5;

  logic clk, rst_n;
  initial clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  // ----- Signals -----
  logic        me_start, me_crt_mode, me_done, me_busy;
  logic        me_mem_we;
  logic [9:0]  me_mem_addr;
  logic [31:0] me_mem_rdata, me_mem_wdata;
  logic        me_mont_start, me_mont_mode;
  logic        me_mont_done, me_mont_busy;
  logic [31:0] mm_n_prime;
  logic        mm_mem_we;
  logic [9:0]  mm_mem_addr;
  logic [31:0] mm_mem_rdata, mm_mem_wdata;
  logic [31:0] mul_a, mul_b, mul_c;
  logic        mul_start, mul_done;
  logic [63:0] mul_result;
  logic        tb_a_we;
  logic [9:0]  tb_a_addr;
  logic [31:0] tb_a_wdata;
  logic [31:0] tb_a_rdata;
  logic [31:0] tb_n_prime;

  // Port A mux
  wire        a_we    = me_busy ? me_mem_we    : tb_a_we;
  wire [9:0]  a_addr  = me_busy ? me_mem_addr  : tb_a_addr;
  wire [31:0] a_wdata = me_busy ? me_mem_wdata : tb_a_wdata;
  wire [31:0] a_rdata;
  assign me_mem_rdata = a_rdata;
  assign tb_a_rdata   = a_rdata;

  // ----- Instantiations -----
  mod_exp u_dut (
    .clk_i(clk), .rst_ni(rst_n),
    .start_i(me_start), .crt_mode_i(me_crt_mode),
    .done_o(me_done), .busy_o(me_busy),
    .mem_re_o(), .mem_we_o(me_mem_we),
    .mem_addr_o(me_mem_addr), .mem_rdata_i(me_mem_rdata),
    .mem_wdata_o(me_mem_wdata),
    .mont_start_o(me_mont_start), .mont_mode_o(me_mont_mode),
    .mont_done_i(me_mont_done), .mont_busy_i(me_mont_busy)
  );

  mont_mul #(.MaxWords(64), .WordWidth(32)) u_mont (
    .clk_i(clk), .rst_ni(rst_n),
    .start_i(me_mont_start), .half_mode_i(me_mont_mode),
    .done_o(me_mont_done), .busy_o(me_mont_busy),
    .mem_re_o(), .mem_we_o(mm_mem_we),
    .mem_addr_o(mm_mem_addr), .mem_rdata_i(mm_mem_rdata),
    .mem_wdata_o(mm_mem_wdata),
    .n_prime_i(tb_n_prime),
    .mul_a_o(mul_a), .mul_b_o(mul_b), .mul_c_o(mul_c),
    .mul_start_o(mul_start), .mul_result_i(mul_result), .mul_done_i(mul_done)
  );

  mul_add_unit #(.WordWidth(32)) u_mau (
    .clk_i(clk), .rst_ni(rst_n),
    .a_i(mul_a), .b_i(mul_b), .c_i(mul_c),
    .start_i(mul_start), .result_o(mul_result), .done_o(mul_done)
  );

  operand_mem #(.WordWidth(32), .Depth(1024)) u_mem (
    .clk_i(clk), .rst_ni(rst_n),
    .a_we_i(a_we), .a_addr_i(a_addr), .a_wdata_i(a_wdata), .a_rdata_o(a_rdata),
    .b_we_i(mm_mem_we), .b_addr_i(mm_mem_addr),
    .b_wdata_i(mm_mem_wdata), .b_rdata_o(mm_mem_rdata)
  );

  // ----- Helpers -----
  task automatic mem_write(input logic [9:0] addr, input logic [31:0] data);
    tb_a_we = 1; tb_a_addr = addr; tb_a_wdata = data;
    @(posedge clk); #1;
    tb_a_we = 0;
  endtask

  task automatic mem_read(input logic [9:0] addr, output logic [31:0] data);
    tb_a_addr = addr;
    @(posedge clk); #1;
    data = tb_a_rdata;
  endtask

  // ----- Test vectors (small 32-bit case for fast sim) -----
  // We'll use inline values for a TINY known test:
  // n must be 2048-bit odd with MSB=1, base=0, e=65537 → result=0
  // To speed up debugging, use half-mode (1024-bit) where possible.
  // Actually let's just load from hex files but test ME-08 (base=1, result=1).
  localparam int NUM_FULL_TC = 23;
  localparam int WORDS_FULL  = 64;
  logic [31:0] tv_full_base   [0:NUM_FULL_TC*WORDS_FULL-1];
  logic [31:0] tv_full_exp_v  [0:NUM_FULL_TC*WORDS_FULL-1];
  logic [31:0] tv_full_n      [0:NUM_FULL_TC*WORDS_FULL-1];
  logic [31:0] tv_full_np     [0:NUM_FULL_TC-1];
  logic [31:0] tv_full_rsq    [0:NUM_FULL_TC*WORDS_FULL-1];
  logic [31:0] tv_full_result [0:NUM_FULL_TC*WORDS_FULL-1];

  initial begin
    $readmemh("tb/common/test_vectors/me_full_base.hex",   tv_full_base);
    $readmemh("tb/common/test_vectors/me_full_exp.hex",    tv_full_exp_v);
    $readmemh("tb/common/test_vectors/me_full_n.hex",      tv_full_n);
    $readmemh("tb/common/test_vectors/me_full_np.hex",     tv_full_np);
    $readmemh("tb/common/test_vectors/me_full_rsq.hex",    tv_full_rsq);
    $readmemh("tb/common/test_vectors/me_full_result.hex", tv_full_result);
  end

  // ----- Watchdog -----
  initial begin : watchdog_80m
    #800000000;  // 80M cycles * 10ns
    $display("WD@80M: me_busy=%b me_done=%b me_mont_busy=%b",
             me_busy, me_done, me_mont_busy);
    $display("  mod_exp state_q = %0d", u_dut.state_q);
    $display("  mont_mul state_q = %0d, i_q = %0d, j_q = %0d",
             u_mont.state_q, u_mont.i_q, u_mont.j_q);
    $display("  mont_mul bi_q = 0x%08h", u_mont.bi_q);
  end

  initial begin : watchdog_200m
    #2000000000;  // 200M cycles * 10ns
    $display("WD@200M: me_busy=%b me_done=%b me_mont_busy=%b",
             me_busy, me_done, me_mont_busy);
    $display("  mod_exp state_q = %0d", u_dut.state_q);
    $display("  mont_mul state_q = %0d, i_q = %0d, j_q = %0d",
             u_mont.state_q, u_mont.i_q, u_mont.j_q);
    $finish;
  end

  // ----- Main -----
  initial begin : main
    logic [31:0] rdata;
    int tc;

    rst_n = 0; me_start = 0; me_crt_mode = 0;
    tb_a_we = 0; tb_a_addr = 0; tb_a_wdata = 0; tb_n_prime = 0;
    repeat(10) @(posedge clk); #1;
    rst_n = 1;
    repeat(3)  @(posedge clk); #1;

    // Use ME-01 TC0 (base=random, e=65537): result should be pow(base,65537,n)
    // index 0 = TC_ME01_FIRST
    tc = 0;

    // Write base
    $display("Setting up TC=%0d (ME-01: base=random, e=65537)", tc);
    for (int w = 0; w < 64; w++)
      mem_write(10'(ADDR_BASE) + 10'(w), tv_full_base[tc*64 + w]);
    // Write exp
    for (int w = 0; w < 64; w++)
      mem_write(10'(ADDR_EXP)  + 10'(w), tv_full_exp_v[tc*64 + w]);
    // Write n
    for (int w = 0; w < 64; w++)
      mem_write(10'(ADDR_MOD)  + 10'(w), tv_full_n[tc*64 + w]);
    // Write R^2
    for (int w = 0; w < 64; w++)
      mem_write(10'(ADDR_RSQ)  + 10'(w), tv_full_rsq[tc*64 + w]);
    tb_n_prime = tv_full_np[tc];

    // Verify setup by reading back some values
    $display("Verifying setup...");
    mem_read(10'(ADDR_BASE), rdata);
    $display("  ADDR_BASE[0]    = 0x%08h  (exp=0x%08h)", rdata, tv_full_base[tc*64]);
    mem_read(10'(ADDR_MOD), rdata);
    $display("  ADDR_MOD[0]     = 0x%08h  (exp=0x%08h)", rdata, tv_full_n[tc*64]);
    mem_read(10'(ADDR_RSQ), rdata);
    $display("  ADDR_RSQ[0]     = 0x%08h  (exp=0x%08h)", rdata, tv_full_rsq[tc*64]);
    $display("  tb_n_prime      = 0x%08h  (exp=0x%08h)", tb_n_prime, tv_full_np[tc]);
    $display("  expected result[0] = 0x%08h", tv_full_result[tc*64]);

    // Run mod_exp
    $display("Starting mod_exp...");
    me_crt_mode = 0;
    me_start = 1;
    @(posedge clk); #1;
    me_start = 0;
    while (!me_done) begin
      @(posedge clk); #1;
    end
    $display("done_o fired.");

    // Read result
    $display("Reading ADDR_RESULT...");
    for (int w = 0; w < 4; w++) begin
      mem_read(10'(ADDR_RESULT) + 10'(w), rdata);
      $display("  ADDR_RESULT[%0d] = 0x%08h  exp=0x%08h  %s",
               w, rdata, tv_full_result[tc*64 + w],
               (rdata === tv_full_result[tc*64 + w]) ? "PASS" : "FAIL");
    end
    // Also read ADDR_BASE (the accumulator) for debugging
    $display("Reading ADDR_BASE (last result_mont before FromMont)...");
    for (int w = 0; w < 4; w++) begin
      mem_read(10'(ADDR_BASE) + 10'(w), rdata);
      $display("  ADDR_BASE[%0d]   = 0x%08h", w, rdata);
    end
    $display("Reading ADDR_MONT_T (T[] after FromMont, before StExpDone copy)...");
    // T might be 0 since StExpDone copies T→RESULT... let's see
    for (int w = 0; w < 4; w++) begin
      mem_read(10'(ADDR_MONT_T) + 10'(w), rdata);
      $display("  ADDR_MONT_T[%0d] = 0x%08h", w, rdata);
    end

    $display("DEBUG done.");
    $finish;
  end

endmodule
