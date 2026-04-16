// Description: 32x32 multiply-accumulate unit (DSP48E1 wrapper)
//   Computes a * b + c in a 4-cycle pipeline and outputs a 64-bit result.
//   32x32 multiplication is split into four 16x16 partial products.

module mul_add_unit #(
  parameter int unsigned WordWidth = 32
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [WordWidth-1:0]     a_i,
  input  logic [WordWidth-1:0]     b_i,
  input  logic [WordWidth-1:0]     c_i,
  input  logic                     start_i,
  output logic [2*WordWidth-1:0]   result_o,
  output logic                     done_o
);

  localparam int unsigned HALF = WordWidth / 2;  // 16

  // Input latches
  logic [HALF-1:0] a_lo_q, a_hi_q;
  logic [HALF-1:0] b_lo_q, b_hi_q;
  logic [WordWidth-1:0] c_q;

  // Pipeline counter (0..3)
  logic [2:0] cycle_q;
  logic       busy_q;

  // Partial product accumulator
  logic [2*WordWidth-1:0] accum_q;

  // DSP inputs/outputs
  logic [HALF-1:0]    dsp_a;
  logic [HALF-1:0]    dsp_b;
  logic [2*HALF-1:0]  dsp_p;  // 16x16 = 32-bit result

  // DSP multiplication (combinational — maps to DSP48E1 on real device)
  assign dsp_p = {{(2*HALF-2*HALF){1'b0}}} | (dsp_a * dsp_b);

  // DSP input multiplexer
  always_comb begin
    dsp_a = '0;
    dsp_b = '0;
    unique case (cycle_q)
      3'd0: begin  // a_lo * b_lo
        dsp_a = a_lo_q;
        dsp_b = b_lo_q;
      end
      3'd1: begin  // a_lo * b_hi
        dsp_a = a_lo_q;
        dsp_b = b_hi_q;
      end
      3'd2: begin  // a_hi * b_lo
        dsp_a = a_hi_q;
        dsp_b = b_lo_q;
      end
      3'd3: begin  // a_hi * b_hi
        dsp_a = a_hi_q;
        dsp_b = b_hi_q;
      end
      default: begin
        dsp_a = '0;
        dsp_b = '0;
      end
    endcase
  end

  // Main pipeline
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_lo_q  <= '0;
      a_hi_q  <= '0;
      b_lo_q  <= '0;
      b_hi_q  <= '0;
      c_q     <= '0;
      cycle_q <= '0;
      busy_q  <= 1'b0;
      accum_q <= '0;
      done_o  <= 1'b0;
    end else begin
      done_o <= 1'b0;

      if (start_i && !busy_q) begin
        // Latch inputs and start computation
        a_lo_q  <= a_i[HALF-1:0];
        a_hi_q  <= a_i[WordWidth-1:HALF];
        b_lo_q  <= b_i[HALF-1:0];
        b_hi_q  <= b_i[WordWidth-1:HALF];
        c_q     <= c_i;
        cycle_q <= 3'd0;
        busy_q  <= 1'b1;
        accum_q <= '0;
      end else if (busy_q) begin
        unique case (cycle_q)
          3'd0: begin
            // a_lo * b_lo → add to accum[31:0], also add c
            accum_q <= {32'b0, dsp_p} + {32'b0, c_q};
            cycle_q <= 3'd1;
          end
          3'd1: begin
            // a_lo * b_hi → add to accum shifted left by 16
            accum_q <= accum_q + ({32'b0, dsp_p} << HALF);
            cycle_q <= 3'd2;
          end
          3'd2: begin
            // a_hi * b_lo → add to accum shifted left by 16
            accum_q <= accum_q + ({32'b0, dsp_p} << HALF);
            cycle_q <= 3'd3;
          end
          3'd3: begin
            // a_hi * b_hi → add to accum shifted left by 32, done
            accum_q <= accum_q + ({32'b0, dsp_p} << WordWidth);
            busy_q  <= 1'b0;
            done_o  <= 1'b1;
            cycle_q <= '0;
          end
          default: begin
            busy_q  <= 1'b0;
            cycle_q <= '0;
          end
        endcase
      end
    end
  end

  assign result_o = accum_q;

endmodule
