// Description: Montgomery multiplier (FIOS algorithm, 32-bit word)
//   MontMul(a, b, n) = a * b * R^(-1) mod n
//   Uses FIOS (Finely Integrated Operand Scanning) with 32-bit word arithmetic.
//   half_mode_i selects between 2048-bit (64 words) and 1024-bit (32 words) mode.

module mont_mul #(
  parameter int unsigned MaxWords  = 64,
  parameter int unsigned WordWidth = 32
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  // Control
  input  logic                     start_i,
  input  logic                     half_mode_i,
  output logic                     done_o,
  output logic                     busy_o,
  // Memory interface (read a, b, n / read-write t)
  output logic                     mem_re_o,
  output logic                     mem_we_o,
  output logic [9:0]               mem_addr_o,
  input  logic [WordWidth-1:0]     mem_rdata_i,
  output logic [WordWidth-1:0]     mem_wdata_o,
  // n_prime[0] (precomputed 32-bit constant)
  input  logic [WordWidth-1:0]     n_prime_i,
  // Multiply-accumulate unit interface
  output logic [WordWidth-1:0]     mul_a_o,
  output logic [WordWidth-1:0]     mul_b_o,
  output logic [WordWidth-1:0]     mul_c_o,
  output logic                     mul_start_o,
  input  logic [2*WordWidth-1:0]   mul_result_i,
  input  logic                     mul_done_i
);

  import rsa_pkg::*;

  // State definition
  typedef enum logic [3:0] {
    StMontIdle,
    StMontOuterInit,
    StMontLoadBi,
    StMontInnerFirst,
    StMontInnerFirstWait,
    StMontComputeM,
    StMontMN0,
    StMontMN0Wait,
    StMontInnerLoop,
    StMontBiRead,        // wait one cycle for B[i] data after OuterInit
    StMontInnerStore,
    StMontInnerRead,
    StMontOuterEnd,
    StMontFinalSub,
    StMontWriteBack,
    StMontDone
  } mont_mul_state_e;

  mont_mul_state_e state_d, state_q;

  // Word count (mode-dependent)
  logic [6:0] num_words;
  assign num_words = half_mode_i ? 7'd32 : 7'd64;

  // Loop counters
  logic [6:0] i_q, j_q;       // outer / inner loop
  logic [6:0] i_d, j_d;

  // b[i] latch
  logic [WordWidth-1:0] bi_q, bi_d;

  // m (Montgomery coefficient) latch
  logic [WordWidth-1:0] m_q, m_d;

  // Carry register (33-bit)
  logic [WordWidth:0] carry_q, carry_d;

  // S register (lower word of multiply-accumulate)
  logic [WordWidth-1:0] s_q, s_d;

  // Carry absorption for inner loop: S_adj = S1 + carry_lo (33-bit)
  logic [WordWidth:0] inner_s_adj;

  // Carry overflow bit from OuterEnd — feeds into the NEXT outer iteration's carry
  logic carry_ovfl_q, carry_ovfl_d;

  // Effective carry at OuterEnd: carry_q + carry_ovfl_q (33-bit, fits since carry_q <= 2^33-2)
  logic [WordWidth:0] carry_eff_outer;

  // Memory base addresses (offsets for a, b, n, t)
  logic [9:0] addr_a_base, addr_b_base, addr_n_base, addr_t_base;

  always_comb begin
    if (half_mode_i) begin
      // 1024-bit CRT mode: use the appropriate memory regions
      // In CRT mode, mod_exp remaps base/exp/mod/rsq regions
      // to p/q/dp/dq etc., so standard addresses are used
      addr_a_base = ADDR_MONT_A[9:0];
      addr_b_base = ADDR_BASE[9:0];
      addr_n_base = ADDR_MOD[9:0];
      addr_t_base = ADDR_MONT_T[9:0];
    end else begin
      addr_a_base = ADDR_MONT_A[9:0];
      addr_b_base = ADDR_BASE[9:0];
      addr_n_base = ADDR_MOD[9:0];
      addr_t_base = ADDR_MONT_T[9:0];
    end
  end

  // Comparison result for final subtraction
  logic t_ge_n;  // t >= n
  logic [6:0] sub_idx_q, sub_idx_d;
  logic [WordWidth:0] borrow_q, borrow_d;
  logic sub_phase_q, sub_phase_d;  // 0: compare, 1: subtract and write back

  // Memory interface defaults
  logic        mem_re_d, mem_we_d;
  logic [9:0]  mem_addr_d;
  logic [WordWidth-1:0] mem_wdata_d;

  // Multiply-accumulate unit defaults
  logic [WordWidth-1:0] mul_a_d, mul_b_d, mul_c_d;
  logic                 mul_start_d;

  // Sub-state for inner loop
  // a[j]*b[i] -> t[j] + result + carry -> m*n[j] + result + carry -> store
  logic [2:0] inner_sub_q, inner_sub_d;

  // Combinational logic
  always_comb begin
    state_d     = state_q;
    i_d         = i_q;
    j_d         = j_q;
    bi_d        = bi_q;
    m_d         = m_q;
    carry_d     = carry_q;
    s_d         = s_q;
    sub_idx_d   = sub_idx_q;
    borrow_d    = borrow_q;
    sub_phase_d = sub_phase_q;
    inner_sub_d = inner_sub_q;

    mem_re_d    = 1'b0;
    mem_we_d    = 1'b0;
    mem_addr_d  = '0;
    mem_wdata_d = '0;
    mul_a_d       = '0;
    mul_b_d       = '0;
    mul_c_d       = '0;
    mul_start_d   = 1'b0;
    inner_s_adj   = '0;
    carry_ovfl_d  = carry_ovfl_q;
    carry_eff_outer = '0;

    unique case (state_q)
      StMontIdle: begin
        if (start_i) begin
          i_d          = '0;
          carry_d      = '0;
          carry_ovfl_d = 1'b0;  // reset carry overflow at each MontMul start
          state_d      = StMontOuterInit;
        end
      end

      // Outer loop init: issue B[i] prefetch, then wait one cycle for data
      StMontOuterInit: begin
        mem_re_d   = 1'b1;
        mem_addr_d = addr_b_base + {3'b0, i_q};
        state_d    = StMontBiRead;
      end

      // Wait for B[i] data to appear on mem_rdata_i (1-cycle BRAM latency)
      StMontBiRead: begin
        state_d = StMontLoadBi;
      end

      // Latch b[i]
      StMontLoadBi: begin
        // BRAM outputs with 1-cycle latency
        // Wait one more cycle
        bi_d    = mem_rdata_i;
        j_d     = '0;
        carry_d = '0;
        // Prefetch request for t[0]
        mem_re_d   = 1'b1;
        mem_addr_d = addr_t_base;
        state_d    = StMontInnerFirst;
      end

      // j=0: (C,S) = t[0] + a[0]*b[i]
      StMontInnerFirst: begin
        // Request memory read of a[0]
        mem_re_d   = 1'b1;
        mem_addr_d = addr_a_base;
        // t[0] will be available from mem_rdata_i in the next cycle
        state_d    = StMontInnerFirstWait;
        inner_sub_d = 3'd0;
      end

      StMontInnerFirstWait: begin
        unique case (inner_sub_q)
          3'd0: begin
            // Capture t[0], wait for a[0] read
            s_d = mem_rdata_i;  // t[0]
            inner_sub_d = 3'd1;
          end
          3'd1: begin
            // Capture a[0], start a[0]*b[i] + t[0]
            mul_a_d     = mem_rdata_i;  // a[0]
            mul_b_d     = bi_q;         // b[i]
            mul_c_d     = s_q;          // t[0]
            mul_start_d = 1'b1;
            inner_sub_d = 3'd2;
          end
          3'd2: begin
            if (mul_done_i) begin
              // (C,S) = t[0] + a[0]*b[i]
              s_d     = mul_result_i[31:0];
              carry_d = {1'b0, mul_result_i[63:32]};
              state_d = StMontComputeM;
            end
          end
          default: inner_sub_d = 3'd0;
        endcase
      end

      // m = S * n_prime[0] mod W (only the lower 32 bits are used)
      StMontComputeM: begin
        // m = S * n'[0] — only lower 32 bits needed, use combinational multiply
        m_d     = s_q * n_prime_i;
        // Prefetch n[0]
        mem_re_d   = 1'b1;
        mem_addr_d = addr_n_base;
        state_d    = StMontMN0;
      end

      // (C,S) = S + m*n[0] — S is guaranteed to be 0 by design
      StMontMN0: begin
        inner_sub_d = 3'd0;
        state_d     = StMontMN0Wait;
      end

      StMontMN0Wait: begin
        unique case (inner_sub_q)
          3'd0: begin
            // Capture n[0]
            mul_a_d     = m_q;           // m
            mul_b_d     = mem_rdata_i;   // n[0]
            mul_c_d     = s_q;           // S
            mul_start_d = 1'b1;
            inner_sub_d = 3'd1;
          end
          3'd1: begin
            if (mul_done_i) begin
              // S is 0 (guaranteed by design); accumulate upper word into carry
              carry_d = carry_q + {1'b0, mul_result_i[63:32]};
              j_d     = 7'd1;
              // Prepare inner loop: prefetch a[1] and t[1]
              if (num_words > 7'd1) begin
                mem_re_d   = 1'b1;
                mem_addr_d = addr_t_base + 10'd1;
                inner_sub_d = 3'd0;
                state_d    = StMontInnerLoop;
              end else begin
                state_d = StMontOuterEnd;
              end
            end
          end
          default: inner_sub_d = 3'd0;
        endcase
      end

      // Inner loop j=1..s-1
      // (C,S) = t[j] + a[j]*b[i] + C
      // (C,S) = S + m*n[j] + C  <- two stages in theory, executed sequentially here
      // t[j-1] = S
      StMontInnerLoop: begin
        unique case (inner_sub_q)
          3'd0: begin
            // Wait for t[j], prefetch a[j]
            mem_re_d   = 1'b1;
            mem_addr_d = addr_a_base + {3'b0, j_q};
            inner_sub_d = 3'd1;
          end
          3'd1: begin
            // Latch t[j]
            s_d = mem_rdata_i;
            inner_sub_d = 3'd2;
          end
          3'd2: begin
            // Capture a[j], start a[j]*b[i] + t[j]
            mul_a_d     = mem_rdata_i;  // a[j]
            mul_b_d     = bi_q;
            mul_c_d     = s_q;          // t[j]
            mul_start_d = 1'b1;
            inner_sub_d = 3'd3;
          end
          3'd3: begin
            if (mul_done_i) begin
              // (C,S) = t[j] + a[j]*b[i] + carry_in
              // Absorb carry_in into S: S_adj = S1 + carry_lo (33-bit)
              // carry_new = C1 + S_adj[32] + carry_q[32]
              inner_s_adj = {1'b0, mul_result_i[31:0]}
                          + {1'b0, carry_q[31:0]};
              s_d     = inner_s_adj[WordWidth-1:0];
              carry_d = {1'b0, mul_result_i[63:32]}
                      + {{32{1'b0}}, inner_s_adj[32]}
                      + {{32{1'b0}}, carry_q[32]};
              // Prefetch n[j]
              mem_re_d   = 1'b1;
              mem_addr_d = addr_n_base + {3'b0, j_q};
              inner_sub_d = 3'd4;
            end
          end
          3'd4: begin
            // Wait for n[j] read
            inner_sub_d = 3'd5;
          end
          3'd5: begin
            // Start m*n[j] + S
            mul_a_d     = m_q;
            mul_b_d     = mem_rdata_i;  // n[j]
            mul_c_d     = s_q;          // S
            mul_start_d = 1'b1;
            inner_sub_d = 3'd6;
          end
          3'd6: begin
            if (mul_done_i) begin
              // (C2,S2) = S + m*n[j]
              // carry = C + C2 (accumulated)
              s_d = mul_result_i[31:0];
              carry_d = carry_q
                      + {1'b0, mul_result_i[63:32]};
              state_d = StMontInnerStore;
            end
          end
          default: inner_sub_d = 3'd0;
        endcase
      end

      // (StMontBiRead is handled above — replaces the former StMontInnerLoopWait)

      // Write t[j-1] = S
      StMontInnerStore: begin
        mem_we_d    = 1'b1;
        mem_addr_d  = addr_t_base + {3'b0, j_q} - 10'd1;
        mem_wdata_d = s_q;
        j_d         = j_q + 7'd1;
        if (j_q + 7'd1 < num_words) begin
          // Transition to StMontInnerRead to prefetch the correct t[j_new]
          state_d = StMontInnerRead;
        end else begin
          state_d = StMontOuterEnd;
        end
      end

      // Prefetch t[j_q] for the next inner loop iteration (j_q already incremented in InnerStore)
      //   This fixes the off-by-two read address bug: InnerStore's write address must NOT
      //   be reused as the read address for the next T[j].
      StMontInnerRead: begin
        mem_re_d    = 1'b1;
        mem_addr_d  = addr_t_base + {3'b0, j_q};
        inner_sub_d = 3'd0;
        state_d     = StMontInnerLoop;
      end

      // Outer loop tail: t[s-1] = carry_eff (carry + carry_ovfl from previous iteration)
      //   carry_ovfl_d saves the new overflow bit for the NEXT outer iteration.
      StMontOuterEnd: begin
        carry_eff_outer = carry_q + {32'b0, carry_ovfl_q};
        mem_we_d     = 1'b1;
        mem_addr_d   = addr_t_base + {3'b0, num_words} - 10'd1;
        mem_wdata_d  = carry_eff_outer[WordWidth-1:0];
        carry_ovfl_d = carry_eff_outer[WordWidth];
        i_d          = i_q + 7'd1;
        carry_d      = '0;
        if (i_q + 7'd1 < num_words) begin
          state_d = StMontOuterInit;
        end else begin
          // All outer loop iterations complete -> final conditional subtraction
          sub_idx_d   = '0;
          borrow_d    = '0;
          sub_phase_d = 1'b0;
          state_d     = StMontFinalSub;
        end
      end

      // Final conditional subtraction: if t >= n then t = t - n
      // Phase 0: compare (scan all words computing t[i] - n[i] and tracking borrow)
      // Phase 1: if no final borrow (t >= n), write back the subtracted result
      StMontFinalSub: begin
        if (!sub_phase_q) begin
          // Compare phase: read t[sub_idx] and n[sub_idx]
          mem_re_d   = 1'b1;
          mem_addr_d = addr_t_base + {3'b0, sub_idx_q};
          inner_sub_d = 3'd0;
          state_d     = StMontWriteBack;
        end else begin
          // Subtract and write-back phase
          mem_re_d   = 1'b1;
          mem_addr_d = addr_t_base + {3'b0, sub_idx_q};
          inner_sub_d = 3'd0;
          state_d     = StMontWriteBack;
        end
      end

      StMontWriteBack: begin
        if (!sub_phase_q) begin
          // Compare phase
          unique case (inner_sub_q)
            3'd0: begin
              // Wait for t[sub_idx] read, prefetch n[sub_idx]
              mem_re_d   = 1'b1;
              mem_addr_d = addr_n_base + {3'b0, sub_idx_q};
              inner_sub_d = 3'd1;
            end
            3'd1: begin
              // Latch t[sub_idx]
              s_d = mem_rdata_i;
              inner_sub_d = 3'd2;
            end
            3'd2: begin
              // t[sub_idx] - n[sub_idx] - borrow
              {borrow_d, s_d} = {1'b0, s_q}
                              - {1'b0, mem_rdata_i}
                              - {32'b0, borrow_q[0]};
              // borrow is MSB
              sub_idx_d = sub_idx_q + 7'd1;
              if (sub_idx_q + 7'd1 >= num_words) begin
                // Compare done: if borrow=0 OR carry_ovfl (T >= 2^{s*w}), subtract
                if (!borrow_d[WordWidth] || carry_ovfl_q) begin
                  // t >= n -> proceed to subtract and write-back phase
                  sub_idx_d   = '0;
                  borrow_d    = '0;
                  sub_phase_d = 1'b1;
                  state_d     = StMontFinalSub;
                end else begin
                  // t < n -> copy result to ADDR_RESULT
                  sub_idx_d = '0;
                  state_d   = StMontDone;
                end
              end else begin
                state_d = StMontFinalSub;
              end
            end
            default: inner_sub_d = 3'd0;
          endcase
        end else begin
          // Subtract and write-back phase
          unique case (inner_sub_q)
            3'd0: begin
              mem_re_d   = 1'b1;
              mem_addr_d = addr_n_base + {3'b0, sub_idx_q};
              inner_sub_d = 3'd1;
            end
            3'd1: begin
              s_d = mem_rdata_i;  // t[sub_idx]
              inner_sub_d = 3'd2;
            end
            3'd2: begin
              // t[sub_idx] - n[sub_idx] - borrow
              {borrow_d, mem_wdata_d} = {1'b0, s_q}
                                      - {1'b0, mem_rdata_i}
                                      - {32'b0, borrow_q[0]};
              mem_we_d   = 1'b1;
              mem_addr_d = addr_t_base + {3'b0, sub_idx_q};
              sub_idx_d  = sub_idx_q + 7'd1;
              if (sub_idx_q + 7'd1 >= num_words) begin
                state_d = StMontDone;
              end else begin
                state_d = StMontFinalSub;
              end
            end
            default: inner_sub_d = 3'd0;
          endcase
        end
      end

      StMontDone: begin
        state_d = StMontIdle;
      end

      default: state_d = StMontIdle;
    endcase
  end

  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= StMontIdle;
      i_q         <= '0;
      j_q         <= '0;
      bi_q        <= '0;
      m_q         <= '0;
      carry_q     <= '0;
      s_q         <= '0;
      sub_idx_q   <= '0;
      borrow_q    <= '0;
      sub_phase_q <= 1'b0;
      inner_sub_q <= '0;
      done_o      <= 1'b0;
      mem_re_o    <= 1'b0;
      mem_we_o    <= 1'b0;
      mem_addr_o  <= '0;
      mem_wdata_o <= '0;
      mul_a_o     <= '0;
      mul_b_o     <= '0;
      mul_c_o     <= '0;
      mul_start_o  <= 1'b0;
      carry_ovfl_q <= 1'b0;
    end else begin
      state_q     <= state_d;
      i_q         <= i_d;
      j_q         <= j_d;
      bi_q        <= bi_d;
      m_q         <= m_d;
      carry_q     <= carry_d;
      s_q         <= s_d;
      sub_idx_q   <= sub_idx_d;
      borrow_q    <= borrow_d;
      sub_phase_q <= sub_phase_d;
      inner_sub_q <= inner_sub_d;
      done_o      <= (state_d == StMontDone) && (state_q != StMontDone);
      mem_re_o    <= mem_re_d;
      mem_we_o    <= mem_we_d;
      mem_addr_o  <= mem_addr_d;
      mem_wdata_o <= mem_wdata_d;
      mul_a_o     <= mul_a_d;
      mul_b_o     <= mul_b_d;
      mul_c_o     <= mul_c_d;
      mul_start_o  <= mul_start_d;
      carry_ovfl_q <= carry_ovfl_d;
    end
  end

  assign busy_o = (state_q != StMontIdle);

endmodule
