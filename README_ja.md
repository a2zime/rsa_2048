**日本語** | [English](README.md)

# RSA-2048 IP

RSA-2048 演算を行うハードウェア IP コア。Xilinx Spartan-7（XC7S25）をターゲットとし、SystemVerilog で実装する。

> **Note**: 本実装は教育・学習目的であり、暗号ライブラリとしての安全性を保証するものではありません。

---

## 特徴

- **対応演算**: 暗号化 / 復号 / 署名 / 検証（すべてモジュラー累乗に帰着）
- **鍵長**: 2048 bit
- **アルゴリズム**: FIOS モンゴメリ乗算 + Left-to-right binary Square-and-Multiply
- **高速化**: CRT（中国剰余定理）による秘密鍵演算の高速化
- **インターフェース**: 32bit シリアル Valid/Ready ハンドシェイク
- **DSP**: DSP48E1 × 1（32×32 積和演算）
- **メモリ**: デュアルポート BRAM36K × 1

## 性能見積り（100 MHz）

| 操作 | 推定時間 |
|---|---|
| 公開鍵演算（e=65537） | ~8.1 ms |
| 秘密鍵演算（CRT） | ~285 ms |

## リソース見積り（Spartan-7 XC7S25）

| リソース | 使用見込み | 利用可能 | 使用率 |
|---|---|---|---|
| LUT | ~4,000–6,000 | 14,600 | ~30–40% |
| FF | ~2,000–3,000 | 29,200 | ~10% |
| DSP48E1 | 1–2 | 45 | 2–4% |
| BRAM36K | 1 | 30 | 3% |

---

## ディレクトリ構成

```
rsa_2048/
├── docs/               ドキュメント（要求仕様・設計仕様）
│   └── img/            WaveDrom タイミングチャート SVG
├── rtl/                RTL ソース（SystemVerilog）
├── tb/                 テストベンチ
├── scripts/            補助スクリプト
├── common/             共通開発ルール・コーディング規約
└── CLAUDE.md           Claude Code 向けプロジェクト指示
```

## モジュール階層

```
rsa_top
├── io_controller       32bit シリアル I/O（Valid/Ready）
├── mod_exp             モジュラー累乗（Square-and-Multiply）
│   └── mont_mul        モンゴメリ乗算（FIOS, 32bit ワード）
│       └── mul_add_unit  32×32 積和演算（DSP48E1 ラッパー）
├── crt_controller      CRT オーケストレーション
└── operand_mem         デュアルポート BRAM オペランドストレージ
```

---

## 開発状況

| 工程 | 状態 |
|---|---|
| 要求仕様定義 | 完了 |
| 設計仕様作成 | 完了 |
| RTL コーディング | 未着手 |
| 検証仕様作成 | 未着手 |
| テストベンチ実装 & シミュレーション | 未着手 |

---

## 使用ツール

| ツール | 用途 |
|---|---|
| [Verible](https://github.com/chipsalliance/verible) | Lint・フォーマット |
| [Icarus Verilog](http://iverilog.icarus.com/) | シミュレーション |
| [Verilator](https://www.veripool.org/verilator/) | 高速シミュレーション |
| [GTKWave](https://gtkwave.sourceforge.net/) | 波形確認 |

```bash
brew tap chipsalliance/verible
brew install verible icarus-verilog verilator gtkwave gh
```

---

## ドキュメント

- [要求仕様書](docs/requirements.md)
- [設計仕様書](docs/design_spec.md)

## ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照。
