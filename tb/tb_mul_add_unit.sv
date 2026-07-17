// Description: Testbench for mul_add_unit
//   Covers MAU-01 through MAU-09 from verification_spec.md §5.1.
//   MAU-10 is excluded (input stability is caller responsibility, not DUT).
`timescale 1ns / 1ps

module tb_mul_add_unit;

  // -----------------------------------------------------------------
  // Parameters
  // -----------------------------------------------------------------
  localparam int CLK_HALF = 5;   // 10 ns period = 100 MHz

  localparam int NUM_TC          = 112;
  localparam int TC_MAU01        = 0;
  localparam int TC_MAU02_FIRST  = 1;
  localparam int TC_MAU02_LAST   = 100;
  localparam int TC_MAU03_FIRST  = 101;
  localparam int TC_MAU03_LAST   = 105;
  localparam int TC_MAU04_FIRST  = 106;
  localparam int TC_MAU04_LAST   = 110;
  localparam int TC_MAU05        = 111;
  localparam int EXPECTED_CYCLES = 5;  // MAU-07: start→done inclusive

  // -----------------------------------------------------------------
  // Clock / reset
  // -----------------------------------------------------------------
  logic clk, rst_n;
  initial clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  // -----------------------------------------------------------------
  // DUT
  // -----------------------------------------------------------------
  logic [31:0] a_i, b_i, c_i;
  logic        start_i;
  logic [63:0] result_o;
  logic        done_o;

  mul_add_unit #(.WordWidth(32)) dut (
    .clk_i    (clk),
    .rst_ni   (rst_n),
    .a_i      (a_i),
    .b_i      (b_i),
    .c_i      (c_i),
    .start_i  (start_i),
    .result_o (result_o),
    .done_o   (done_o)
  );

  // -----------------------------------------------------------------
  // Test vectors
  // -----------------------------------------------------------------
  logic [31:0] tv_a     [0:NUM_TC-1];
  logic [31:0] tv_b     [0:NUM_TC-1];
  logic [31:0] tv_c     [0:NUM_TC-1];
  logic [31:0] tv_exp_lo[0:NUM_TC-1];
  logic [31:0] tv_exp_hi[0:NUM_TC-1];

  initial begin
    $readmemh("tb/common/test_vectors/mau_tv_a.hex",      tv_a);
    $readmemh("tb/common/test_vectors/mau_tv_b.hex",      tv_b);
    $readmemh("tb/common/test_vectors/mau_tv_c.hex",      tv_c);
    $readmemh("tb/common/test_vectors/mau_tv_exp_lo.hex", tv_exp_lo);
    $readmemh("tb/common/test_vectors/mau_tv_exp_hi.hex", tv_exp_hi);
  end

  // -----------------------------------------------------------------
  // Waveform dump
  // -----------------------------------------------------------------
  initial begin
    $dumpfile("tb_mul_add_unit.vcd");
    $dumpvars(0, tb_mul_add_unit);
  end

  // -----------------------------------------------------------------
  // Pass / fail counters (module-level for visibility in all tasks)
  // -----------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  // -----------------------------------------------------------------
  // Task: apply one test case, wait for done_o, return result/cycles
  //
  //   Cycle counting (MAU-07):
  //     cnt=1 at the posedge where start_i is sampled (T)
  //     cnt=5 at the posedge where done_o fires    (T+4)
  //   → cycles=5 matches the "5 サイクルレイテンシ" spec.
  // -----------------------------------------------------------------
  task automatic run_tc(
    input  logic [31:0] a, b, c,
    output logic [63:0] result,
    output int          cycles
  );
    int cnt;
    a_i     = a;
    b_i     = b;
    c_i     = c;
    start_i = 1'b1;
    cnt     = 0;
    @(posedge clk); #1; cnt++;  // T: start_i sampled by DUT
    start_i = 1'b0;
    while (!done_o) begin
      @(posedge clk); #1; cnt++;
    end
    result = result_o;
    cycles = cnt;
  endtask

  // -----------------------------------------------------------------
  // Task: compare result against expected, update counters
  // -----------------------------------------------------------------
  task automatic check_result(
    input logic [63:0] got,
    input logic [63:0] exp,
    input string       label
  );
    if (got === exp) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL %-12s got=0x%016h  exp=0x%016h", label, got, exp);
    end
  endtask

  // -----------------------------------------------------------------
  // Task: check cycle latency
  // -----------------------------------------------------------------
  task automatic check_cycles(
    input int got,
    input int exp,
    input string label
  );
    if (got === exp) begin
      pass_cnt++;
    end else begin
      fail_cnt++;
      $display("FAIL %-12s latency got=%0d  exp=%0d", label, got, exp);
    end
  endtask

  // -----------------------------------------------------------------
  // Main test sequence
  // -----------------------------------------------------------------
  initial begin : main
    logic [63:0] res;
    logic [63:0] exp;
    int          cyc;

    // -- Initialise signals
    a_i = '0; b_i = '0; c_i = '0; start_i = 1'b0;
    rst_n = 1'b0;
    repeat (4) @(posedge clk); #1;
    rst_n = 1'b1;
    @(posedge clk); #1;

    // ==================================================================
    // MAU-01: basic multiply-only
    // ==================================================================
    run_tc(tv_a[TC_MAU01], tv_b[TC_MAU01], tv_c[TC_MAU01], res, cyc);
    exp = {tv_exp_hi[TC_MAU01], tv_exp_lo[TC_MAU01]};
    check_result(res, exp, "MAU-01");

    // ==================================================================
    // MAU-07: 5-cycle latency — measured from the MAU-01 run above,
    //         plus one dedicated re-run for an explicit count check.
    // ==================================================================
    run_tc(tv_a[TC_MAU01], tv_b[TC_MAU01], tv_c[TC_MAU01], res, cyc);
    check_cycles(cyc, EXPECTED_CYCLES, "MAU-07");

    // ==================================================================
    // MAU-02: 100 random cases
    // ==================================================================
    for (int i = TC_MAU02_FIRST; i <= TC_MAU02_LAST; i++) begin
      run_tc(tv_a[i], tv_b[i], tv_c[i], res, cyc);
      exp = {tv_exp_hi[i], tv_exp_lo[i]};
      check_result(res, exp, "MAU-02");
    end

    // ==================================================================
    // MAU-03: a=0  →  result must equal c
    // ==================================================================
    for (int i = TC_MAU03_FIRST; i <= TC_MAU03_LAST; i++) begin
      run_tc(tv_a[i], tv_b[i], tv_c[i], res, cyc);
      exp = {tv_exp_hi[i], tv_exp_lo[i]};
      check_result(res, exp, "MAU-03");
      // Additional check: result == zero-extended c
      if (res !== {32'h0, tv_c[i]}) begin
        fail_cnt++;
        $display("FAIL MAU-03     result != c: got=0x%016h  c=0x%08h", res, tv_c[i]);
      end else begin
        pass_cnt++;
      end
    end

    // ==================================================================
    // MAU-04: b=0  →  result must equal c
    // ==================================================================
    for (int i = TC_MAU04_FIRST; i <= TC_MAU04_LAST; i++) begin
      run_tc(tv_a[i], tv_b[i], tv_c[i], res, cyc);
      exp = {tv_exp_hi[i], tv_exp_lo[i]};
      check_result(res, exp, "MAU-04");
      if (res !== {32'h0, tv_c[i]}) begin
        fail_cnt++;
        $display("FAIL MAU-04     result != c: got=0x%016h  c=0x%08h", res, tv_c[i]);
      end else begin
        pass_cnt++;
      end
    end

    // ==================================================================
    // MAU-05: max inputs  (a=b=c=0xFFFFFFFF)
    //   Python ref: (2^32-1)*2^32 = 0xFFFFFFFF_00000000
    //   Note: verification_spec.md §5.1 MAU-05 lists 0xFFFFFFFE_0000_0000
    //   which is incorrect; Python reference is authoritative (Issue to be raised).
    // ==================================================================
    run_tc(tv_a[TC_MAU05], tv_b[TC_MAU05], tv_c[TC_MAU05], res, cyc);
    exp = {tv_exp_hi[TC_MAU05], tv_exp_lo[TC_MAU05]};
    check_result(res, exp, "MAU-05");

    // ==================================================================
    // MAU-06: no X/Z in result
    // ==================================================================
    if (^res === 1'bx) begin
      fail_cnt++;
      $display("FAIL MAU-06     result contains X/Z: 0x%016h", res);
    end else begin
      pass_cnt++;
    end

    // ==================================================================
    // MAU-08: consecutive execution (5 back-to-back cases)
    // ==================================================================
    for (int i = TC_MAU02_FIRST; i <= TC_MAU02_FIRST + 4; i++) begin
      run_tc(tv_a[i], tv_b[i], tv_c[i], res, cyc);
      exp = {tv_exp_hi[i], tv_exp_lo[i]};
      check_result(res, exp, "MAU-08");
    end

    // ==================================================================
    // MAU-09: reset mid-operation
    //   1. Start an operation
    //   2. Assert rst_n=0 halfway through (after 2 cycles)
    //   3. Verify done_o=0 and result_o=0 while in reset
    //   4. Release reset, run a full operation, verify correctness
    // ==================================================================
    begin
      a_i = tv_a[TC_MAU01]; b_i = tv_b[TC_MAU01]; c_i = tv_c[TC_MAU01];
      start_i = 1'b1;
      @(posedge clk); #1;
      start_i = 1'b0;
      @(posedge clk); #1;  // +1: cycle_q=0 fires
      @(posedge clk); #1;  // +2: cycle_q=1 fires  → assert reset here

      rst_n = 1'b0;
      @(posedge clk); #1;  // +3: asynchronous reset takes effect

      // done_o must be 0 while in reset
      if (done_o !== 1'b0) begin
        fail_cnt++;
        $display("FAIL MAU-09     done_o asserted during reset");
      end else begin
        pass_cnt++;
      end
      // result_o must be 0 while in reset
      if (result_o !== 64'h0) begin
        fail_cnt++;
        $display("FAIL MAU-09     result_o=0x%016h (non-zero) during reset", result_o);
      end else begin
        pass_cnt++;
      end

      // Release reset, verify normal operation resumes
      rst_n = 1'b1;
      @(posedge clk); #1;
      run_tc(tv_a[TC_MAU01], tv_b[TC_MAU01], tv_c[TC_MAU01], res, cyc);
      exp = {tv_exp_hi[TC_MAU01], tv_exp_lo[TC_MAU01]};
      check_result(res, exp, "MAU-09-recover");
    end

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
    #(20000 * 2 * CLK_HALF);
    $display("TIMEOUT: simulation exceeded limit");
    $finish;
  end

endmodule
