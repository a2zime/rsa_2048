[日本語](README_ja.md) | **English**

# RSA-2048 IP

A hardware IP core for RSA-2048 operations, targeting Xilinx Spartan-7 (XC7S25) and implemented in SystemVerilog.

> **Note**: This implementation is for educational/learning purposes and does not guarantee cryptographic security for production use.

---

## Features

- **Operations**: Encryption / Decryption / Signing / Verification (all reduced to modular exponentiation)
- **Key length**: 2048 bit
- **Algorithm**: FIOS Montgomery multiplication + Left-to-right binary Square-and-Multiply
- **Optimization**: CRT (Chinese Remainder Theorem) for fast private-key operations
- **Interface**: 32-bit serial Valid/Ready handshake
- **DSP**: DSP48E1 × 1 (32×32 multiply-accumulate)
- **Memory**: True Dual-Port BRAM36K × 1

## Performance Estimate (100 MHz)

| Operation | Estimated Time |
|---|---|
| Public-key (e=65537) | ~8.1 ms |
| Private-key (CRT) | ~285 ms |

## Resource Estimate (Spartan-7 XC7S25)

| Resource | Estimated | Available | Utilization |
|---|---|---|---|
| LUT | ~4,000–6,000 | 14,600 | ~30–40% |
| FF | ~2,000–3,000 | 29,200 | ~10% |
| DSP48E1 | 1–2 | 45 | 2–4% |
| BRAM36K | 1 | 30 | 3% |

---

## Directory Structure

```
rsa_2048/
├── docs/               Documentation (requirements, design spec)
│   └── img/            WaveDrom timing chart SVGs
├── rtl/                RTL source (SystemVerilog)
├── tb/                 Testbenches
├── scripts/            Utility scripts
├── common/             Shared coding style and dev-flow rules
└── CLAUDE.md           Claude Code project instructions
```

## Module Hierarchy

```
rsa_top
├── io_controller       32-bit serial I/O (Valid/Ready)
├── mod_exp             Modular exponentiation (Square-and-Multiply)
│   └── mont_mul        Montgomery multiplication (FIOS, 32-bit word)
│       └── mul_add_unit  32×32 multiply-accumulate (DSP48E1 wrapper)
├── crt_controller      CRT orchestration
└── operand_mem         Dual-port BRAM operand storage
```

---

## Development Status

| Step | Status |
|---|---|
| Requirements definition | Done |
| Design specification | Done |
| RTL coding | Not started |
| Verification specification | Not started |
| Testbench & simulation | Not started |

---

## Tools

| Tool | Purpose |
|---|---|
| [Verible](https://github.com/chipsalliance/verible) | Lint & format |
| [Icarus Verilog](http://iverilog.icarus.com/) | Simulation |
| [Verilator](https://www.veripool.org/verilator/) | Fast simulation |
| [GTKWave](https://gtkwave.sourceforge.net/) | Waveform viewer |

```bash
brew tap chipsalliance/verible
brew install verible icarus-verilog verilator gtkwave gh
```

---

## Documentation

- [Requirements Specification](docs/requirements.md)
- [Design Specification](docs/design_spec.md)

## License

MIT License — see [LICENSE](LICENSE) for details.
