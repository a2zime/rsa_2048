# RSA-2048 IP 検証仕様書

**作成日**: 2026年4月18日
**更新日**: 2026年5月11日
**作成者**: a2zime × Claude Code
**バージョン**: 1.8
**前提ドキュメント**:
- [要求仕様書](requirements.md)
- [設計仕様書](design_spec.md)

---

## 変更履歴

| バージョン | 日付 | 変更内容 |
|---|---|---|
| 1.0 | 2026-04-18 | 初版作成 |
| 1.1 | 2026-04-26 | 各検証項目に「検証方法」列を追加。MAU-03/04 の項目名・期待出力の説明を明確化。MAU-07・MM-11 の検証手順を具体化。（Issue #10 対応） |
| 1.2 | 2026-04-28 | §5.2 に最終条件付き減算の説明を追加・MM-08/09 の項目名を明確化。§7.1 の CRT フェーズ網羅とステートカバレッジの関係を明記。§7.2 のカバレッジ目標値に根拠を追記。（Issue #10 追加対応） |
| 1.3 | 2026-04-28 | §7.2 コードカバレッジを「将来目標」から「Step 5 の完了条件」に格上げし、計測コマンドを追記。 |
| 1.4 | 2026-04-28 | §2.2 を新設し、Icarus Verilog と Verilator の使い分けを検証フェーズ・目的別に明記。（Issue #10 追加対応） |
| 1.5 | 2026-04-29 | §5.1 MAU-05 期待値の誤植を修正（0xFFFF_FFFE_0000_0000 → 0xFFFF_FFFF_0000_0000）。（Issue #13 対応） |
| 1.6 | 2026-05-02 | §5.5 MEM-07 を Port A・Port B × addr=0・1023 の 4 ケースに拡充。MEM-09（境界アドレス連続アクセス折り返し）を新規追加。 |
| 1.7 | 2026-05-03 | §5.2 MM-12 サイクル数上限を実測値ベースに修正。25K → 実測値記録方式へ変更。（Issue #20 対応） |
| 1.8 | 2026-05-11 | §5.4 IO-08/IO-13/IO-14 の記載を実装・設計仕様と整合させる。IO-08 は unload が addr_i に依らず常に 64 ワードであることを明示。IO-13 は予約値の存在しない 4bit param_addr_e 仕様に合わせ「全 16 値の境界値カバレッジ補完」に再定義。IO-14 は「load_en が unload_en より優先」を明示。（Issue #28 対応） |

---

## 1. 概要

本ドキュメントは RSA-2048 IP の検証仕様を定義する。
設計仕様に基づき、各モジュールおよび統合時の検証項目、合否判定基準、
テストベクタの生成方法を記述する。

本仕様の目的は以下のとおり。

- 設計仕様の全機能・全モジュールに対して検証項目を網羅する
- シミュレーションによる動作確認の合否判定基準（検証クライテリア）を明確化する
- テストベクタの生成方法・再現性を担保する
- ブログ記事化・FPGA 実装フェーズでの再検証に耐える仕様を与える

---

## 2. 検証環境

### 2.1 使用ツール

| ツール | 用途 | バージョン |
|---|---|---|
| Icarus Verilog（`iverilog`） | 機能検証・波形デバッグ（主検証ツール） | 12.0+ |
| Verilator | 回帰テスト・コードカバレッジ計測 | 5.0+ |
| GTKWave | 波形確認 | 3.3+ |
| Python 3 | 参照モデル・テストベクタ生成 | 3.10+ |
| pycryptodome または cryptography | RSA 参照実装 | 任意 |

### 2.2 シミュレータの使い分け

2 つのシミュレータは目的に応じて以下のように使い分ける。

| フェーズ | シミュレータ | 理由 |
|---|---|---|
| 初回機能検証・デバッグ | Icarus Verilog | VCD 波形を GTKWave で確認できる。SystemVerilog の `$fatal` / `$display` による詳細ログが容易 |
| 波形確認が必要な検証項目（タイミング・プロトコル・FSM トレース） | Icarus Verilog | VCD 出力で波形アサーションの詳細を目視確認できる |
| 回帰テスト（機能確認済み後の繰り返し実行） | Verilator | コンパイル済みバイナリで高速実行。CI 連携に適している |
| コードカバレッジ計測（§7.2） | Verilator | `--coverage` オプションでライン・ブランチ・FSM カバレッジを自動計測できる |

**検証項目ごとの対応:**

- **全検証項目（MAU / MM / ME / IO / MEM / CRT / TOP）**: まず Icarus Verilog で実行し、合否と波形を確認する
- **回帰テスト（develop マージ前の必須実行）**: Verilator で高速実行し、全テスト通過を確認する
- **コードカバレッジ**: Verilator で計測し、§7.2 の目標値を満たすことを確認する

### 2.3 ディレクトリ構成（検証関連）

```
tb/
├── tb_mul_add_unit.sv         mul_add_unit 単体テストベンチ
├── tb_mont_mul.sv             mont_mul 単体テストベンチ
├── tb_mod_exp.sv              mod_exp 単体テストベンチ
├── tb_io_controller.sv        io_controller 単体テストベンチ
├── tb_operand_mem.sv          operand_mem 単体テストベンチ
├── tb_crt_controller.sv       crt_controller 単体テストベンチ
├── tb_rsa_top.sv              rsa_top 統合テストベンチ
└── common/
    ├── tb_utils.sv            共通タスク（hex ロード・メモリ比較等）
    └── test_vectors/          テストベクタ（hex ファイル）

scripts/
├── gen_mont_vectors.py        モンゴメリ乗算のリファレンス生成
├── gen_modexp_vectors.py      モジュラー累乗のリファレンス生成
├── gen_rsa_vectors.py         RSA 公開鍵・秘密鍵（CRT）ベクタ生成
└── gen_mul_add_vectors.py     32×32 積和演算のベクタ生成
```

### 2.4 実行コマンド（標準形式）

```bash
# 単体テスト
iverilog -g2012 -o sim.out tb/tb_<module>.sv rtl/<deps>.sv
vvp sim.out +vcd

# 高速回帰
verilator --binary -j 0 -Wall tb/tb_<module>.sv rtl/<deps>.sv
./obj_dir/Vtb_<module>

# 波形確認
gtkwave dump.vcd
```

---

## 3. 検証クライテリア（合否判定基準）

### 3.1 共通クライテリア

全テストベンチに以下を必須とする。

| ID | 項目 | 基準 |
|---|---|---|
| C-01 | 機能一致 | 参照モデル（Python）出力と DUT 出力が全ビット一致すること |
| C-02 | プロトコル準拠 | Valid/Ready ハンドシェイクで `valid` がアサートされている間データ値が変化しないこと |
| C-03 | リセット初期化 | `rst_n` 解除後、全出力が仕様通りの初期値（`valid=0`, `busy=0` 等）であること |
| C-04 | ラッチ推論なし | Verible lint と合成警告（将来）でラッチ推論が検出されないこと |
| C-05 | X/Z 伝播なし | 出力信号（`data_o`, `valid_o`, `done_o` 等）に X/Z が出現しないこと |
| C-06 | タイムアウト検出 | 期待時刻までに完了通知（`done_o` / `valid_o`）が来ない場合にテスト失敗と判定すること |
| C-07 | テスト完了ログ | `$display("TEST PASSED")` または `$display("TEST FAILED")` を最終出力すること |

### 3.2 合否判定の実装方針

テストベンチは以下の構造を標準とする。

```
1. DUT リセット
2. 参照入力ベクタを Python で事前生成（hex ファイル）
3. DUT に入力・期待値をロード
4. DUT 実行
5. DUT 出力と期待値の bit-exact 比較
6. 全ケース通過なら TEST PASSED、1 ケースでも不一致なら TEST FAILED
```

シミュレーションの exit code は Icarus Verilog の `$fatal` / `$finish` を使い、
CI 連携時に終了コードで合否判定できるようにする。

---

## 4. テストベクタ生成方法

### 4.1 参照モデル

Python で実装した参照モデルを唯一の正解源（golden model）とする。
ハンドコードによるベクタは誤り混入の温床となるため、原則として使わない。

### 4.2 ベクタの形式

テストベクタは以下の形式で供給する。

- **hex ファイル**（`$readmemh` 互換）: 32bit ワード単位で 1 行 1 ワード、LSB-first
- **ファイル命名**: `<module>_<caseid>_<signal>.hex`（例: `mont_mul_tc01_a.hex`）
- **メタデータ**: 各ケースについて `<caseid>.json` に入力アドレス・期待出力・説明を記述

### 4.3 Python 参照モデルの責務

| スクリプト | 生成内容 |
|---|---|
| `gen_mul_add_vectors.py` | `result = a*b + c`（a,b: 32bit, c: 32bit, result: 64bit）のランダム/境界ベクタ |
| `gen_mont_vectors.py` | `MontMul(a, b, n) = a*b*R^(-1) mod n`（R = 2^2048 or 2^1024）、および前計算値 `R^2 mod n`、`n'[0]` |
| `gen_modexp_vectors.py` | `base^exp mod n` と、その中間状態（Montgomery 形式の base/result、指数ビット列） |
| `gen_rsa_vectors.py` | RSA-2048 鍵ペア（p, q, n, e, d, dp, dq, qinv）、暗号化/復号/署名/検証の入出力、CRT 中間値 |

### 4.4 既知ベクタの取り込み

`gen_rsa_vectors.py` は以下を取り込む／再現できること。

- NIST FIPS 186-4 / SP 800-56B の RSA テストベクタ
- OpenSSL 生成の鍵・暗号文ペア（`openssl rsautl` 等で再現可能）

これにより「自前参照実装が間違っている」リスクを低減する。

### 4.5 再現性

- 乱数シードは各スクリプト先頭で明示（例: `random.seed(0xA2Z1_RSA2048)`）
- 生成結果の SHA-256 を `test_vectors/CHECKSUMS.txt` に記録

---

## 5. モジュール別検証項目

### 検証方法の凡例

各テーブルの「検証方法」列で使用する手順の略称を以下に示す。

| 略称 | 内容 |
|---|---|
| bit-exact比較 | Python参照モデルの出力と DUT 出力を全ビット一致で確認（不一致は `$fatal`） |
| サイクルカウント | テストベンチのカウンタで start_i アサートから done_o アサートまでのクロック数を計測し、期待値と一致することを `$display` で確認 |
| 波形アサーション | SystemVerilog `assert` または GTKWave 波形で信号状態・遷移を確認（違反時は `$fatal`） |
| 波形確認 | 対象信号の値・タイミングを `$display` ログまたは波形で目視確認 |

---

### 5.1 mul_add_unit — 32×32 積和演算ユニット

**参照モデル:** Python の任意精度整数演算で `result = (a*b + c) & ((1<<64)-1)`。

**タイミング要求:** `start_i` アサート後、5 サイクルで `done_o` がアサートされること。

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| MAU-01 | 基本動作（乗算のみ） | 正常系 | a=0x1234_5678, b=0x9ABC_DEF0, c=0 | `a*b` の 64bit 値 | Python `(a*b) & (2**64-1)` と DUT result_o を bit-exact比較 |
| MAU-02 | 基本動作（積和） | 正常系 | ランダム a, b, c（100 ケース） | `(a*b+c) & 2^64-1` | 全 100 ケースで Python参照と DUT result_o を bit-exact比較 |
| MAU-03 | ゼロ入力（a=0） | 境界値 | a=0, b=任意, c=任意 | result_o = c（a×b = 0 のため乗算項が消え加算項のみ残る） | Python `(0*b+c) & (2**64-1)` と DUT result_o を bit-exact比較。期待値が c そのものであることを確認 |
| MAU-04 | ゼロ入力（b=0） | 境界値 | a=任意, b=0, c=任意 | result_o = c（a×b = 0 のため乗算項が消え加算項のみ残る） | Python `(a*0+c) & (2**64-1)` と DUT result_o を bit-exact比較。期待値が c そのものであることを確認 |
| MAU-05 | 全ビット最大入力 | 境界値 | a=0xFFFF_FFFF, b=0xFFFF_FFFF, c=0xFFFF_FFFF | 0xFFFF_FFFF_0000_0000 | Python参照と DUT result_o を bit-exact比較 |
| MAU-06 | 桁上がり最大（64bit 収まり確認） | 境界値 | a=0xFFFF_FFFF, b=0xFFFF_FFFF, c=0xFFFF_FFFF | オーバーフローせず 64bit 以内に収まること | result_o が 64bit 幅に収まること（Python参照と bit-exact比較で自動的に確認）。波形アサーションで result_o[63:0] に X/Z が出ないことも確認 |
| MAU-07 | 5 サイクルレイテンシ | タイミング | start_i アサートから done_o アサートまでのクロック数 | ちょうど 5 クロック | テストベンチで start_i アサートサイクルを起点にカウンタを起動し、done_o がアサートされたサイクルのカウント値が 5 と一致することを `$display` で出力・確認。不一致の場合は `$fatal` で終了 |
| MAU-08 | 連続実行 | 正常系 | done_o アサート後、次サイクルで再び start_i | 各回の result_o が参照値と一致 | 連続 N 回実行し、各回 Python参照と DUT result_o を bit-exact比較 |
| MAU-09 | リセット中 start 無視 | 異常系 | rst_n=0 中に start_i をアサート | done_o が立たず、result_o が 0 | 波形アサーションで rst_n=0 期間中 done_o=0 かつ result_o=0 であることを確認（違反時 `$fatal`） |
| MAU-10 | 入力安定性違反は呼出側責務 | — | start 中の a,b,c 変化は未定義（呼び出し側で保証） | 検証対象外（設計前提） | — |

**合否判定:** 全ケースで result_o・done_o の時刻と値が参照と bit-exact 一致。

---

### 5.2 mont_mul — モンゴメリ乗算器（FIOS）

**参照モデル:**
```python
def mont_mul(a, b, n, R, n_prime):
    t = a * b
    m = (t * n_prime) & (R - 1)
    t = (t + m * n) >> R.bit_length() - 1  # R = 2^s
    if t >= n:
        t -= n
    return t
```

**タイミング要求:** `start_i` アサート後、モード別サイクル数の範囲内で `done_o` アサート。
- 2048bit モード: 概ね 24K〜27K サイクル（設計仕様 §6.2）
- 1024bit モード: 概ね 6K〜8K サイクル

**最終条件付き減算について:**
FIOS アルゴリズムの最終ステップでは `if t >= n: t -= n` という条件付き減算を実行する。
- **減算実行（発火する）**: 中間結果 t が剰余 n 以上になった場合に減算を行い `t - n` を返すパス
- **減算スキップ（発火しない）**: 中間結果 t が n 未満のままで減算をスキップし `t` をそのまま返すパス

両パスを網羅することで、条件付き減算の RTL 実装（`sub_en` 制御）を確認する（MM-08, MM-09）。

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| MM-01 | 2048bit 基本動作 | 正常系 | NIST 鍵由来の a, b, n（5 ケース） | 参照値と一致 | Python `mont_mul()` と DUT result_o を bit-exact比較 |
| MM-02 | 2048bit ランダム | 正常系 | ランダム a, b, n（n は奇数・MSB=1）（20 ケース） | 参照値と一致 | 全 20 ケースで Python参照と DUT result_o を bit-exact比較 |
| MM-03 | 1024bit 基本動作（half_mode） | 正常系 | CRT パラメータ由来の a, b, p（5 ケース） | 参照値と一致 | Python `mont_mul()` と DUT result_o を bit-exact比較 |
| MM-04 | 1024bit ランダム | 正常系 | ランダム a, b, p（20 ケース） | 参照値と一致 | 全 20 ケースで Python参照と DUT result_o を bit-exact比較 |
| MM-05 | a = 0 | 境界値 | a=0, b=任意, n=任意 | 0 | Python参照（結果 = 0）と DUT result_o を bit-exact比較 |
| MM-06 | b = 0 | 境界値 | a=任意, b=0, n=任意 | 0 | Python参照（結果 = 0）と DUT result_o を bit-exact比較 |
| MM-07 | a = n-1, b = n-1 | 境界値 | 最大オペランド | 参照値と一致 | Python参照と DUT result_o を bit-exact比較 |
| MM-08 | 最終条件付き減算（減算実行） | 境界値 | 中間 t ≥ n となる入力（`t - n` パスを通るケース） | `t - n` が返される | Python参照と DUT result_o を bit-exact比較。波形で内部 `sub_en` 信号がアサートされることを確認 |
| MM-09 | 最終条件付き減算（減算スキップ） | 境界値 | 中間 t < n のままとなる入力（減算不要なケース） | `t` がそのまま返される | Python参照と DUT result_o を bit-exact比較。波形で内部 `sub_en` 信号が非アサートであることを確認 |
| MM-10 | R^(-1) 性質検証 | 機能 | MontMul(a, R^2 mod n, n) × MontMul(1, 1, n) 等 | 数学的恒等式が成立すること | Python参照の恒等式結果と DUT 出力を bit-exact比較 |
| MM-11 | half_mode 切替 | 機能 | 2048→1024→2048 と連続実行（各 1 ケース以上） | 各回とも正しい幅で動作 | ① 各回 Python参照（2048bit または 1024bit の `mont_mul()`）と DUT result_o を bit-exact比較 ② 波形で内部カウンタ（`step_cnt`）の最大値が 2048bit モードでは 2048・1024bit モードでは 1024 に切り替わっていることを確認 |
| MM-12 | 内部ループサイクル数 | タイミング | 2048bit MontMul の done 時刻 | 実測値を記録（上限規定なし） | サイクルカウント（start_i〜done_o 間）を計測し `$display` で出力。現状実装での実測値: **78,209 サイクル @ 100MHz**（将来の最適化時の基準値として記録） |
| MM-13 | t[] の残留影響なし | 機能 | 連続 MontMul（t[] が初期化されること） | 次回演算に前回の中間値が影響しないこと | 同一入力を 2 回連続実行し、2 回とも同一の Python参照値と bit-exact比較 |
| MM-14 | リセット中 start 無視 | 異常系 | rst_n=0 中 start_i | done_o 立たず busy_o=0 | 波形アサーションで rst_n=0 期間中 done_o=0 かつ busy_o=0 を確認（違反時 `$fatal`） |
| MM-15 | mul_add_unit との接続 | プロトコル | mul_start / mul_done / mul_result の波形整合 | start→5cyc→done の不変条件 | 波形アサーションで mul_start アサートから 5 サイクル後に mul_done がアサートされることを確認 |
| MM-16 | メモリポート衝突なし | プロトコル | Port B の re/we 同時アサートなし | 同一サイクルで re=1 かつ we=1 にならない | 波形アサーションで `b_re && b_we` の同時アサートを検出（発生した場合 `$fatal`） |

**合否判定:** MM-01〜MM-11 は bit-exact 一致。MM-12 は実測値を記録（合否判定なし）。
MM-13〜MM-16 は波形アサーションで検出。

---

### 5.3 mod_exp — モジュラー累乗エンジン

**参照モデル:** Python の `pow(base, exp, n)`。

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| ME-01 | 2048bit 基本動作（e=65537） | 正常系 | NIST 鍵 3 種 | 参照値と一致 | Python `pow(base, e, n)` と DUT result_o を bit-exact比較 |
| ME-02 | 2048bit 基本動作（e=3） | 正常系 | ランダム鍵 | 参照値と一致 | Python参照と DUT result_o を bit-exact比較 |
| ME-03 | 2048bit ランダム指数 | 正常系 | 2048bit 指数ランダム（5 ケース） | 参照値と一致 | 全 5 ケースで Python参照と DUT result_o を bit-exact比較 |
| ME-04 | 1024bit モード（CRT 前提） | 正常系 | 1024bit の (base, dp, p) 等（5 ケース） | 参照値と一致 | Python `pow(base, dp, p)` と DUT result_o を bit-exact比較 |
| ME-05 | exp = 0 | 境界値 | base=任意, exp=0, n=任意 | 1 mod n | Python `pow(base, 0, n)` = 1 と DUT result_o を bit-exact比較 |
| ME-06 | exp = 1 | 境界値 | base=任意, exp=1, n=任意 | base mod n | Python参照と DUT result_o を bit-exact比較 |
| ME-07 | base = 0 | 境界値 | base=0, exp≠0, n=任意 | 0 | Python参照（結果 = 0）と DUT result_o を bit-exact比較 |
| ME-08 | base = 1 | 境界値 | base=1, exp=任意, n=任意 | 1 | Python参照（結果 = 1）と DUT result_o を bit-exact比較 |
| ME-09 | base = n-1（= -1 mod n） | 境界値 | base=n-1 | exp の偶奇で n-1 or 1 | Python参照と DUT result_o を bit-exact比較 |
| ME-10 | 最上位ビットのみ 1 | 境界値 | exp = 2^2047 | 正しく計算されること | Python参照と DUT result_o を bit-exact比較 |
| ME-11 | 最下位ビットのみ 1 | 境界値 | exp = 1 | base mod n | Python参照と DUT result_o を bit-exact比較 |
| ME-12 | MSB→LSB 走査順の確認 | 機能 | 既知指数での中間結果トレース | 設計仕様の走査順と一致 | 波形で mont_start アサートのタイミングと指数ビット列の処理順序を照合 |
| ME-13 | ToMont / FromMont 正当性 | 機能 | Montgomery 変換前後の値を参照と比較 | 変換が bit-exact | Python参照の Montgomery 変換値と DUT 内部信号（波形）を照合 |
| ME-14 | 連続 2 回実行 | 機能 | done_o 後すぐ次の start_i | 2 回目も正しく完了 | 2 回とも Python参照と DUT result_o を bit-exact比較 |
| ME-15 | リセット中断耐性 | 異常系 | 演算中 rst_n=0 → 再開 | 次の start_i で正常動作 | リセット後に再実行し、Python参照と DUT result_o を bit-exact比較 |
| ME-16 | mont_mul 起動数 | トレース | mont_start アサート回数 | 設計想定数（例: 17bit指数 → 33 回） | 波形で mont_start_o のアサート回数をカウントし、期待値と一致することを `$display` で確認 |

**合否判定:** ME-01〜ME-11 は最終結果の bit-exact 一致。ME-12, ME-13 は中間波形トレース比較。

---

### 5.4 io_controller — 32bit シリアル I/O コントローラ

**参照モデル:** Python で (addr_i, N, LSB-first) から mem_addr, mem_wdata の期待列を生成。

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| IO-01 | 2048bit パラメータロード | 正常系 | addr_i=ParamBase, 64 ワード | mem_addr=ADDR_BASE..+63 の順、mem_wdata 一致 | Python生成の期待アドレス列・データ列と DUT mem_addr_o / mem_wdata_o を bit-exact比較 |
| IO-02 | 1024bit パラメータロード | 正常系 | addr_i=ParamP, 32 ワード | mem_addr=ADDR_P..+31、load_done が 32 サイクル目に 1 パルス | Python参照と bit-exact比較。サイクルカウントで load_done の発生サイクルを確認 |
| IO-03 | 32bit パラメータロード | 正常系 | addr_i=ParamNPrime 相当, 1 ワード | 1 サイクルで load_done | サイクルカウントで load_done が 1 サイクル目にアサートされることを確認 |
| IO-04 | 全パラメータ ID 網羅 | 正常系 | param_addr_e の 16 種全て | それぞれ正しい ADDR_* にマップされること | 全 16 種の addr_i に対して Python参照のアドレスマップと mem_addr_o を bit-exact比較 |
| IO-05 | LSB-first 順序 | 機能 | 入力列 w0, w1, ..., w63 | word_cnt=0 のとき LSB（w0）が書かれる | 波形で mem_addr_o の初期値と mem_wdata_o = w0 を確認 |
| IO-06 | load_done パルス幅 | プロトコル | 最終ワード受信時 | 1 クロック幅のパルス | 波形アサーションで load_done_o のアサート期間がちょうど 1 サイクルであることを確認 |
| IO-07 | unload 2048bit | 正常系 | unload_en_i, N=64 | data_o が 64 ワード出力、unload_done が最終 | Python生成の期待データ列と DUT data_o を bit-exact比較。unload_done のタイミングを波形確認 |
| IO-08 | unload は addr_i に依らず 64 ワード固定 | 機能 | addr_i=ParamP, unload_en_i | 64 ワード出力（ADDR_RESULT 領域）、unload_done が 64 ワード目に 1 パルス | Python生成の期待データ列と DUT data_o を bit-exact比較。設計仕様 §4.2 に基づき結果領域は常に 2048bit（unload_num_words=64 固定）であることを確認 |
| IO-09 | Valid/Ready ハンドシェイク | プロトコル | ready_o=0 中は word_cnt 変化なし | Valid/Ready 成立サイクルのみカウント進行 | 波形アサーションで ready_o=0 期間中 word_cnt が変化しないことを確認 |
| IO-10 | ready_i バックプレッシャ | プロトコル | unload 中 ready_i=0 期間 | valid_o と data_o が保持され、カウンタ停止 | 波形アサーションで ready_i=0 期間中 valid_o と data_o が保持されることを確認 |
| IO-11 | 連続パラメータロード | 機能 | param1 → param2 を連続投入 | 各パラメータで load_done が 1 回、領域が干渉しない | 各パラメータのアドレス領域に対して Python参照と mem_addr_o / mem_wdata_o を bit-exact比較 |
| IO-12 | リセット中の load_en 無視 | 異常系 | rst_n=0 中 load_en_i | mem_we_o が立たない | 波形アサーションで rst_n=0 期間中 mem_we_o=0 を確認（違反時 `$fatal`） |
| IO-13 | param_addr_e 4bit 最大値の単独確認 | 機能 | addr_i=ParamBasQ（4'hF） | 32 ワード正常書込、load_done パルス 1 回 | IO-04 で全 16 値を網羅済み。本ケースは 4bit 最大値での回帰防止確認。`param_addr_e` は ParamBase=4'h0〜ParamBasQ=4'hF の 16 値全てを定義済みで予約値は存在しない |
| IO-14 | load_en_i と unload_en_i 同時アサート時の優先度 | プロトコル | 両 enable を同時アサート | load_en_i が優先され StIoLoad に遷移（mem_we_o アサート、valid_o は立たない） | RTL の `if (load_en_i) ... else if (unload_en_i)` 順により load が優先。mem_we_o の立ち上がりと valid_o=0 を波形で確認 |

**合否判定:** mem_addr_o / mem_wdata_o / data_o / load_done_o / unload_done_o の波形が
参照シーケンスと bit-exact 一致。

---

### 5.5 operand_mem — デュアルポート BRAM

**参照モデル:** Python の 1024 要素配列（初期 0）を Port A / Port B の操作で更新する動作モデル。

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| MEM-01 | Port A 単独ライト→リード | 正常系 | a_we_i でアドレス書込 → リード | 書いた値がリードで返る | Python配列モデルのリード値と DUT a_rdata_o を bit-exact比較 |
| MEM-02 | Port B 単独ライト→リード | 正常系 | b_we_i でアドレス書込 → リード | 書いた値がリードで返る | Python配列モデルのリード値と DUT b_rdata_o を bit-exact比較 |
| MEM-03 | 読み出しレイテンシ | タイミング | リード要求 → rdata 確定 | BRAM ネイティブのレイテンシ（1 クロック）と一致 | サイクルカウントでリード要求の 1 サイクル後に rdata が確定することを波形確認 |
| MEM-04 | Port A/B 異アドレス同時アクセス | 正常系 | 同サイクルで別アドレスに A ライト / B ライト | 各アドレスが独立に更新 | 各アドレスをそれぞれリードし、Python配列モデルの値と bit-exact比較 |
| MEM-05 | Port A/B 同アドレス同時リード | 正常系 | 同サイクルで両ポートから同一アドレス読み | 両 rdata が同じ値 | a_rdata_o と b_rdata_o が一致することを波形アサーションで確認 |
| MEM-06 | Port A/B 同アドレス同時ライト競合 | 異常系 | 設計上禁止（rsa_top FSM で保証） | テストでは発生しないことを確認（アサーション） | 波形アサーションで `a_we && b_we && (a_addr == b_addr)` が発生しないことを確認（発生時 `$fatal`） |
| MEM-07 | 境界アドレス | 境界値 | addr=0 / addr=Depth-1 を Port A・Port B の両方でアクセス（計 4 ケース） | 正常アクセス | Python配列モデルと DUT rdata を bit-exact比較 |
| MEM-08 | リセット後の内容 | 機能 | rst_n 解除直後のリード | BRAM 初期化仕様に従う（通常は不定、検証対象外）| 波形確認（X/Z 伝播がないことを目視確認） |
| MEM-09 | 境界アドレス連続アクセス（折り返し） | 境界値 | addr=1023 書込直後に addr=0 書込、その後 1023→0 の順でリード（Port A・Port B 各 1 回） | 各アドレスに書いた値がそれぞれリードで返る（アドレス間の汚染なし） | 1023 と 0 のリード値をそれぞれ Python配列モデルと bit-exact比較 |

**合否判定:** MEM-01〜MEM-05, MEM-07, MEM-09 はリードデータの bit-exact 一致。
MEM-06 は SystemVerilog アサーションで検出（発火しないこと）。

---

### 5.6 crt_controller — CRT オーケストレーション

**参照モデル:**
```python
def crt_decrypt(c, p, q, dp, dq, qinv):
    m1 = pow(c % p, dp, p)
    m2 = pow(c % q, dq, q)
    h = (qinv * ((m1 - m2) % p)) % p
    return m2 + h * q
```

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| CRT-01 | 基本 CRT 復号 | 正常系 | NIST 鍵 3 種での復号 | `pow(c, d, n)` と一致 | Python `crt_decrypt()` と DUT 最終出力を bit-exact比較 |
| CRT-02 | CRT 署名 | 正常系 | NIST 鍵での署名 | `pow(m, d, n)` と一致 | Python参照と DUT 最終出力を bit-exact比較 |
| CRT-03 | m1 < m2（負補正あり） | 境界値 | m1 - m2 < 0 となるケース | `+p` 補正が働き、正しく h が得られる | Python参照と DUT 最終出力を bit-exact比較。波形で内部補正加算パスが通ることを確認 |
| CRT-04 | m1 ≥ m2（負補正なし） | 境界値 | 補正不要なケース | 補正せず正しく動作 | Python参照と DUT 最終出力を bit-exact比較。波形で補正加算パスが通らないことを確認 |
| CRT-05 | h = 0（m1 == m2） | 境界値 | 稀だが数学的に成立するケース | result = m2 | Python参照（result = m2）と DUT 最終出力を bit-exact比較 |
| CRT-06 | ExpP / ExpQ の n_prime 切替 | 機能 | use_nq_prime_o の波形 | ExpP で 0、ExpQ で 1 | 波形アサーションで FSM 状態 StExpP 中に use_nq_prime_o=0、StExpQ 中に=1 を確認 |
| CRT-07 | MulQinv の 2 回 MontMul | 機能 | mont_start_o のアサート回数 | ちょうど 2 回 | 波形で MulQinv ステート中の mont_start_o アサート回数をカウントし、2 と一致することを `$display` で確認 |
| CRT-08 | StCrtMulHQ の mul_add_unit 駆動 | 機能 | h×q ワード単位乗算の結果 | 1024×1024→2048bit の schoolbook 参照値と一致 | Python参照（h×q の 2048bit 積）と DUT の対応出力信号を bit-exact比較 |
| CRT-09 | StCrtAddM2 の 2048bit 加算 | 機能 | result = m2 + h*q | 2048bit 内でオーバーフローしない（数学的に保証）ことを確認 | Python参照と DUT 最終出力を bit-exact比較。波形アサーションで result が 2048bit に収まることを確認 |
| CRT-10 | 状態遷移順序 | プロトコル | FSM の状態トレース | 設計仕様の遷移順どおり | 波形で state_q の遷移が設計仕様 §X の順序と一致することを確認 |
| CRT-11 | mod_exp 完了待ちの排他性 | プロトコル | ExpPWait 中に mont_start_o が出ない | 直接駆動と mod_exp 経由の競合がない | 波形アサーションで StExpPWait 中に mont_start_o=0 であることを確認（違反時 `$fatal`） |
| CRT-12 | リセット中断耐性 | 異常系 | 演算中 rst_n=0 | 再開時に正常動作 | リセット後に再実行し、Python参照と DUT 最終出力を bit-exact比較 |

**合否判定:** CRT-01〜CRT-05 は最終結果の bit-exact 一致。CRT-06〜CRT-11 は波形トレース比較。

---

### 5.7 rsa_top — トップレベル統合

**参照モデル:** Python の `cryptography` / `pycryptodome` による RSA 暗号化・復号・署名・検証。

| ID | 検証項目 | 種別 | 入力 / 条件 | 期待出力 | 検証方法 |
|---|---|---|---|---|---|
| TOP-01 | 暗号化（mode=0） | 正常系 | NIST 鍵の `c = m^e mod n`（3 ケース） | 参照 c と一致 | Python参照と DUT 出力を bit-exact比較 |
| TOP-02 | 検証（mode=0） | 正常系 | `m = s^e mod n`（3 ケース） | 参照 m と一致 | Python参照と DUT 出力を bit-exact比較 |
| TOP-03 | 復号（mode=1, CRT） | 正常系 | `m = c^d mod n`（3 ケース） | 参照 m と一致 | Python参照と DUT 出力を bit-exact比較 |
| TOP-04 | 署名（mode=1, CRT） | 正常系 | `s = m^d mod n`（3 ケース） | 参照 s と一致 | Python参照と DUT 出力を bit-exact比較 |
| TOP-05 | 復号 → 暗号化の往復 | 機能 | `Dec(Enc(m)) == m` | 一致 | DUT の復号出力と元の平文 m を bit-exact比較 |
| TOP-06 | 署名 → 検証の往復 | 機能 | `Ver(Sign(m)) == m` | 一致 | DUT の検証出力と元のメッセージ m を bit-exact比較 |
| TOP-07 | 連続 2 回演算 | 機能 | busy_o=0 を確認してから次の start_i | 2 回とも正しく完了 | 2 回とも Python参照と DUT 出力を bit-exact比較 |
| TOP-08 | mode 切替（0→1→0） | 機能 | 公開→CRT→公開 の連続 | 各回とも正しく完了 | 各回 Python参照と DUT 出力を bit-exact比較 |
| TOP-09 | パラメータロード順不同 | 機能 | base, exp, n, R^2 の順序を入れ替え | どの順でも正しくロード | 複数の順序パターンで Python参照と DUT 出力を bit-exact比較 |
| TOP-10 | 不足パラメータでの start | 異常系 | 必要パラメータ未ロードで start_i | 仕様どおりの挙動（エラー or 未定義動作の明示） | 波形確認（動作が仕様どおりであることを確認。エラー出力があれば波形アサーションで確認） |
| TOP-11 | busy_o 期間の start_i 無視 | 異常系 | busy_o=1 中に start_i | 2 回目の start は無視される | 波形アサーションで busy_o=1 中の追加 start_i が FSM 状態遷移を引き起こさないことを確認 |
| TOP-12 | ready_i バックプレッシャ | プロトコル | unload 中 ready_i を長期 Low | データ保持、最終的に全ワード出力完了 | バックプレッシャ解除後に全ワードが Python参照と bit-exact一致で出力されることを確認 |
| TOP-13 | 性能（e=65537, 公開鍵） | 性能 | 暗号化 1 回の所要サイクル | 設計想定（~811K サイクル）±10% | サイクルカウント（start_i〜done_o 間）を計測し、729,900〜892,100 の範囲内であることを確認 |
| TOP-14 | 性能（CRT 復号） | 性能 | 復号 1 回の所要サイクル | 設計想定（~28.5M サイクル）±10% | サイクルカウントを計測し、25,650,000〜31,350,000 の範囲内であることを確認 |
| TOP-15 | リセットからのコールドスタート | 機能 | rst_n 解除直後に通常シーケンス | 正常動作 | Python参照と DUT 出力を bit-exact比較 |
| TOP-16 | OpenSSL 互換性 | 正常系 | OpenSSL 生成の暗号文を復号 | 平文が一致 | OpenSSL で復号した平文と DUT 出力を bit-exact比較 |

**合否判定:** TOP-01〜TOP-06, TOP-16 は最終結果の bit-exact 一致。
TOP-13, TOP-14 はサイクル数範囲判定。その他は波形／プロトコル確認。

---

## 6. 検証項目トレーサビリティ

### 6.1 要求仕様 → 検証項目

| 要求仕様 | 検証項目 ID |
|---|---|
| 暗号化（$m^e \mod n$） | TOP-01, ME-01, ME-02, ME-03 |
| 復号（CRT） | TOP-03, CRT-01 |
| 署名（CRT） | TOP-04, CRT-02 |
| 検証（$s^e \mod n$） | TOP-02 |
| 公開鍵演算（2048bit, 任意指数） | ME-01〜ME-03, MM-01, MM-02 |
| 秘密鍵演算（CRT パラメータ） | CRT-01〜CRT-12, TOP-03, TOP-04 |
| 32bit シリアル I/O | IO-01〜IO-14, TOP-09 |
| Valid/Ready ハンドシェイク | IO-09, IO-10, TOP-12 |
| アクティブLow非同期リセット | C-03, 各モジュールのリセット検証項目 |
| 100MHz 動作（性能目標） | TOP-13, TOP-14（サイクル数で代替確認。タイミングクロージャは合成時に別途確認） |

### 6.2 設計仕様モジュール → 検証項目

| モジュール | 検証項目 |
|---|---|
| rsa_top | TOP-01〜TOP-16 |
| io_controller | IO-01〜IO-14 |
| mod_exp | ME-01〜ME-16 |
| mont_mul | MM-01〜MM-16 |
| mul_add_unit | MAU-01〜MAU-10 |
| crt_controller | CRT-01〜CRT-12 |
| operand_mem | MEM-01〜MEM-08 |

### 6.3 設計判断 → 検証項目

| 設計判断（design_spec §8） | 検証項目 |
|---|---|
| FIOS アルゴリズム | MM-01〜MM-16 |
| Left-to-right binary 累乗 | ME-12 |
| DSP48E1 の 4 部分積分割 | MAU-01〜MAU-07 |
| デュアルポート BRAM | MEM-04, MEM-05 |
| CRT を mont_mul で再利用 | CRT-07 |
| half_mode 切替 | MM-03, MM-04, MM-11 |
| 最終条件付き減算 | MM-08, MM-09 |
| addr_i パラメータ ID 方式 | IO-04, IO-05 |

---

## 7. カバレッジ目標

### 7.1 機能カバレッジ

- 全検証項目 ID の実行・合格（100%）
- Montgomery 形式変換（ToMont / FromMont）両方向の実行
- CRT 演算の全フェーズ（ExpP, ExpQ, SubM, MulQinv×2, MulHQ, AddM2）を少なくとも 1 回実行すること
  （各フェーズへの到達は crt_controller の FSM 状態に対応し、§7.2 のステートカバレッジとしても計測される）
- param_addr_e の 16 値全てについて少なくとも 1 回ロードが発生

### 7.2 コードカバレッジ（Step 5 で計測）

Verilator の `--coverage` を使用し、Step 5（テストベンチ実装 & シミュレーション）で計測・確認する。
以下の目標値を満たすことを Step 5 の完了条件の一つとする。

| 種別 | 目標値 | 根拠 |
|---|---|---|
| ラインカバレッジ | 95% 以上 | RTL 検証のベストプラクティス（UVM/OVM ガイドライン）に基づく一般的な目標値。デッドコードがほぼ存在しないことを示す現実的な閾値として採用 |
| ブランチカバレッジ | 90% 以上 | 全条件分岐の網羅は現実的に困難なため、主要パスを網羅できる 90% を目標とする |
| FSM 状態カバレッジ | 100% | 未到達状態はデッドロック・ハングの原因となるリスクが高いため、全状態の到達を必須とする |
| FSM 遷移カバレッジ | 90% 以上 | 全遷移の網羅は入力の組み合わせ爆発により困難なため、主要遷移を網羅できる 90% を目標とする |

**計測コマンド（Step 5 で実行）:**
```bash
verilator --binary --coverage -j 0 -Wall tb/tb_<module>.sv rtl/<deps>.sv
./obj_dir/Vtb_<module>
verilator_coverage --annotate coverage_annotated/ coverage.dat
```

### 7.3 コーナーケース網羅

- 全モジュールで「0 入力」「最大値入力」「n-1 入力」の境界値を最低 1 ケース
- `mont_mul` の最終条件付き減算（FIOS の `if t >= n: t -= n`）は「減算実行（t ≥ n）」「減算スキップ（t < n）」の両パスを検証（MM-08, MM-09）
- `crt_controller` の `m1 - m2` は「正」「負」両方を検証（CRT-03, CRT-04）

---

## 8. 既知バグ管理・回帰方針

### 8.1 バグ登録

シミュレーションで不一致が発見された場合、以下のフローで管理する。

1. GitHub Issue を登録（再現手順・期待値・実測値・関連モジュール）
2. `fix/issue-NNN` ブランチで修正
3. 修正コミットで該当テストベンチを追加または強化
4. PR マージ時に回帰テストが通過していることを確認

### 8.2 回帰テスト

- develop ブランチへの PR 前に `tb_rsa_top.sv` の TOP-01〜TOP-06 を必須実行
- feature ブランチ単位では該当モジュール単体テストを必須実行
- 将来的に GitHub Actions で Verilator 回帰を自動化（本フェーズではスコープ外）

---

## 9. 制約事項

- 本検証はシミュレーション（Icarus Verilog / Verilator）によるものであり、
  合成後の STA（タイミング解析）や実機 FPGA 検証は本スコープ外
- サイドチャネル攻撃耐性（タイミング攻撃、電力解析）の検証は行わない
- パディング検証（PKCS#1 v1.5, OAEP）は本 IP のスコープ外のため検証しない
- AXI-Lite ラッパー経由の検証は本 IP のスコープ外

---

## 10. 参考

- NIST FIPS 186-4: Digital Signature Standard
- NIST SP 800-56B Rev.2: Recommendation for Pair-Wise Key-Establishment Using Integer Factorization Cryptography
- PKCS#1 v2.2: RSA Cryptography Standard
- lowRISC Verilog Coding Style Guide
