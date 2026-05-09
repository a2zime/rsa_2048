// Description: 32-bit serial I/O controller
//   Receives 32-bit words via Valid/Ready handshake and writes them to the
//   operand memory parameter region specified by addr_i.
//   On output, reads from the result region and transmits as 32-bit words.

module io_controller #(
  parameter int unsigned KeyWidth  = 2048,
  parameter int unsigned WordWidth = 32
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  // External interface
  input  logic                  valid_i,
  output logic                  ready_o,
  input  logic [3:0]            addr_i,
  input  logic [WordWidth-1:0]  data_i,
  output logic                  valid_o,
  input  logic                  ready_i,
  output logic [WordWidth-1:0]  data_o,
  // Internal memory interface
  output logic                  mem_we_o,
  output logic [9:0]            mem_addr_o,
  output logic [WordWidth-1:0]  mem_wdata_o,
  input  logic [WordWidth-1:0]  mem_rdata_i,
  output logic                  mem_re_o,
  // Control
  input  logic                  load_en_i,
  input  logic                  unload_en_i,
  output logic                  load_done_o,
  output logic                  unload_done_o
);

  import rsa_pkg::*;

  // State definition
  typedef enum logic [1:0] {
    StIoIdle,
    StIoLoad,
    StIoUnload
  } io_state_e;

  io_state_e state_d, state_q;

  // Word counter (output side: advances on (valid_i & ready_o) for Load,
  // and on (valid_o & ready_i) for Unload)
  logic [6:0] word_cnt_d, word_cnt_q;

  // Read-address counter for Unload (separate from word_cnt_q so the read
  // pipeline can lead the output handshake by 1 cycle for BRAM latency)
  logic [6:0] read_cnt_d, read_cnt_q;

  // Number of words to transfer
  logic [6:0] num_xfer_words;

  // Parameter ID to memory base address decoder
  logic [9:0] param_base_addr;

  always_comb begin
    unique case (rsa_pkg::param_addr_e'(addr_i))
      ParamBase:   param_base_addr = ADDR_BASE[9:0];
      ParamExp:    param_base_addr = ADDR_EXP[9:0];
      ParamMod:    param_base_addr = ADDR_MOD[9:0];
      ParamRSq:    param_base_addr = ADDR_RSQ[9:0];
      ParamNPrime: param_base_addr = 10'h000;  // Register-held (not stored in memory)
      ParamP:      param_base_addr = ADDR_P[9:0];
      ParamQ:      param_base_addr = ADDR_Q[9:0];
      ParamDp:     param_base_addr = ADDR_DP[9:0];
      ParamDq:     param_base_addr = ADDR_DQ[9:0];
      ParamQinv:   param_base_addr = ADDR_QINV[9:0];
      ParamRSqP:   param_base_addr = ADDR_RSQ_P[9:0];
      ParamRSqQ:   param_base_addr = ADDR_RSQ_Q[9:0];
      ParamNpP:    param_base_addr = 10'h000;  // Register-held
      ParamNqP:    param_base_addr = 10'h000;  // Register-held
      ParamBasP:   param_base_addr = ADDR_BASE_P[9:0];
      ParamBasQ:   param_base_addr = ADDR_BASE_Q[9:0];
      default:     param_base_addr = 10'h000;
    endcase
  end

  // Parameter ID to transfer word count
  always_comb begin
    unique case (rsa_pkg::param_addr_e'(addr_i))
      ParamBase:   num_xfer_words = 7'd64;
      ParamExp:    num_xfer_words = 7'd64;
      ParamMod:    num_xfer_words = 7'd64;
      ParamRSq:    num_xfer_words = 7'd64;
      ParamNPrime: num_xfer_words = 7'd1;
      ParamP:      num_xfer_words = 7'd32;
      ParamQ:      num_xfer_words = 7'd32;
      ParamDp:     num_xfer_words = 7'd32;
      ParamDq:     num_xfer_words = 7'd32;
      ParamQinv:   num_xfer_words = 7'd32;
      ParamRSqP:   num_xfer_words = 7'd32;
      ParamRSqQ:   num_xfer_words = 7'd32;
      ParamNpP:    num_xfer_words = 7'd1;
      ParamNqP:    num_xfer_words = 7'd1;
      ParamBasP:   num_xfer_words = 7'd32;
      ParamBasQ:   num_xfer_words = 7'd32;
      default:     num_xfer_words = 7'd1;
    endcase
  end

  // Address during Unload (result region)
  logic [9:0] unload_base_addr;
  assign unload_base_addr = ADDR_RESULT[9:0];

  // Number of words during Unload (always 64 words = 2048 bits)
  logic [6:0] unload_num_words;
  assign unload_num_words = 7'd64;

  // Read pipeline for Unload (handles 1-cycle BRAM read latency)
  // unload_read_valid_q: skid (unload_data_q) holds an unconsumed word
  // mem_re_q:            mem_re_o was asserted in the previous cycle
  //                      (a read fired and its data is on mem_rdata_i now)
  logic unload_read_valid_q;
  logic mem_re_q;
  logic [WordWidth-1:0] unload_data_q;

  // Combinational logic
  always_comb begin
    state_d    = state_q;
    word_cnt_d = word_cnt_q;
    read_cnt_d = read_cnt_q;

    unique case (state_q)
      StIoIdle: begin
        if (load_en_i) begin
          word_cnt_d = '0;
          state_d    = StIoLoad;
        end else if (unload_en_i) begin
          word_cnt_d = '0;
          read_cnt_d = '0;
          state_d    = StIoUnload;
        end
      end

      StIoLoad: begin
        if (valid_i && ready_o) begin
          if (word_cnt_q == num_xfer_words - 7'd1) begin
            state_d    = StIoIdle;
            word_cnt_d = '0;
          end else begin
            word_cnt_d = word_cnt_q + 7'd1;
          end
        end
      end

      StIoUnload: begin
        if (valid_o && ready_i) begin
          if (word_cnt_q == unload_num_words - 7'd1) begin
            state_d    = StIoIdle;
            word_cnt_d = '0;
          end else begin
            word_cnt_d = word_cnt_q + 7'd1;
          end
        end
        if (mem_re_o) begin
          read_cnt_d = read_cnt_q + 7'd1;
        end
      end

      default: state_d = StIoIdle;
    endcase
  end

  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q             <= StIoIdle;
      word_cnt_q          <= '0;
      read_cnt_q          <= '0;
      mem_re_q            <= 1'b0;
      unload_read_valid_q <= 1'b0;
      unload_data_q       <= '0;
    end else begin
      state_q    <= state_d;
      word_cnt_q <= word_cnt_d;
      read_cnt_q <= read_cnt_d;
      mem_re_q   <= mem_re_o;

      // Skid update for Unload:
      //   - Capture mem_rdata_i into unload_data_q only when a read fired in
      //     the previous cycle (mem_re_q) AND the skid has space (either empty
      //     or being drained this cycle by a successful output handshake).
      //   - Otherwise, if the consumer takes the current word, mark the skid
      //     empty so the next read can fill it.
      if (state_q == StIoUnload) begin
        if (mem_re_q && (!unload_read_valid_q || (valid_o && ready_i))) begin
          unload_data_q       <= mem_rdata_i;
          unload_read_valid_q <= 1'b1;
        end else if (valid_o && ready_i) begin
          unload_read_valid_q <= 1'b0;
        end
      end else begin
        unload_read_valid_q <= 1'b0;
      end
    end
  end

  // Output logic
  // Load: handshake accepted on valid_i & ready_o -> write to memory
  assign ready_o = (state_q == StIoIdle) || (state_q == StIoLoad);

  assign mem_we_o    = (state_q == StIoLoad) && valid_i && ready_o;
  assign mem_addr_o  = (state_q == StIoLoad)
                     ? (param_base_addr + {3'b0, word_cnt_q})
                     : (unload_base_addr + {3'b0, read_cnt_q});
  assign mem_wdata_o = data_i;
  // Issue a read only when:
  //   - State is Unload and we still have words to fetch
  //   - The previous cycle did NOT issue a read (avoid double in-flight, since
  //     the skid is 1-deep and in-flight data would be dropped)
  //   - Skid is empty or being drained this cycle
  assign mem_re_o    = (state_q == StIoUnload)
                    && (read_cnt_q < unload_num_words)
                    && !mem_re_q
                    && (!unload_read_valid_q || (valid_o && ready_i));

  // Unload: output data read from memory (registered into unload_data_q)
  assign valid_o = (state_q == StIoUnload) && unload_read_valid_q;
  assign data_o  = unload_data_q;

  // Done pulses
  assign load_done_o   = (state_q == StIoLoad)
                      && (word_cnt_q == num_xfer_words - 7'd1)
                      && valid_i && ready_o;
  assign unload_done_o = (state_q == StIoUnload)
                      && (word_cnt_q == unload_num_words - 7'd1)
                      && valid_o && ready_i;

endmodule
