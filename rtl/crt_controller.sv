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
    StCrtMulHQ,
    StCrtAddM2,
    StCrtDone
  } crt_state_e;

  crt_state_e state_d, state_q;

  // Word counter
  logic [6:0] word_cnt_d, word_cnt_q;
  // Sub-state
  logic [2:0] sub_d, sub_q;
  // Borrow / Carry
  logic [WordWidth:0] borrow_d, borrow_q;
  logic [WordWidth:0] carry_d, carry_q;
  // Temporary register
  logic [WordWidth-1:0] tmp_d, tmp_q;

  // Default memory outputs
  logic        mem_re_d, mem_we_d;
  logic [9:0]  mem_addr_d;
  logic [WordWidth-1:0] mem_wdata_d;

  // Default DSP outputs
  logic                 mul_start_d;
  logic [WordWidth-1:0] mul_a_d, mul_b_d, mul_c_d;

  // Combinational logic
  always_comb begin
    state_d    = state_q;
    word_cnt_d = word_cnt_q;
    sub_d      = sub_q;
    borrow_d   = borrow_q;
    carry_d    = carry_q;
    tmp_d      = tmp_q;

    mem_re_d    = 1'b0;
    mem_we_d    = 1'b0;
    mem_addr_d  = '0;
    mem_wdata_d = '0;
    mul_start_d = 1'b0;
    mul_a_d     = '0;
    mul_b_d     = '0;
    mul_c_d     = '0;

    unique case (state_q)
      StCrtIdle: begin
        if (start_i) begin
          word_cnt_d = '0;
          sub_d      = '0;
          state_d    = StCrtReduceP;
        end
      end

      // Compute base mod p (simplified: use the lower 1024 bits of base)
      // Strictly, base(2048-bit) mod p(1024-bit) is required, but in the
      // initial implementation this is delegated to mod_exp for internal processing.
      // Here the lower 32 words of base are set up at ADDR_BASE and
      // mod_exp is launched in 1024-bit mode.
      StCrtReduceP: begin
        // Set up exp = dp, mod = p, rsq = R^2 mod p
        // mod_exp references ADDR_EXP, ADDR_MOD, ADDR_RSQ, ADDR_BASE.
        // In CRT mode the following remapping is required:
        //   ADDR_EXP <- dp(ADDR_DP), ADDR_MOD <- p(ADDR_P),
        //   ADDR_RSQ <- R^2_p(ADDR_RSQ_P), ADDR_BASE <- base mod p
        // Copy dp -> ADDR_EXP, p -> ADDR_MOD, R^2_p -> ADDR_RSQ
        unique case (sub_q)
          3'd0: begin
            // Copy dp -> ADDR_EXP
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_DP[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd1;
          end
          3'd1: begin
            sub_d = 3'd2;
          end
          3'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_EXP[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 3'd3;
            end else begin
              sub_d = 3'd0;
            end
          end
          3'd3: begin
            // Copy p -> ADDR_MOD
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd4;
          end
          3'd4: begin
            sub_d = 3'd5;
          end
          3'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MOD[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 3'd6;
            end else begin
              sub_d = 3'd3;
            end
          end
          3'd6: begin
            // Copy R^2_p -> ADDR_RSQ
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ_P[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd7;
          end
          3'd7: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_RSQ[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              state_d    = StCrtExpP;
            end else begin
              sub_d = 3'd6;
            end
          end
          default: sub_d = 3'd0;
        endcase
      end

      StCrtExpP: begin
        // Launch mod_exp in 1024-bit mode
        state_d = StCrtExpPWait;
      end

      StCrtExpPWait: begin
        if (exp_done_i) begin
          // Copy m1 result to ADDR_M1
          word_cnt_d = '0;
          sub_d      = '0;
          state_d    = StCrtReduceQ;
        end
      end

      // Set up base mod q (dq -> EXP, q -> MOD, R^2_q -> RSQ)
      StCrtReduceQ: begin
        unique case (sub_q)
          3'd0: begin
            // Copy m1(ADDR_RESULT) -> ADDR_M1
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd1;
          end
          3'd1: begin
            sub_d = 3'd2;
          end
          3'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_M1[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 3'd3;
            end else begin
              sub_d = 3'd0;
            end
          end
          3'd3: begin
            // Copy dq -> ADDR_EXP
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_DQ[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd4;
          end
          3'd4: begin
            sub_d = 3'd5;
          end
          3'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_EXP[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 3'd6;
            end else begin
              sub_d = 3'd3;
            end
          end
          3'd6: begin
            // Copy q -> ADDR_MOD
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_Q[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd7;
          end
          3'd7: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MOD[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              // R^2_q -> ADDR_RSQ is also needed, but sub is only 3 bits wide
              // -> copy it inside StCrtExpQ
              state_d    = StCrtExpQ;
            end else begin
              sub_d = 3'd6;
            end
          end
          default: sub_d = 3'd0;
        endcase
      end

      StCrtExpQ: begin
        // Copy R^2_q -> ADDR_RSQ
        unique case (sub_q)
          3'd0: begin
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ_Q[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd1;
          end
          3'd1: begin
            sub_d = 3'd2;
          end
          3'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_RSQ[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              state_d    = StCrtExpQWait;
            end else begin
              sub_d = 3'd0;
            end
          end
          default: sub_d = 3'd0;
        endcase
      end

      StCrtExpQWait: begin
        if (exp_done_i) begin
          // Copy m2 result to ADDR_M2
          word_cnt_d = '0;
          sub_d      = '0;
          borrow_d   = '0;
          state_d    = StCrtSubM;
        end
      end

      // h_temp = m1 - m2 (correct by adding p if negative)
      StCrtSubM: begin
        unique case (sub_q)
          3'd0: begin
            // Copy m2(ADDR_RESULT) -> ADDR_M2
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd1;
          end
          3'd1: begin
            sub_d = 3'd2;
          end
          3'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_M2[9:0] + {3'b0, word_cnt_q};
            mem_wdata_d = mem_rdata_i;
            word_cnt_d  = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = 3'd3;
              borrow_d   = '0;
            end else begin
              sub_d = 3'd0;
            end
          end
          3'd3: begin
            // Read m1[word_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_M1[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd4;
          end
          3'd4: begin
            tmp_d = mem_rdata_i;  // m1[word_cnt]
            // Read m2[word_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_M2[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd5;
          end
          3'd5: begin
            sub_d = 3'd6;
          end
          3'd6: begin
            // h_temp[word_cnt] = m1 - m2 - borrow
            {borrow_d, mem_wdata_d} = {1'b0, tmp_q}
                                    - {1'b0, mem_rdata_i}
                                    - {32'b0, borrow_q[0]};
            mem_we_d   = 1'b1;
            // Temporarily store h_temp in HQ region
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            word_cnt_d = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= HALF_WORDS) begin
              word_cnt_d = '0;
              sub_d      = '0;
              // If borrow exists, correction h_temp += p is needed.
              // Since the subsequent MulQinv uses Montgomery multiplication,
              // set h_temp at ADDR_BASE and compute MontMul(qinv, h_temp, p).
              state_d = StCrtMulQinv;
            end else begin
              sub_d = 3'd3;
            end
          end
          default: sub_d = 3'd0;
        endcase
      end

      // h = qinv * h_temp mod p (executed via Montgomery multiplication)
      StCrtMulQinv: begin
        // Copy h_temp(ADDR_HQ) -> ADDR_BASE (as input to mod_exp)
        // Copy qinv -> ADDR_MONT_A
        // Then use mod_exp in 1024-bit mode for a MontMul-equivalent operation.
        // However, since mod_exp performs exponentiation, direct mont_mul is preferred here.
        // -> Either control mont_mul directly from rsa_top, or
        //    delegate via exp_start from crt_controller.
        // Design simplification: h = qinv * h_temp mod p is delegated to mod_exp
        // as exp=1 exponentiation (= two single MontMuls + conversion) via exp_start.
        // -> This is inefficient; a future optimization will use mont_mul directly.
        state_d = StCrtMulQinvWait;
      end

      StCrtMulQinvWait: begin
        if (exp_done_i) begin
          word_cnt_d = '0;
          sub_d      = '0;
          carry_d    = '0;
          state_d    = StCrtMulHQ;
        end
      end

      // h * q (1024 x 1024 -> 2048 bits) -- directly drives mul_add_unit
      StCrtMulHQ: begin
        // Multi-word multiplication is complex; compute word-by-word sequentially.
        // Simplified implementation: accumulate h[i] * q[j] using word_cnt as iterator.
        // Full implementation is deferred to the verification phase (skeleton here).
        word_cnt_d = '0;
        sub_d      = '0;
        state_d    = StCrtAddM2;
      end

      // result = m2 + h*q
      StCrtAddM2: begin
        // Simplified implementation: ADDR_HQ + ADDR_M2 -> ADDR_RESULT
        unique case (sub_q)
          3'd0: begin
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_HQ[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd1;
          end
          3'd1: begin
            tmp_d = mem_rdata_i;
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_M2[9:0] + {3'b0, word_cnt_q};
            sub_d      = 3'd2;
          end
          3'd2: begin
            sub_d = 3'd3;
          end
          3'd3: begin
            // result[word_cnt] = hq[word_cnt] + m2[word_cnt] + carry
            {carry_d, mem_wdata_d} = {1'b0, tmp_q}
                                   + {1'b0, mem_rdata_i}
                                   + {32'b0, carry_q[0]};
            mem_we_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, word_cnt_q};
            word_cnt_d = word_cnt_q + 7'd1;
            if (word_cnt_q + 7'd1 >= NUM_WORDS) begin
              state_d = StCrtDone;
            end else begin
              sub_d = 3'd0;
            end
          end
          default: sub_d = 3'd0;
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
      done_o     <= 1'b0;
      mem_we_o   <= 1'b0;
      mem_re_o   <= 1'b0;
      mem_addr_o <= '0;
      mem_wdata_o <= '0;
      mul_start_o <= 1'b0;
      mul_a_o    <= '0;
      mul_b_o    <= '0;
      mul_c_o    <= '0;
    end else begin
      state_q    <= state_d;
      word_cnt_q <= word_cnt_d;
      sub_q      <= sub_d;
      borrow_q   <= borrow_d;
      carry_q    <= carry_d;
      tmp_q      <= tmp_d;
      done_o     <= (state_d == StCrtIdle) && (state_q == StCrtDone);
      mem_we_o   <= mem_we_d;
      mem_re_o   <= mem_re_d;
      mem_addr_o <= mem_addr_d;
      mem_wdata_o <= mem_wdata_d;
      mul_start_o <= mul_start_d;
      mul_a_o    <= mul_a_d;
      mul_b_o    <= mul_b_d;
      mul_c_o    <= mul_c_d;
    end
  end

  // mod_exp control signals
  assign exp_start_o    = ((state_q == StCrtExpP) || (state_q == StCrtExpQ)
                        || (state_q == StCrtMulQinv))
                       && (state_q != state_d);  // 1-cycle pulse on state transition
  assign exp_crt_mode_o = 1'b1;  // always 1024-bit in CRT mode

  assign busy_o = (state_q != StCrtIdle);

endmodule
