// Description: CRT orchestration controller
//   Controls CRT-based private key operations.
//   Sequences two 1024-bit modular exponentiations and the final CRT recombination.
//   m1 = base^dp mod p, m2 = base^dq mod q
//   h = qinv * (m1 - m2) mod p
//   result = m2 + h * q

module crt_controller #(
  parameter int unsigned KeyWidth  = 2048,
  parameter int unsigned WordWidth = 32
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  // Control
  input  logic                  start_i,
  output logic                  done_o,
  output logic                  busy_o,
  // mod_exp control
  output logic                  exp_start_o,
  output logic                  exp_crt_mode_o,
  input  logic                  exp_done_i,
  input  logic                  exp_busy_i,
  // mont_mul direct control
  output logic                  mont_start_o,
  output logic                  mont_mode_o,
  input  logic                  mont_done_i,
  input  logic                  mont_busy_i,
  // n_prime selection (1 = use nq_prime, 0 = use np_prime)
  output logic                  use_nq_prime_o,
  // Memory interface
  output logic                  mem_we_o,
  output logic                  mem_re_o,
  output logic [9:0]            mem_addr_o,
  output logic [WordWidth-1:0]  mem_wdata_o,
  input  logic [WordWidth-1:0]  mem_rdata_i,
  // DSP (mul_add_unit) interface
  output logic                  mul_start_o,
  output logic [WordWidth-1:0]  mul_a_o,
  output logic [WordWidth-1:0]  mul_b_o,
  output logic [WordWidth-1:0]  mul_c_o,
  input  logic [2*WordWidth-1:0] mul_result_i,
  input  logic                  mul_done_i
);

  import rsa_pkg::*;

  localparam int unsigned HALF_WORDS = NUM_WORDS / 2;  // 32

  // State definition
  typedef enum logic [3:0] {
    StCrtIdle,
    StCrtReduceP,
    StCrtExpP,
    StCrtExpPWait,
    StCrtReduceQ,
    StCrtExpQ,
    StCrtExpQWait,
    StCrtSubM,
    StCrtMulQinv,
    StCrtMulQinvWait,
    StCrtMulQinv2,
    StCrtMulQinv2Wait,
    StCrtMulHQ,
    StCrtAddM2,
    StCrtDone
  } crt_state_e;

  crt_state_e state_d, state_q;

  // Word counter
  logic [6:0] word_cnt_d, word_cnt_q;
  // Sub-state (4-bit for complex states)
  logic [3:0] sub_d, sub_q;
  // Borrow / Carry
  logic [WordWidth:0] borrow_d, borrow_q;
  logic [WordWidth:0] carry_d, carry_q;
  // Temporary registers
  logic [WordWidth-1:0] tmp_d, tmp_q;
  logic [WordWidth-1:0] tmp2_d, tmp2_q;
  // Outer loop index for StCrtMulHQ
  logic [4:0] mul_i_d, mul_i_q;

  // Default memory outputs
  logic        mem_re_d, mem_we_d;
  logic [9:0]  mem_addr_d;
  logic [WordWidth-1:0] mem_wdata_d;

  // Default DSP outputs
  logic                 mul_start_d;
  logic [WordWidth-1:0] mul_a_d, mul_b_d, mul_c_d;

  // mont_mul direct start
  logic mont_start_d;

  // Combinational logic
  always_comb begin
    state_d     = state_q;
    word_cnt_d  = word_cnt_q;
    sub_d       = sub_q;
    borrow_d    = borrow_q;
    carry_d     = carry_q;
    tmp_d       = tmp_q;
    tmp2_d      = tmp2_q;
    mul_i_d     = mul_i_q;

    mem_re_d    = 1'b0;
    mem_we_d    = 1'b0;
    mem_addr_d  = '0;
    mem_wdata_d = '0;
    mul_start_d = 1'b0;
    mul_a_d     = '0;
    mul_b_d     = '0;
    mul_c_d     = '0;
    mont_start_d = 1'b0;

    unique case (state_q)
      StCrtIdle: begin
        if (start_i) begin
          word_cnt_d = '0;
          sub_d      = '0;
          state_d    = StCrtReduceP;
        end
      end

      // Set up parameters for m1 = base_p ^ dp mod p
      // Copy base_p -> ADDR_BASE, dp -> ADDR_EXP, p -> ADDR_MOD, R^2_p -> ADDR_RSQ
      StCrtReduceP: begin
        unique case (sub_q)
          4'd0: begin
            // Copy base_p (ADDR_BASE_P) -> ADDR_BASE
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_BASE_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd1;
          end
          4'd1: begin
            sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd3;
            end else begin
              sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Copy dp (ADDR_DP) -> ADDR_EXP
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_DP[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd4;
          end
          4'd4: begin
            sub_d = 4'd5;
          end
          4'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_EXP[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd6;
            end else begin
              sub_d = 4'd3;
            end
          end
          4'd6: begin
            // Copy p (ADDR_P) -> ADDR_MOD
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd7;
          end
          4'd7: begin
            sub_d = 4'd8;
          end
          4'd8: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MOD[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd9;
            end else begin
              sub_d = 4'd6;
            end
          end
          4'd9: begin
            // Copy R^2_p (ADDR_RSQ_P) -> ADDR_RSQ
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd10;
          end
          4'd10: begin
            sub_d = 4'd11;
          end
          4'd11: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_RSQ[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              state_d    = StCrtExpP;
            end else begin
              sub_d = 4'd9;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      StCrtExpP: begin
        // Launch mod_exp in 1024-bit mode
        state_d = StCrtExpPWait;
      end

      StCrtExpPWait: begin
        if (exp_done_i) begin
          // m1 result is at ADDR_RESULT
          word_cnt_d = '0;
          sub_d      = '0;
          state_d    = StCrtReduceQ;
        end
      end

      // Save m1, set up parameters for m2 = base_q ^ dq mod q
      StCrtReduceQ: begin
        unique case (sub_q)
          4'd0: begin
            // Copy m1 (ADDR_RESULT) -> ADDR_M1
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd1;
          end
          4'd1: begin
            sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_M1[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd3;
            end else begin
              sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Copy base_q (ADDR_BASE_Q) -> ADDR_BASE
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_BASE_Q[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd4;
          end
          4'd4: begin
            sub_d = 4'd5;
          end
          4'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd6;
            end else begin
              sub_d = 4'd3;
            end
          end
          4'd6: begin
            // Copy dq (ADDR_DQ) -> ADDR_EXP
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_DQ[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd7;
          end
          4'd7: begin
            sub_d = 4'd8;
          end
          4'd8: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_EXP[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd9;
            end else begin
              sub_d = 4'd6;
            end
          end
          4'd9: begin
            // Copy q (ADDR_Q) -> ADDR_MOD
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_Q[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd10;
          end
          4'd10: begin
            sub_d = 4'd11;
          end
          4'd11: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MOD[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd12;
            end else begin
              sub_d = 4'd9;
            end
          end
          4'd12: begin
            // Copy R^2_q (ADDR_RSQ_Q) -> ADDR_RSQ
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ_Q[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd13;
          end
          4'd13: begin
            sub_d = 4'd14;
          end
          4'd14: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_RSQ[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              state_d    = StCrtExpQ;
            end else begin
              sub_d = 4'd12;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      StCrtExpQ: begin
        // Launch mod_exp in 1024-bit mode
        state_d = StCrtExpQWait;
      end

      StCrtExpQWait: begin
        if (exp_done_i) begin
          // m2 result is at ADDR_RESULT
          word_cnt_d = '0;
          sub_d      = '0;
          borrow_d   = '0;
          state_d    = StCrtSubM;
        end
      end

      // h_temp = m1 - m2 (correct by adding p if negative)
      StCrtSubM: begin
        unique case (sub_q)
          4'd0: begin
            // Copy m2 (ADDR_RESULT) -> ADDR_M2
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd1;
          end
          4'd1: begin
            sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_M2[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd3;
              borrow_d   = '0;
            end else begin
              sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Read m1[word_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_M1[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd4;
          end
          4'd4: begin
            // Wait for BRAM rdata to become valid (2-cycle latency)
            sub_d = 4'd5;
          end
          4'd5: begin
            // Latch m1[word_cnt], then read m2[word_cnt]
            tmp_d      = mem_rdata_i;
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_M2[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd6;
          end
          4'd6: begin
            sub_d = 4'd7;
          end
          4'd7: begin
            // h_temp[word_cnt] = m1 - m2 - borrow
            {borrow_d, mem_wdata_d} = {1'b0, tmp_q}
                                    - {1'b0, mem_rdata_i}
                                    - {32'b0, borrow_q[0]};
            mem_we_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            word_cnt_d = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              // Check if borrow correction is needed
              if (borrow_d[WordWidth]) begin
                // m1 < m2: h_temp is negative, correct by adding p
                word_cnt_d = '0;
                carry_d    = '0;
                sub_d      = 4'd8;
              end else begin
                // m1 >= m2: h_temp is correct
                word_cnt_d = '0;
                sub_d      = '0;
                state_d    = StCrtMulQinv;
              end
            end else begin
              sub_d = 4'd3;
            end
          end
          // Borrow correction: h_temp += p
          4'd8: begin
            // Read h_temp[word_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd9;
          end
          4'd9: begin
            // Wait for BRAM rdata to become valid
            sub_d = 4'd10;
          end
          4'd10: begin
            // Latch h_temp[word_cnt], then read p[word_cnt]
            tmp_d      = mem_rdata_i;
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd11;
          end
          4'd11: begin
            sub_d = 4'd12;
          end
          4'd12: begin
            // h_temp[word_cnt] = h_temp[word_cnt] + p[word_cnt] + carry
            {carry_d, mem_wdata_d} = {1'b0, tmp_q}
                                   + {1'b0, mem_rdata_i}
                                   + {32'b0, carry_q[0]};
            mem_we_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            word_cnt_d = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              state_d    = StCrtMulQinv;
            end else begin
              sub_d = 4'd8;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      // h = qinv * h_temp mod p (via two direct MontMuls)
      // MontMul 1: MontMul(qinv, h_temp, p) = qinv * h_temp * R^{-1} mod p
      StCrtMulQinv: begin
        unique case (sub_q)
          4'd0: begin
            // Copy qinv (ADDR_QINV) -> ADDR_MONT_A
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_QINV[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd1;
          end
          4'd1: begin
            sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd3;
            end else begin
              sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Copy h_temp (ADDR_HQ) -> ADDR_BASE
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd4;
          end
          4'd4: begin
            sub_d = 4'd5;
          end
          4'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd6;
            end else begin
              sub_d = 4'd3;
            end
          end
          4'd6: begin
            // Copy p (ADDR_P) -> ADDR_MOD
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd7;
          end
          4'd7: begin
            sub_d = 4'd8;
          end
          4'd8: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MOD[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd9;
            end else begin
              sub_d = 4'd6;
            end
          end
          4'd9: begin
            // Clear ADDR_MONT_T (65 words for 1024-bit mode: 33 words)
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = '0;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 > HALF_WORDS) begin
              // Start mont_mul
              mont_start_d = 1'b1;
              state_d      = StCrtMulQinvWait;
            end else begin
              sub_d = 4'd9;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      StCrtMulQinvWait: begin
        if (mont_done_i) begin
          // MontMul(qinv, h_temp, p) result in ADDR_MONT_T
          word_cnt_d = '0;
          sub_d      = '0;
          state_d    = StCrtMulQinv2;
        end
      end

      // MontMul 2: MontMul(result, R^2_p, p) to compensate R^{-1}
      // result = qinv * h_temp mod p
      StCrtMulQinv2: begin
        unique case (sub_q)
          4'd0: begin
            // Copy ADDR_MONT_T -> ADDR_MONT_A
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_T[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd1;
          end
          4'd1: begin
            sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd3;
            end else begin
              sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Copy R^2_p (ADDR_RSQ_P) -> ADDR_BASE
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd4;
          end
          4'd4: begin
            sub_d = 4'd5;
          end
          4'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 4'd6;
            end else begin
              sub_d = 4'd3;
            end
          end
          4'd6: begin
            // Clear ADDR_MONT_T
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = '0;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 > HALF_WORDS) begin
              // Start mont_mul
              mont_start_d = 1'b1;
              state_d      = StCrtMulQinv2Wait;
            end else begin
              sub_d = 4'd6;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      StCrtMulQinv2Wait: begin
        if (mont_done_i) begin
          // h = qinv * h_temp mod p is in ADDR_MONT_T
          // Copy h -> ADDR_RESULT for use by StCrtMulHQ
          word_cnt_d = '0;
          sub_d      = '0;
          state_d    = StCrtMulHQ;
        end
      end

      // h * q (1024 x 1024 -> 2048 bits) — schoolbook multiplication
      // h is in ADDR_MONT_T (32 words), q is at ADDR_Q (32 words)
      // Result stored in ADDR_HQ (64 words)
      StCrtMulHQ: begin
        unique case (sub_q)
          // Phase 1: Zero-clear ADDR_HQ (64 words)
          4'd0: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = '0;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= NUM_WORDS) begin
              word_cnt_d = '0;
              mul_i_d    = '0;
              sub_d      = 4'd1;
            end else begin
              sub_d = 4'd0;
            end
          end
          // Phase 2: Read h[mul_i] from ADDR_MONT_T
          4'd1: begin
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_T[9:0] + {3'b0, 2'b0, mul_i_q};
            sub_d      = 4'd2;
          end
          4'd2: begin
            // Wait for BRAM rdata to become valid
            sub_d = 4'd3;
          end
          4'd3: begin
            tmp_d      = mem_rdata_i;  // h[mul_i]
            carry_d    = '0;
            word_cnt_d = '0;  // j counter
            sub_d      = 4'd4;
          end
          // Phase 3: Inner loop — read q[j], read hq[i+j], multiply, write
          4'd4: begin
            // Read q[j]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_Q[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd5;
          end
          4'd5: begin
            sub_d = 4'd6;
          end
          4'd6: begin
            // Latch q[j], read hq[i+j]
            tmp2_d     = mem_rdata_i;
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, 2'b0, mul_i_q} + {3'b0, word_cnt_q};
            sub_d      = 4'd7;
          end
          4'd7: begin
            sub_d = 4'd8;
          end
          4'd8: begin
            // Start mul_add_unit: h[i] * q[j] + hq[i+j]
            mul_a_d     = tmp_q;         // h[i]
            mul_b_d     = tmp2_q;        // q[j]
            mul_c_d     = mem_rdata_i;   // hq[i+j]
            mul_start_d = 1'b1;
            sub_d       = 4'd9;
          end
          4'd9: begin
            // Wait for mul_add_unit done
            if (mul_done_i) begin
              sub_d = 4'd10;
            end
          end
          4'd10: begin
            // total = mul_result + carry
            // hq[i+j] = total[31:0], carry = total[64:32]
            {carry_d, mem_wdata_d} = {1'b0, mul_result_i}
                                   + {32'b0, carry_q[WordWidth-1:0]};
            mem_we_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, 2'b0, mul_i_q} + {3'b0, word_cnt_q};
            word_cnt_d = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              // Inner loop done: write carry to hq[i+32]
              sub_d = 4'd11;
            end else begin
              sub_d = 4'd4;
            end
          end
          // Phase 4: Write carry to hq[i + HALF_WORDS]
          4'd11: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_HQ[9:0] + {3'b0, 2'b0, mul_i_q} + {3'b0, 7'(HALF_WORDS)};
            mem_wdata_d = carry_q[WordWidth-1:0];
            mul_i_d     = mul_i_q + 5'd1;
            // Compare with HALF_WORDS-1 (=31) since mul_i_q is 5-bit unsigned
            // and HALF_WORDS[4:0] would slice to 0 due to localparam being int.
            if (mul_i_q == 5'd31) begin
              // All outer iterations done
              word_cnt_d = '0;
              sub_d      = '0;
              carry_d    = '0;
              state_d    = StCrtAddM2;
            end else begin
              sub_d = 4'd1;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      // result = m2 + h*q
      StCrtAddM2: begin
        unique case (sub_q)
          4'd0: begin
            // Read hq[word_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            sub_d      = 4'd1;
          end
          4'd1: begin
            // Wait for BRAM rdata to become valid
            sub_d = 4'd2;
          end
          4'd2: begin
            // Latch hq[word_cnt], then read m2[word_cnt] (or dummy for upper words)
            tmp_d    = mem_rdata_i;
            mem_re_d = 1'b1;
            // m2 is 32 words; zero-extend to 64 words
            if (word_cnt_q < HALF_WORDS) begin
              mem_addr_d = ADDR_M2[9:0] + {3'b0, word_cnt_q};
            end else begin
              // For upper words, m2 is implicitly zero.
              // Use ADDR_M2[0] as dummy read; result ignored in sub 4.
              mem_addr_d = ADDR_M2[9:0];
            end
            sub_d = 4'd3;
          end
          4'd3: begin
            sub_d = 4'd4;
          end
          4'd4: begin
            // result[word_cnt] = hq[word_cnt] + m2[word_cnt] + carry
            if (word_cnt_q < HALF_WORDS) begin
              {carry_d, mem_wdata_d} = {1'b0, tmp_q}
                                     + {1'b0, mem_rdata_i}
                                     + {32'b0, carry_q[0]};
            end else begin
              // m2 zero-extended: add 0
              {carry_d, mem_wdata_d} = {1'b0, tmp_q}
                                     + {32'b0, carry_q[0]};
            end
            mem_we_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, word_cnt_q};
            word_cnt_d = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= NUM_WORDS) begin
              state_d = StCrtDone;
            end else begin
              sub_d = 4'd0;
            end
          end
          default: sub_d = 4'd0;
        endcase
      end

      StCrtDone: begin
        state_d = StCrtIdle;
      end

      default: state_d = StCrtIdle;
    endcase
  end

  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= StCrtIdle;
      word_cnt_q <= '0;
      sub_q      <= '0;
      borrow_q   <= '0;
      carry_q    <= '0;
      tmp_q      <= '0;
      tmp2_q     <= '0;
      mul_i_q    <= '0;
      done_o     <= 1'b0;
      mem_we_o   <= 1'b0;
      mem_re_o   <= 1'b0;
      mem_addr_o <= '0;
      mem_wdata_o <= '0;
      mul_start_o <= 1'b0;
      mul_a_o    <= '0;
      mul_b_o    <= '0;
      mul_c_o    <= '0;
      mont_start_o <= 1'b0;
    end else begin
      state_q    <= state_d;
      word_cnt_q <= word_cnt_d;
      sub_q      <= sub_d;
      borrow_q   <= borrow_d;
      carry_q    <= carry_d;
      tmp_q      <= tmp_d;
      tmp2_q     <= tmp2_d;
      mul_i_q    <= mul_i_d;
      done_o     <= (state_d == StCrtIdle) && (state_q == StCrtDone);
      mem_we_o   <= mem_we_d;
      mem_re_o   <= mem_re_d;
      mem_addr_o <= mem_addr_d;
      mem_wdata_o <= mem_wdata_d;
      mul_start_o <= mul_start_d;
      mul_a_o    <= mul_a_d;
      mul_b_o    <= mul_b_d;
      mul_c_o    <= mul_c_d;
      mont_start_o <= mont_start_d;
    end
  end

  // mod_exp control signals
  assign exp_start_o    = ((state_q == StCrtExpP) || (state_q == StCrtExpQ))
                       && (state_q != state_d);  // 1-cycle pulse on state transition
  assign exp_crt_mode_o = 1'b1;  // always 1024-bit in CRT mode

  // mont_mul mode: always 1024-bit in CRT direct mode
  assign mont_mode_o = 1'b1;

  // n_prime selection: use nq_prime during q-phase
  assign use_nq_prime_o = (state_q == StCrtExpQ) || (state_q == StCrtExpQWait);

  assign busy_o = (state_q != StCrtIdle);

endmodule
