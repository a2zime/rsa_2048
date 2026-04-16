// Description: Modular exponentiation engine (left-to-right binary square-and-multiply)
//   Computes base^exp mod n using a Montgomery multiplier.
//   crt_mode_i selects between 2048-bit and 1024-bit operation.

module mod_exp #(
  parameter int unsigned MaxWidth  = 2048,
  parameter int unsigned WordWidth = 32
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  // Control
  input  logic                  start_i,
  input  logic                  crt_mode_i,
  output logic                  done_o,
  output logic                  busy_o,
  // Memory interface
  output logic                  mem_re_o,
  output logic                  mem_we_o,
  output logic [9:0]            mem_addr_o,
  input  logic [WordWidth-1:0]  mem_rdata_i,
  output logic [WordWidth-1:0]  mem_wdata_o,
  // Montgomery multiplier interface
  output logic                  mont_start_o,
  output logic                  mont_mode_o,
  input  logic                  mont_done_i,
  input  logic                  mont_busy_i
);

  import rsa_pkg::*;

  // State definition
  typedef enum logic [3:0] {
    StExpIdle,
    StExpToMont,
    StExpToMontWait,
    StExpInitR,
    StExpInitRWait,
    StExpScan,
    StExpSquare,
    StExpSquareWait,
    StExpMul,
    StExpMulWait,
    StExpFromMont,
    StExpFromMontWait,
    StExpCopyResult,
    StExpDone
  } mod_exp_state_e;

  mod_exp_state_e state_d, state_q;

  // Word count (mode-dependent)
  logic [6:0] num_words;
  assign num_words = crt_mode_i ? 7'd32 : 7'd64;

  // Bit width
  logic [11:0] bit_width;
  assign bit_width = crt_mode_i ? 12'd1024 : 12'd2048;

  // Bit counter (scans from MSB to LSB)
  logic [11:0] bit_cnt_q, bit_cnt_d;

  // Exponent word latch (used as a shift register)
  logic [WordWidth-1:0] exp_word_q, exp_word_d;

  // Word index and bit offset for the current bit position
  logic [6:0]  exp_word_idx;
  logic [4:0]  exp_bit_offset;
  logic        current_exp_bit;

  assign exp_word_idx  = bit_cnt_q[11:5];  // bit_cnt / 32 (word index)
  assign exp_bit_offset = bit_cnt_q[4:0];   // bit_cnt % 32 (bit offset within word)
  assign current_exp_bit = exp_word_q[exp_bit_offset];

  // Counter for memory copy operations
  logic [6:0] copy_cnt_q, copy_cnt_d;

  // mont_mul input operand setup notes:
  // base -> MontDomain: MontMul(base, R^2, n) -> stored at ADDR_MONT_A
  // result init:        MontMul(1, R^2, n)    -> stored at ADDR_RESULT
  // Square:             MontMul(result, result, n)    -> ADDR_RESULT
  // Multiply:           MontMul(result, MONT_A, n)    -> ADDR_RESULT
  // FromMont:           MontMul(result, 1, n)          -> ADDR_RESULT

  // Operand setup for mont_mul
  // mont_mul reads a from ADDR_MONT_A and b from ADDR_BASE
  // Data must be copied for each operation
  logic [3:0] setup_sub_q, setup_sub_d;

  // Remembers the exponent word index read in the previous cycle
  logic [6:0] prev_exp_word_idx_q, prev_exp_word_idx_d;

  // Memory interface defaults
  logic        mem_re_d, mem_we_d;
  logic [9:0]  mem_addr_d;
  logic [WordWidth-1:0] mem_wdata_d;

  // Combinational logic
  always_comb begin
    state_d    = state_q;
    bit_cnt_d  = bit_cnt_q;
    exp_word_d = exp_word_q;
    copy_cnt_d = copy_cnt_q;
    setup_sub_d = setup_sub_q;
    prev_exp_word_idx_d = prev_exp_word_idx_q;

    mem_re_d    = 1'b0;
    mem_we_d    = 1'b0;
    mem_addr_d  = '0;
    mem_wdata_d = '0;

    unique case (state_q)
      StExpIdle: begin
        if (start_i) begin
          // Prepare to convert base into the Montgomery domain
          // Set up a=base, b=R^2 to execute MontMul(base, R^2, n)
          // mont_mul reads a from ADDR_MONT_A and b from ADDR_BASE
          // First copy base -> ADDR_MONT_A, R^2 -> ADDR_BASE
          copy_cnt_d = '0;
          setup_sub_d = '0;
          state_d    = StExpToMont;
        end
      end

      // Copy base -> ADDR_MONT_A (as a), R^2 is at ADDR_RSQ
      // mont_mul reads a=ADDR_MONT_A, b=ADDR_BASE by design
      // ToMont: execute MontMul(base, R^2, n)
      // base is at ADDR_BASE, R^2 is at ADDR_RSQ
      // Since mont_mul reads a=ADDR_MONT_A, b=ADDR_BASE:
      //   copy ADDR_BASE -> ADDR_MONT_A (a=base)
      //   copy ADDR_RSQ  -> ADDR_BASE   (b=R^2)
      // Overwriting ADDR_BASE would destroy the original data, so
      // copy ADDR_BASE -> ADDR_MONT_A first, then ADDR_RSQ -> ADDR_BASE
      StExpToMont: begin
        unique case (setup_sub_q)
          4'd0: begin
            // Read base[copy_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            // Wait for BRAM read
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            // Write to ADDR_MONT_A
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // base -> MONT_A copy done; next copy R^2 -> BASE
              copy_cnt_d  = '0;
              setup_sub_d = 4'd3;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Read R^2[copy_cnt]
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd4;
          end
          4'd4: begin
            // Wait for BRAM read
            setup_sub_d = 4'd5;
          end
          4'd5: begin
            // Write to ADDR_BASE (as b=R^2)
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Zero-clear t[]
              copy_cnt_d  = '0;
              setup_sub_d = 4'd6;
            end else begin
              setup_sub_d = 4'd3;
            end
          end
          4'd6: begin
            // Zero-clear t[]
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = '0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 > num_words) begin
              // Start mont_mul
              state_d = StExpToMontWait;
            end else begin
              setup_sub_d = 4'd6;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      StExpToMontWait: begin
        if (mont_done_i) begin
          // MontMul complete: result is in ADDR_MONT_T
          // Copy ADDR_MONT_T -> ADDR_MONT_A (used as a=base_mont from now on)
          copy_cnt_d  = '0;
          setup_sub_d = '0;
          state_d     = StExpInitR;
        end
      end

      // Initialize result: MontMul(1, R^2, n) -> result = R mod n
      // Would need to set a=1 at ADDR_MONT_A and b=R^2 at ADDR_BASE,
      // but first must save base_mont from ToMont, then set a=1 and b=R^2.
      // Simplified design: perform result init after copying t[] result.
      StExpInitR: begin
        unique case (setup_sub_q)
          4'd0: begin
            // Copy ToMont result t[] -> ADDR_MONT_A
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // base_mont saved.
              // Next: set 1 -> ADDR_MONT_A (temporary) and R^2 -> ADDR_BASE,
              // then execute MontMul(1, R^2, n).
              // To avoid overwriting ADDR_MONT_A, an alternative region is used:
              //   write 1 to ADDR_RESULT and pass it to mont_mul as a.
              // Design choice: set ADDR_BASE=1 and ADDR_MONT_A=R^2 for MontMul.
              // Result lands in t[]. Then copy t[] -> ADDR_RESULT, and restore
              // base_mont from ADDR_MONT_A back to ADDR_MONT_A.
              // base_mont temporarily saved in ADDR_MONT_A will be restored later
              copy_cnt_d  = '0;
              setup_sub_d = 4'd3;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Write 1 to ADDR_BASE (word[0]=1, rest=0)
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = (copy_cnt_q == '0) ? 32'd1 : 32'd0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Copy R^2 to ADDR_MONT_A (as a=R^2)
              // base_mont is currently in ADDR_MONT_A, so it must be saved first
              // -> use ADDR_RESULT as a temporary save area for base_mont
              copy_cnt_d  = '0;
              setup_sub_d = 4'd4;
            end else begin
              setup_sub_d = 4'd3;
            end
          end
          4'd4: begin
            // Save ADDR_MONT_A (base_mont) -> ADDR_RESULT
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd5;
          end
          4'd5: begin
            setup_sub_d = 4'd6;
          end
          4'd6: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_RESULT[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Next: R^2 -> ADDR_MONT_A
              copy_cnt_d  = '0;
              setup_sub_d = 3'd7;
            end else begin
              setup_sub_d = 4'd4;
            end
          end
          4'd7: begin
            // ADDR_RSQ -> ADDR_MONT_A
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RSQ[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd8;
          end
          4'd8: begin
            // Wait for BRAM read
            setup_sub_d = 4'd9;
          end
          4'd9: begin
            // Write to ADDR_MONT_A
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Clear t[]
              copy_cnt_d  = '0;
              setup_sub_d = 4'd10;
            end else begin
              setup_sub_d = 4'd7;
            end
          end
          4'd10: begin
            // Clear t[] then start mont_mul
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = '0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 > num_words) begin
              state_d = StExpInitRWait;
            end else begin
              setup_sub_d = 4'd10;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      StExpInitRWait: begin
        if (mont_done_i) begin
          // MontMul(1, R^2, n) result is in t[]
          // Copy t[] -> ADDR_BASE (used as result)
          // Restore base_mont from ADDR_RESULT back to ADDR_MONT_A
          // Prepare for exponent bit scan
          copy_cnt_d  = '0;
          setup_sub_d = '0;
          bit_cnt_d   = bit_width - 12'd1;  // Start from MSB
          prev_exp_word_idx_d = 7'h7F;  // Invalid sentinel value
          state_d     = StExpCopyResult;
        end
      end

      // Copy MontMul result t[] and saved data
      StExpCopyResult: begin
        unique case (setup_sub_q)
          4'd0: begin
            // t[] -> ADDR_BASE (used as result storage)
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              copy_cnt_d  = '0;
              setup_sub_d = 4'd3;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Restore ADDR_RESULT (base_mont save area) -> ADDR_MONT_A
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd4;
          end
          4'd4: begin
            setup_sub_d = 4'd5;
          end
          4'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              state_d = StExpScan;
            end else begin
              setup_sub_d = 4'd3;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      // Exponent bit scan: read the relevant word
      StExpScan: begin
        // If the exponent word index changed, read from memory
        if (exp_word_idx != prev_exp_word_idx_q) begin
          mem_re_d   = 1'b1;
          mem_addr_d = ADDR_EXP[9:0] + {3'b0, exp_word_idx};
          setup_sub_d = 4'd0;
        end else begin
          // Same word, proceed directly to squaring
          state_d = StExpSquare;
        end
      end

      // Square: MontMul(result, result, n)
      // result is at ADDR_BASE
      // a=result, b=result -> ADDR_MONT_A=result, ADDR_BASE=result (same data)
      StExpSquare: begin
        unique case (setup_sub_q)
          4'd0: begin
            // Copy result (ADDR_BASE) -> ADDR_MONT_A (a=result)
            // b is already at ADDR_BASE (b=result)
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Zero-clear t[]
              copy_cnt_d  = '0;
              setup_sub_d = 4'd3;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          4'd3: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = '0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 > num_words) begin
              // Start mont_mul
              state_d = StExpSquareWait;
              copy_cnt_d = '0;
            end else begin
              setup_sub_d = 4'd3;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      StExpSquareWait: begin
        if (mont_done_i) begin
          // Copy squaring result t[] -> ADDR_BASE
          copy_cnt_d  = '0;
          setup_sub_d = '0;
          // If current bit is 1, multiply; if 0, advance to next bit
          if (current_exp_bit) begin
            state_d = StExpMul;
          end else begin
            // Copy result to ADDR_BASE and move to next bit
            state_d = StExpCopyResult;
          end
        end
      end

      // Multiply: MontMul(result, base_mont, n)
      // result is in t[] (squaring result) -> copy to ADDR_BASE (b=result)
      // base_mont is at ADDR_MONT_A (a=base_mont)
      // However, squaring overwrote ADDR_MONT_A, so base_mont must be restored
      StExpMul: begin
        unique case (setup_sub_q)
          4'd0: begin
            // Copy squaring result t[] -> ADDR_BASE (b=result)
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Restore base_mont from ADDR_RESULT to ADDR_MONT_A.
              // Note: base_mont is no longer at ADDR_RESULT after InitR.
              // Design note: base_mont should ideally be kept in ADDR_MONT_A,
              // but squaring overwrites it.
              // Solution: during squaring, copy result to ADDR_MONT_A (a=result),
              // while saving base_mont to a separate location.
              // This approach is complex, so ADDR_RESULT is used as
              // the persistent home for base_mont.
              // Clear t[] then start mont_mul
              copy_cnt_d  = '0;
              setup_sub_d = 4'd3;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          4'd3: begin
            // Copy ADDR_RESULT (base_mont) -> ADDR_MONT_A
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_RESULT[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd4;
          end
          4'd4: begin
            setup_sub_d = 4'd5;
          end
          4'd5: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Zero-clear t[]
              copy_cnt_d  = '0;
              setup_sub_d = 4'd6;
            end else begin
              setup_sub_d = 4'd3;
            end
          end
          4'd6: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = '0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 > num_words) begin
              state_d = StExpMulWait;  // Start mont_mul
              copy_cnt_d = '0;
            end else begin
              setup_sub_d = 4'd6;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      StExpMulWait: begin
        if (mont_done_i) begin
          // Copy multiplication result t[] -> ADDR_BASE
          copy_cnt_d  = '0;
          setup_sub_d = '0;
          state_d     = StExpCopyResult;
        end
      end

      // Convert back from Montgomery domain: MontMul(result, 1, n)
      StExpFromMont: begin
        unique case (setup_sub_q)
          4'd0: begin
            // Copy result (ADDR_BASE) -> ADDR_MONT_A (a=result)
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_A[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Write 1 to ADDR_BASE (b=1)
              copy_cnt_d  = '0;
              setup_sub_d = 4'd3;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          4'd3: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_BASE[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = (copy_cnt_q == '0) ? 32'd1 : 32'd0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              // Zero-clear t[]
              copy_cnt_d  = '0;
              setup_sub_d = 4'd4;
            end else begin
              setup_sub_d = 4'd3;
            end
          end
          4'd4: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = '0;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 > num_words) begin
              state_d = StExpFromMontWait;  // Start mont_mul
              copy_cnt_d = '0;
            end else begin
              setup_sub_d = 4'd4;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      StExpFromMontWait: begin
        if (mont_done_i) begin
          // Copy result t[] -> ADDR_RESULT
          copy_cnt_d  = '0;
          setup_sub_d = '0;
          state_d     = StExpDone;
        end
      end

      StExpDone: begin
        // Copy final result t[] -> ADDR_RESULT
        unique case (setup_sub_q)
          4'd0: begin
            mem_re_d   = 1'b1;
            mem_addr_d = ADDR_MONT_T[9:0] + {3'b0, copy_cnt_q};
            setup_sub_d = 4'd1;
          end
          4'd1: begin
            setup_sub_d = 4'd2;
          end
          4'd2: begin
            mem_we_d    = 1'b1;
            mem_addr_d  = ADDR_RESULT[9:0] + {3'b0, copy_cnt_q};
            mem_wdata_d = mem_rdata_i;
            copy_cnt_d  = copy_cnt_q + 7'd1;
            if (copy_cnt_q + 7'd1 >= num_words) begin
              state_d = StExpIdle;
            end else begin
              setup_sub_d = 4'd0;
            end
          end
          default: setup_sub_d = 4'd0;
        endcase
      end

      default: state_d = StExpIdle;
    endcase

    // Handle exponent word read completion in StExpScan
    if (state_q == StExpScan && exp_word_idx != prev_exp_word_idx_q) begin
      unique case (setup_sub_q)
        4'd0: begin
          // Wait for memory read
          setup_sub_d = 4'd1;
        end
        4'd1: begin
          exp_word_d = mem_rdata_i;
          prev_exp_word_idx_d = exp_word_idx;
          copy_cnt_d = '0;
          setup_sub_d = 4'd0;
          state_d    = StExpSquare;
        end
        default: setup_sub_d = 4'd0;
      endcase
    end

    // After StExpCopyResult: update bit counter and decide next state
    // After StExpCopyResult completes, either advance to the next bit or go to FromMont
    if (state_q == StExpCopyResult && setup_sub_q == 4'd5) begin
      if (copy_cnt_q + 7'd1 >= num_words) begin
        if (bit_cnt_q == 12'd0) begin
          // All bits scanned -> convert back from Montgomery domain
          copy_cnt_d  = '0;
          setup_sub_d = 4'd0;
          state_d     = StExpFromMont;
        end else begin
          bit_cnt_d   = bit_cnt_q - 12'd1;
          copy_cnt_d  = '0;
          setup_sub_d = 4'd0;
          state_d     = StExpScan;
        end
      end
    end

    // base_mont save area: InitR and Square use ADDR_RESULT to save base_mont
    // Mul restores base_mont from ADDR_RESULT
  end

  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= StExpIdle;
      bit_cnt_q   <= '0;
      exp_word_q  <= '0;
      copy_cnt_q  <= '0;
      setup_sub_q <= '0;
      prev_exp_word_idx_q <= 7'h7F;
      done_o      <= 1'b0;
      mem_re_o    <= 1'b0;
      mem_we_o    <= 1'b0;
      mem_addr_o  <= '0;
      mem_wdata_o <= '0;
      mont_start_o <= 1'b0;
      mont_mode_o  <= 1'b0;
    end else begin
      state_q     <= state_d;
      bit_cnt_q   <= bit_cnt_d;
      exp_word_q  <= exp_word_d;
      copy_cnt_q  <= copy_cnt_d;
      setup_sub_q <= setup_sub_d;
      prev_exp_word_idx_q <= prev_exp_word_idx_d;
      done_o      <= (state_d == StExpIdle) && (state_q == StExpDone);
      mem_re_o    <= mem_re_d;
      mem_we_o    <= mem_we_d;
      mem_addr_o  <= mem_addr_d;
      mem_wdata_o <= mem_wdata_d;
      mont_mode_o <= crt_mode_i;

      // Generate mont_mul start signal
      // Assert when transitioning into ToMontWait, InitRWait, SquareWait, MulWait, or FromMontWait
      mont_start_o <= (state_d == StExpToMontWait && state_q != StExpToMontWait)
                   || (state_d == StExpInitRWait && state_q != StExpInitRWait)
                   || (state_d == StExpSquareWait && state_q != StExpSquareWait)
                   || (state_d == StExpMulWait && state_q != StExpMulWait)
                   || (state_d == StExpFromMontWait && state_q != StExpFromMontWait);
    end
  end

  assign busy_o = (state_q != StExpIdle);

endmodule
