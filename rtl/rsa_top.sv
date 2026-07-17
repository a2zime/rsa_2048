// Description: RSA-2048 IP top-level module
//   Handles data routing and overall control among the I/O controller,
//   CRT controller, modular exponentiation engine, and operand memory.

module rsa_top #(
  parameter int unsigned KeyWidth  = 2048,
  parameter int unsigned WordWidth = 32
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  // Input interface
  input  logic                  valid_i,
  output logic                  ready_o,
  input  logic                  mode_i,
  input  logic [3:0]            addr_i,
  input  logic [WordWidth-1:0]  data_i,
  // Output interface
  output logic                  valid_o,
  input  logic                  ready_i,
  output logic [WordWidth-1:0]  data_o,
  // Control
  input  logic                  start_i,
  output logic                  busy_o
);

  import rsa_pkg::*;

  // ---------------------------------------------------------------
  // FSM
  // ---------------------------------------------------------------
  typedef enum logic [2:0] {
    StIdle,
    StLoad,
    StPubExp,
    StCrt,
    StUnload
  } rsa_top_state_e;

  rsa_top_state_e state_d, state_q;

  // n_prime registers (32-bit constants, register-held rather than in memory)
  logic [WordWidth-1:0] n_prime_q;
  logic [WordWidth-1:0] np_prime_q;  // CRT: -p^(-1) mod 2^32
  logic [WordWidth-1:0] nq_prime_q;  // CRT: -q^(-1) mod 2^32

  // n_prime write detection
  logic n_prime_we;
  logic np_prime_we;
  logic nq_prime_we;

  assign n_prime_we  = (state_q == StLoad)
                    && valid_i && ready_o
                    && (rsa_pkg::param_addr_e'(addr_i) == ParamNPrime);
  assign np_prime_we = (state_q == StLoad)
                    && valid_i && ready_o
                    && (rsa_pkg::param_addr_e'(addr_i) == ParamNpP);
  assign nq_prime_we = (state_q == StLoad)
                    && valid_i && ready_o
                    && (rsa_pkg::param_addr_e'(addr_i) == ParamNqP);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      n_prime_q  <= '0;
      np_prime_q <= '0;
      nq_prime_q <= '0;
    end else begin
      if (n_prime_we) begin
        n_prime_q  <= data_i;
      end
      if (np_prime_we) begin
        np_prime_q <= data_i;
      end
      if (nq_prime_we) begin
        nq_prime_q <= data_i;
      end
    end
  end

  // ---------------------------------------------------------------
  // Submodule signals
  // ---------------------------------------------------------------

  // io_controller
  logic        io_mem_we, io_mem_re;
  logic [9:0]  io_mem_addr;
  logic [WordWidth-1:0] io_mem_wdata;
  logic        io_load_done, io_unload_done;
  logic        io_ready, io_valid;
  logic [WordWidth-1:0] io_data_out;

  // mod_exp
  logic        exp_mem_re, exp_mem_we;
  logic [9:0]  exp_mem_addr;
  logic [WordWidth-1:0] exp_mem_wdata;
  logic        exp_done, exp_busy;
  logic        exp_mont_start, exp_mont_mode;

  // mont_mul
  logic        mont_mem_re, mont_mem_we;
  logic [9:0]  mont_mem_addr;
  logic [WordWidth-1:0] mont_mem_wdata;
  logic        mont_done, mont_busy;
  logic [WordWidth-1:0] mont_mul_a, mont_mul_b, mont_mul_c;
  logic        mont_mul_start;

  // crt_controller
  logic        crt_mem_we, crt_mem_re;
  logic [9:0]  crt_mem_addr;
  logic [WordWidth-1:0] crt_mem_wdata;
  logic        crt_done, crt_busy;
  logic        crt_exp_start, crt_exp_crt_mode;
  logic        crt_mul_start;
  logic [WordWidth-1:0] crt_mul_a, crt_mul_b, crt_mul_c;
  logic        crt_mont_start, crt_mont_mode;
  logic        crt_use_nq_prime;

  // mul_add_unit
  logic [WordWidth-1:0] dsp_a, dsp_b, dsp_c;
  logic        dsp_start;
  logic [2*WordWidth-1:0] dsp_result;
  logic        dsp_done;

  // operand_mem
  logic        mem_a_we;
  logic [9:0]  mem_a_addr;
  logic [WordWidth-1:0] mem_a_wdata, mem_a_rdata;
  logic        mem_b_we;
  logic [9:0]  mem_b_addr;
  logic [WordWidth-1:0] mem_b_wdata, mem_b_rdata;

  // ---------------------------------------------------------------
  // Memory port A arbitration
  // Shared by io_controller / crt_controller / mod_exp
  //   StLoad / StUnload : io_controller
  //   StPubExp          : mod_exp
  //   StCrt             : mod_exp when exp_busy (crt_controller's
  //                       StCrtExpP/Q delegates to mod_exp), otherwise
  //                       crt_controller for its own copy/sub/mul/add
  //                       steps.
  // The DSP and mont_mul start arbitration use the same exp_busy gate
  // (see below), so Port A must match — otherwise mod_exp's reads/writes
  // during StCrtExpP/Q go to addresses driven by crt_controller and
  // m1/m2 are never stored.
  // ---------------------------------------------------------------
  always_comb begin
    mem_a_we    = 1'b0;
    mem_a_addr  = '0;
    mem_a_wdata = '0;

    unique case (state_q)
      StLoad, StUnload: begin
        mem_a_we    = io_mem_we;
        mem_a_addr  = io_mem_addr;
        mem_a_wdata = io_mem_wdata;
      end
      StCrt: begin
        if (exp_busy) begin
          mem_a_we    = exp_mem_we;
          mem_a_addr  = exp_mem_addr;
          mem_a_wdata = exp_mem_wdata;
        end else begin
          mem_a_we    = crt_mem_we;
          mem_a_addr  = crt_mem_addr;
          mem_a_wdata = crt_mem_wdata;
        end
      end
      StPubExp: begin
        mem_a_we    = exp_mem_we;
        mem_a_addr  = exp_mem_addr;
        mem_a_wdata = exp_mem_wdata;
      end
      default: begin
        mem_a_we    = 1'b0;
        mem_a_addr  = '0;
        mem_a_wdata = '0;
      end
    endcase
  end

  // Memory port B: exclusively used by mont_mul
  assign mem_b_we    = mont_mem_we;
  assign mem_b_addr  = mont_mem_addr;
  assign mem_b_wdata = mont_mem_wdata;

  // ---------------------------------------------------------------
  // DSP (mul_add_unit) arbitration
  // Shared by mont_mul / crt_controller
  // ---------------------------------------------------------------
  always_comb begin
    dsp_a     = '0;
    dsp_b     = '0;
    dsp_c     = '0;
    dsp_start = 1'b0;

    if (state_q == StCrt && !mont_busy) begin
      // CRT drives DSP directly
      dsp_a     = crt_mul_a;
      dsp_b     = crt_mul_b;
      dsp_c     = crt_mul_c;
      dsp_start = crt_mul_start;
    end else begin
      // mont_mul drives DSP
      dsp_a     = mont_mul_a;
      dsp_b     = mont_mul_b;
      dsp_c     = mont_mul_c;
      dsp_start = mont_mul_start;
    end
  end

  // ---------------------------------------------------------------
  // n_prime mode selection
  // ---------------------------------------------------------------
  logic [WordWidth-1:0] active_n_prime;

  always_comb begin
    if (state_q == StCrt) begin
      // In CRT mode, switch between np_prime / nq_prime based on crt_controller phase
      if (crt_use_nq_prime) begin
        active_n_prime = nq_prime_q;
      end else begin
        active_n_prime = np_prime_q;
      end
    end else begin
      active_n_prime = n_prime_q;
    end
  end

  // ---------------------------------------------------------------
  // FSM transitions
  // ---------------------------------------------------------------
  always_comb begin
    state_d = state_q;

    unique case (state_q)
      StIdle: begin
        if (valid_i && io_ready) begin
          state_d = StLoad;
        end else if (start_i && !mode_i) begin
          state_d = StPubExp;
        end else if (start_i && mode_i) begin
          state_d = StCrt;
        end
      end

      StLoad: begin
        if (io_load_done) begin
          state_d = StIdle;
        end
      end

      StPubExp: begin
        if (exp_done) begin
          state_d = StUnload;
        end
      end

      StCrt: begin
        if (crt_done) begin
          state_d = StUnload;
        end
      end

      StUnload: begin
        if (io_unload_done) begin
          state_d = StIdle;
        end
      end

      default: state_d = StIdle;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
    end else begin
      state_q <= state_d;
    end
  end

  // ---------------------------------------------------------------
  // External port connections
  // ---------------------------------------------------------------
  assign ready_o = io_ready && (state_q == StIdle || state_q == StLoad);
  assign valid_o = io_valid;
  assign data_o  = io_data_out;
  assign busy_o  = (state_q != StIdle);

  // ---------------------------------------------------------------
  // Submodule instances
  // ---------------------------------------------------------------

  io_controller #(
    .KeyWidth  (KeyWidth),
    .WordWidth (WordWidth)
  ) u_io_controller (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .valid_i       (valid_i),
    .ready_o       (io_ready),
    .addr_i        (addr_i),
    .data_i        (data_i),
    .valid_o       (io_valid),
    .ready_i       (ready_i),
    .data_o        (io_data_out),
    .mem_we_o      (io_mem_we),
    .mem_addr_o    (io_mem_addr),
    .mem_wdata_o   (io_mem_wdata),
    .mem_rdata_i   (mem_a_rdata),
    .mem_re_o      (io_mem_re),
    .load_en_i     ((state_q == StIdle) && valid_i && io_ready),
    .unload_en_i   ((state_d == StUnload) && (state_q != StUnload)),
    .load_done_o   (io_load_done),
    .unload_done_o (io_unload_done)
  );

  mod_exp #(
    .MaxWidth  (KeyWidth),
    .WordWidth (WordWidth)
  ) u_mod_exp (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .start_i       ((state_q == StPubExp && !exp_busy && !exp_done)
                  || crt_exp_start),
    .crt_mode_i    ((state_q == StCrt) ? crt_exp_crt_mode : 1'b0),
    .done_o        (exp_done),
    .busy_o        (exp_busy),
    .mem_re_o      (exp_mem_re),
    .mem_we_o      (exp_mem_we),
    .mem_addr_o    (exp_mem_addr),
    .mem_rdata_i   (mem_a_rdata),
    .mem_wdata_o   (exp_mem_wdata),
    .mont_start_o  (exp_mont_start),
    .mont_mode_o   (exp_mont_mode),
    .mont_done_i   (mont_done),
    .mont_busy_i   (mont_busy)
  );

  // mont_mul start arbitration: mod_exp or crt_controller (mutually exclusive)
  logic mont_start_arb;
  logic mont_mode_arb;
  assign mont_start_arb = exp_mont_start || crt_mont_start;
  assign mont_mode_arb  = (state_q == StCrt && !exp_busy) ? crt_mont_mode : exp_mont_mode;

  mont_mul #(
    .MaxWords  (KeyWidth / WordWidth),
    .WordWidth (WordWidth)
  ) u_mont_mul (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .start_i       (mont_start_arb),
    .half_mode_i   (mont_mode_arb),
    .done_o        (mont_done),
    .busy_o        (mont_busy),
    .mem_re_o      (mont_mem_re),
    .mem_we_o      (mont_mem_we),
    .mem_addr_o    (mont_mem_addr),
    .mem_rdata_i   (mem_b_rdata),
    .mem_wdata_o   (mont_mem_wdata),
    .n_prime_i     (active_n_prime),
    .mul_a_o       (mont_mul_a),
    .mul_b_o       (mont_mul_b),
    .mul_c_o       (mont_mul_c),
    .mul_start_o   (mont_mul_start),
    .mul_result_i  (dsp_result),
    .mul_done_i    (dsp_done)
  );

  crt_controller #(
    .KeyWidth  (KeyWidth),
    .WordWidth (WordWidth)
  ) u_crt_controller (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .start_i         ((state_q == StCrt) && !crt_busy && !crt_done),
    .done_o          (crt_done),
    .busy_o          (crt_busy),
    .exp_start_o     (crt_exp_start),
    .exp_crt_mode_o  (crt_exp_crt_mode),
    .exp_done_i      (exp_done),
    .exp_busy_i      (exp_busy),
    .mont_start_o    (crt_mont_start),
    .mont_mode_o     (crt_mont_mode),
    .mont_done_i     (mont_done),
    .mont_busy_i     (mont_busy),
    .use_nq_prime_o  (crt_use_nq_prime),
    .mem_we_o        (crt_mem_we),
    .mem_re_o        (crt_mem_re),
    .mem_addr_o      (crt_mem_addr),
    .mem_wdata_o     (crt_mem_wdata),
    .mem_rdata_i     (mem_a_rdata),
    .mul_start_o     (crt_mul_start),
    .mul_a_o         (crt_mul_a),
    .mul_b_o         (crt_mul_b),
    .mul_c_o         (crt_mul_c),
    .mul_result_i    (dsp_result),
    .mul_done_i      (dsp_done)
  );

  mul_add_unit #(
    .WordWidth (WordWidth)
  ) u_mul_add_unit (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .a_i       (dsp_a),
    .b_i       (dsp_b),
    .c_i       (dsp_c),
    .start_i   (dsp_start),
    .result_o  (dsp_result),
    .done_o    (dsp_done)
  );

  operand_mem #(
    .WordWidth (WordWidth),
    .Depth     (1024)
  ) u_operand_mem (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .a_we_i    (mem_a_we),
    .a_addr_i  (mem_a_addr),
    .a_wdata_i (mem_a_wdata),
    .a_rdata_o (mem_a_rdata),
    .b_we_i    (mem_b_we),
    .b_addr_i  (mem_b_addr),
    .b_wdata_i (mem_b_wdata),
    .b_rdata_o (mem_b_rdata)
  );

endmodule
