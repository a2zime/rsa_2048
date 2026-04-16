// Description: RSA-2048 IP package
//   Defines address map constants and parameter encoding types.

package rsa_pkg;

  localparam int unsigned KEY_WIDTH  = 2048;
  localparam int unsigned WORD_WIDTH = 32;
  localparam int unsigned NUM_WORDS  = KEY_WIDTH / WORD_WIDTH;  // 64

  // Memory address map (word addresses)
  localparam int unsigned ADDR_BASE     = 10'h000;  // base (message/ciphertext)  64w
  localparam int unsigned ADDR_EXP      = 10'h040;  // exponent e or d            64w
  localparam int unsigned ADDR_MOD      = 10'h080;  // modulus n                  64w
  localparam int unsigned ADDR_RSQ      = 10'h0C0;  // R^2 mod n                  64w
  localparam int unsigned ADDR_RESULT   = 10'h100;  // computation result          64w
  localparam int unsigned ADDR_MONT_A   = 10'h140;  // Montgomery form base        64w
  localparam int unsigned ADDR_MONT_T   = 10'h180;  // Montgomery intermediate t[] 65w
  localparam int unsigned ADDR_P        = 10'h1C0;  // CRT: p                      32w
  localparam int unsigned ADDR_Q        = 10'h1E0;  // CRT: q                      32w
  localparam int unsigned ADDR_DP       = 10'h200;  // CRT: dp                     32w
  localparam int unsigned ADDR_DQ       = 10'h220;  // CRT: dq                     32w
  localparam int unsigned ADDR_QINV     = 10'h240;  // CRT: qinv                   32w
  localparam int unsigned ADDR_RSQ_P    = 10'h260;  // CRT: R^2 mod p              32w
  localparam int unsigned ADDR_RSQ_Q    = 10'h280;  // CRT: R^2 mod q              32w
  localparam int unsigned ADDR_M1       = 10'h2A0;  // CRT intermediate: m1        32w
  localparam int unsigned ADDR_M2       = 10'h2C0;  // CRT intermediate: m2        32w
  localparam int unsigned ADDR_HQ       = 10'h2E0;  // CRT intermediate: h*q       64w
  localparam int unsigned ADDR_BASE_P   = 10'h320;  // CRT: base mod p             32w
  localparam int unsigned ADDR_BASE_Q   = 10'h340;  // CRT: base mod q             32w

  // Parameter address encoding (addr_i[3:0])
  typedef enum logic [3:0] {
    ParamBase   = 4'h0,
    ParamExp    = 4'h1,
    ParamMod    = 4'h2,
    ParamRSq    = 4'h3,
    ParamNPrime = 4'h4,
    ParamP      = 4'h5,
    ParamQ      = 4'h6,
    ParamDp     = 4'h7,
    ParamDq     = 4'h8,
    ParamQinv   = 4'h9,
    ParamRSqP   = 4'hA,
    ParamRSqQ   = 4'hB,
    ParamNpP    = 4'hC,
    ParamNqP    = 4'hD,
    ParamBasP   = 4'hE,
    ParamBasQ   = 4'hF
  } param_addr_e;

endpackage
