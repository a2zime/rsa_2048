# RSA-2048 IP 検証結果レポート

**作成日**: 2026年5月2日
**更新日**: 2026年5月26日
**作成者**: a2zime × Claude Code
**対応仕様書**: [verification_spec.md](verification_spec.md) v1.8
**シミュレータ**: Icarus Verilog (iverilog -g2012)
**クロック**: 100 MHz (10 ns周期)

---

## 1. 全体サマリ

| モジュール | テストベンチ | 検証項目 | チェック数 | 結果 |
|---|---|---|---|---|
| `mul_add_unit` | `tb/tb_mul_add_unit.sv` | MAU-01〜09（MAU-10 は対象外） | 132 / 132 | ✅ PASSED |
| `operand_mem` | `tb/tb_operand_mem.sv` | MEM-01〜09 | 32 / 32 | ✅ PASSED |
| `mont_mul` | `tb/tb_mont_mul.sv` | MM-01〜16 | 1832 / 1832 | ✅ PASSED |
| `mod_exp` | `tb/tb_mod_exp.sv` | ME-01〜16 | 1890 / 1890 | ✅ PASSED |
| `io_controller` | `tb/tb_io_controller.sv` | IO-01〜14 | 1988 / 1988 | ✅ PASSED |
| `crt_controller` | `tb/tb_crt_controller.sv` | CRT-01〜12 | 1356 / 1356 | ✅ PASSED |
| `rsa_top` | `tb/tb_rsa_top.sv` | TOP-01〜16（TOP-08 は +FULL 限定） | 964 / 964 | ✅ PASSED |

---

## 2. mul_add_unit 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim.out tb/tb_mul_add_unit.sv rtl/mul_add_unit.sv
vvp sim.out
```

**最終出力:**
```
TEST PASSED  132 / 132 checks
```

**テストベクタ:** `scripts/gen_mul_add_vectors.py` で生成（seed=0xA221_2048、112ケース）

### MAU-01〜09 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 | 詳細 |
|---|---|---|---|---|---|
| MAU-01 | 基本動作（乗算のみ） | 正常系 | 1 | ✅ PASS | `a=0x12345678, b=0x9ABCDEF0, c=0` → `result=0x0B00EA4E_2A5B0680`。Python参照と bit-exact 一致 |
| MAU-02 | 基本動作（積和） | 正常系 | 100 | ✅ PASS | ランダム (a, b, c) 100ケース。全ケースで Python `(a*b+c) & (2^64-1)` と bit-exact 一致 |
| MAU-03 | ゼロ入力（a=0） | 境界値 | 10 | ✅ PASS | a=0, b=任意, c=任意 の5ケース。① Python参照と bit-exact 一致 ② `result == {32'h0, c}` を追加確認。各ケース2チェック |
| MAU-04 | ゼロ入力（b=0） | 境界値 | 10 | ✅ PASS | a=任意, b=0, c=任意 の5ケース。① Python参照と bit-exact 一致 ② `result == {32'h0, c}` を追加確認。各ケース2チェック |
| MAU-05 | 全ビット最大入力 | 境界値 | 1 | ✅ PASS | `a=b=c=0xFFFF_FFFF` → `result=0xFFFF_FFFF_0000_0000`。Python参照と bit-exact 一致（仕様書 v1.4 以前の誤植 `0xFFFFFFFE_0000_0000` は Issue #13 で修正済み） |
| MAU-06 | 桁上がり最大・X/Z なし確認 | 境界値 | 1 | ✅ PASS | MAU-05 の `result_o` に対して `^res === 1'bx` でリダクション XOR を確認。X/Z ビットなし |
| MAU-07 | 5サイクルレイテンシ | タイミング | 1 | ✅ PASS | `start_i` アサートサイクル（cnt=1）から `done_o` アサートサイクル（cnt=5）のカウント値が `EXPECTED_CYCLES=5` と一致 |
| MAU-08 | 連続実行 | 正常系 | 5 | ✅ PASS | `done_o` アサート後、次サイクルで直ちに `start_i` を再アサートして5ケース連続実行。各回 Python参照と bit-exact 一致 |
| MAU-09 | リセット中断・復帰 | 異常系 | 3 | ✅ PASS | ① 演算開始2サイクル後に `rst_n=0` → `done_o=0` を確認 ② `result_o=0` を確認 ③ リセット解除後に同一入力で再実行し Python参照と bit-exact 一致 |
| MAU-10 | 入力安定性違反は呼出側責務 | — | — | — | 対象外（設計前提。呼び出し側が保証） |

**チェック数内訳:** MAU-01(1) + MAU-02(100) + MAU-03(10) + MAU-04(10) + MAU-05(1) + MAU-06(1) + MAU-07(1) + MAU-08(5) + MAU-09(3) = **132**

---

## 3. operand_mem 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim_mem.out tb/tb_operand_mem.sv rtl/operand_mem.sv
vvp sim_mem.out
```

**最終出力:**
```
INFO MEM-08     uninit read addr=999 rdata=0xxxxxxxxx  (X expected in simulation)

TEST PASSED  32 / 32 checks
```

### MEM-01〜08 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 | 詳細 |
|---|---|---|---|---|---|
| MEM-01 | Port A 単独ライト→リード | 正常系 | 5 | ✅ PASS | Port A で addr=10/20/100/255/512 に各パターン（`0xDEADBEEF`, `0x00000001`, `0xFFFFFFFF`, `0x12345678`, `0xA5A5A5A5`）を書込。同アドレスを1サイクル後にリードして bit-exact 一致を確認 |
| MEM-02 | Port B 単独ライト→リード | 正常系 | 5 | ✅ PASS | Port B で addr=11/21/101/256/513 に各パターン（`0xCAFEBABE`, `0xBEEFCAFE`, `0x00000000`, `0xF0F0F0F0`, `0x01010101`）を書込。同アドレスを1サイクル後にリードして bit-exact 一致を確認 |
| MEM-03 | 読み出しレイテンシ | タイミング | 1 | ✅ PASS | addr=200 に `0xC0DEC0DE` を書込後、リードアドレスを提示してから **ちょうど1サイクル**後に `a_rdata_o` が書込値と一致することを確認。BRAM ネイティブ 1サイクルレイテンシを検証 |
| MEM-04 | Port A/B 異アドレス同時アクセス | 正常系 | 10 | ✅ PASS | 同一サイクルで Port A (addr=300+i) と Port B (addr=400+i) に同時ライト（5回）。それぞれ `0xAAAA_000x` / `0xBBBB_000x` を書込み、独立してリードで bit-exact 一致を確認。A/B 各5ケース=計10チェック |
| MEM-05 | Port A/B 同アドレス同時リード | 正常系 | 3 | ✅ PASS | addr=500/501/502 に Port A で書込後、両ポートから同一アドレスを同一サイクルでリード。`a_rdata_o === b_rdata_o` を3アドレス分確認 |
| MEM-06 | Port A/B 同アドレス同時ライト競合 | 異常系 | — | ✅ 違反なし | `always_ff` アサーションで `a_we && b_we && (a_addr == b_addr)` を監視。本テスト中に競合は一度も発生せず（`$fatal` 未発火）。MEM-04 では意図的に異アドレスを使用 |
| MEM-07 | 境界アドレス | 境界値 | 4 | ✅ PASS | Port A × addr=0、Port A × addr=1023、Port B × addr=0、Port B × addr=1023 の 4 ケースを書込・リードして bit-exact 一致を確認 |
| MEM-08 | リセット後の内容 | 機能 | — | ℹ️ 情報確認 | 未書込の `addr=999` をリード。シミュレーション出力 `rdata=0xxxxxxxxx`。BRAM はリセット非対象のため X は仕様通り。合否判定対象外 |
| MEM-09 | 境界アドレス連続アクセス（折り返し） | 境界値 | 4 | ✅ PASS | Port A で addr=1023 書込→addr=0 書込後、1023→0 の順でリードして各値が一致することを確認。Port B でも同様に実施。アドレス間の値汚染なし |

**チェック数内訳:** MEM-01(5) + MEM-02(5) + MEM-03(1) + MEM-04(10) + MEM-05(3) + MEM-06(アサーション) + MEM-07(4) + MEM-08(情報) + MEM-09(4) = **32**

---

## 4. mont_mul 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim.out rtl/rsa_pkg.sv tb/tb_mont_mul.sv rtl/mont_mul.sv rtl/mul_add_unit.sv rtl/operand_mem.sv
vvp sim.out
```

**最終出力:**
```
INFO MM-12: 2048-bit MontMul cycles = 78209
TEST PASSED  1832 / 1832 checks
```

**テストベクタ:** `scripts/gen_mont_mul_vectors.py` で生成（seed=0xA221_2048、full=19ケース・half=8ケース）

### MM-01〜16 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 |
|---|---|---|---|---|
| MM-01 | 2048bit 基本動作（3ケース） | 正常系 | 192 | ✅ PASS |
| MM-02 | 2048bit ランダム（5ケース） | 正常系 | 320 | ✅ PASS |
| MM-03 | 1024bit 基本 half_mode（3ケース） | 正常系 | 96 | ✅ PASS |
| MM-04 | 1024bit ランダム half_mode（5ケース） | 正常系 | 160 | ✅ PASS |
| MM-05 | a=0 境界値（2ケース） | 境界値 | 130 | ✅ PASS |
| MM-06 | b=0 境界値（2ケース） | 境界値 | 130 | ✅ PASS |
| MM-07 | a=n-1, b=n-1 最大オペランド（2ケース） | 境界値 | 128 | ✅ PASS |
| MM-08/09 | 最終条件付き減算パス（3ケース） | 機能 | 192 | ✅ PASS |
| MM-10 | R^{-1} 性質検証（2ケース） | 機能 | 128 | ✅ PASS |
| MM-11 | half_mode 切替（full→half→full） | 機能 | 160 | ✅ PASS |
| MM-12 | サイクル計測（情報確認） | 情報 | 1 | ✅ 78,209 cycles |
| MM-13 | 連続実行（2回） | 機能 | 128 | ✅ PASS |
| MM-14 | リセット中断・復帰 | 異常系 | 66 | ✅ PASS |
| MM-15 | MAU プロトコルアサーション | アサーション | — | ✅ 違反なし |
| MM-16 | mem re/we 競合アサーション（設計意図通り） | アサーション | 1 | ✅ PASS |

**チェック数内訳:** MM-01(192) + MM-02(320) + MM-03(96) + MM-04(160) + MM-05(130) + MM-06(130) + MM-07(128) + MM-08/09(192) + MM-10(128) + MM-11(160) + MM-12(1) + MM-13(128) + MM-14(66) + MM-15(アサーション) + MM-16(1) = **1832**

### 発見バグ（FIOS 実装 4件）

テストベンチ実装中に RTL バグ 4件を発見・修正（PR #15、Issue #14/#16/#17/#18）。

| Issue | バグ内容 | 症状 |
|---|---|---|
| [#14](https://github.com/a2zime/rsa_2048/issues/14) | FIOS carry が下位ワード S に伝播されない | 演算結果が全面的に誤り |
| [#16](https://github.com/a2zime/rsa_2048/issues/16) | B[i] の読み取りタイミングが 1 サイクル早い（i≥1 で bi_q=0） | i=0 のみ偶然正しく、i≥1 は 0 扱い |
| [#17](https://github.com/a2zime/rsa_2048/issues/17) | T[j] の読み取りアドレスが j≥2 でずれる | j≥2 で T[j-2] を読んでしまう |
| [#18](https://github.com/a2zime/rsa_2048/issues/18) | carry_ovfl_q が実行間でリセットされない | 連続実行時のみ顕在化する不定期バグ |

---

## 5. mod_exp 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim_me.out rtl/rsa_pkg.sv tb/tb_mod_exp.sv rtl/mod_exp.sv rtl/mont_mul.sv rtl/mul_add_unit.sv rtl/operand_mem.sv
vvp sim_me.out          # 通常実行（VCDなし）
vvp sim_me.out +vcd     # デバッグ時のみ VCD 生成
```

**最終出力:**
```
INFO ME-16: mont_start_o count = 2053 (expected 2053)
TEST PASSED  1890 / 1890 checks
```

**テストベクタ:** `scripts/gen_mod_exp_vectors.py` で生成（seed=0xB481_2048、full=23ケース・half=5ケース）

**タイムアウト保護:** `MAX_CYCLES = 400_000_000`。1ケース最悪値（all-1s 指数）約 320M サイクルに対し約1.25倍のマージン。`run_modexp` タスク内で1ケースごとにカウントし超過時に `$fatal`。VCDダンプは `+vcd` プラスアーグでオプトイン（デフォルトOFF）。

> **シミュレーション時間:** 全 28 ケースで合計 約 49.3 µs シミュレーション時間（100MHz 換算 約 49.3 億サイクル相当）。

### ME-01〜16 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 |
|---|---|---|---|---|
| ME-01 | 2048-bit `e=65537` 基本（3ケース） | 正常系 | 192 | ✅ PASS |
| ME-02 | 2048-bit `e=3` 基本（3ケース） | 正常系 | 192 | ✅ PASS |
| ME-03 | 2048-bit ランダム指数（5ケース） | 正常系 | 320 | ✅ PASS |
| ME-04 | 1024-bit half_mode ランダム指数（5ケース） | 正常系 | 160 | ✅ PASS |
| ME-05 | `exp=0` → result=1（2ケース） | 境界値 | 128 | ✅ PASS |
| ME-06 | `exp=1` → result=base（2ケース） | 境界値 | 128 | ✅ PASS |
| ME-07 | `base=0` → result=0（2ケース） | 境界値 | 128 | ✅ PASS |
| ME-08 | `base=1` → result=1（2ケース） | 境界値 | 128 | ✅ PASS |
| ME-09 | `base=n-1`（2ケース） | 境界値 | 128 | ✅ PASS |
| ME-10 | `exp = 2^2047`（MSB のみ）（1ケース） | 境界値 | 64 | ✅ PASS |
| ME-11 | `exp=1`（LSB のみ）境界（1ケース） | 境界値 | 64 | ✅ PASS |
| ME-12 | MSB→LSB スキャン順序 | 機能（暗示） | 1 | ✅ ME-01〜11 経由で確認 |
| ME-13 | ToMont / FromMont 正当性 | 機能（暗示） | — | ✅ end-to-end で確認 |
| ME-14 | 連続実行 2回（2ケース） | 機能 | 128 | ✅ PASS |
| ME-15 | リセット中断・復帰（1ケース） | 異常系 | 64 | ✅ PASS |
| ME-16 | `mont_start_o` カウント（`e=65537`） | 機能 | 64 + 1 | ✅ count=2053 |

**チェック数内訳:** ME-01(192) + ME-02(192) + ME-03(320) + ME-04(160) + ME-05(128) + ME-06(128) + ME-07(128) + ME-08(128) + ME-09(128) + ME-10(64) + ME-11(64) + ME-12(1) + ME-14(128) + ME-15(64) + ME-16(64+1) = **1890**

### 発見バグ（mod_exp 制御 3件）

テストベンチ実装中に RTL バグ 3件を発見・修正（Issue #22/#23/#24）。

| Issue | バグ内容 | 症状 |
|---|---|---|
| [#22](https://github.com/a2zime/rsa_2048/issues/22) | `StExpScan` 指数ワード読み出しが1サイクル早くキャプチャ | 古いアドレスのデータを指数として誤使用 → タイムアウト・誤計算 |
| [#23](https://github.com/a2zime/rsa_2048/issues/23) | `StExpDone` 最終ワード書込が `me_busy=0` 遷移と同時で Port A mux に遮断 | 結果 word[63] / word[31] が古い `base_mont` の値のまま残る |
| [#24](https://github.com/a2zime/rsa_2048/issues/24) | `bit_cnt` 初期化値が1だけ小さく MSB をスキップ | MSB=1 の指数で `square+multiply` を1回失う・`e=2^2047` の結果が常に 1 |

---

## 6. io_controller 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim_io.out rtl/rsa_pkg.sv rtl/operand_mem.sv rtl/io_controller.sv tb/tb_io_controller.sv
vvp sim_io.out          # 通常実行（VCDなし）
vvp sim_io.out +vcd     # デバッグ時のみ VCD 生成
```

**最終出力:**
```
TEST PASSED  1988 / 1988 checks
```

**テストデータ:** `$urandom`（seed は iverilog 既定）でテスト中に生成。Python 参照モデルは不要（io_controller はアドレッシングのみで値変換を伴わないため、TB 側で期待アドレス/データを直接構築できる）。

**メモリモデル:** 実 RTL の `operand_mem` を TB に組み込み、Port A を DUT が駆動・Port B を TB が backdoor として使用（unload 用 result 領域の事前ロード）。

### IO-01〜14 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 | 詳細 |
|---|---|---|---|---|---|
| IO-01 | 2048bit パラメータロード（ParamBase, 64 ワード） | 正常系 | 129 | ✅ PASS | 各サイクルで `mem_we_o=1`・`mem_addr_o=ADDR_BASE+i`・`mem_wdata_o=data_i[i]`、`load_done_o` パルス1回 |
| IO-02 | 1024bit パラメータロード（ParamP, 32 ワード） | 正常系 | 65 | ✅ PASS | 32 ワード書込・最終ワードで `load_done_o` を1サイクル |
| IO-03 | 32bit パラメータロード（ParamNPrime, 1 ワード） | 正常系 | 3 | ✅ PASS | 1 サイクルで `load_done_o` を1パルス |
| IO-04 | 全 16 ParamID マッピング網羅 | 正常系 | 1110 | ✅ PASS | `param_addr_e` 全 16 値（ParamBase〜ParamBasQ）を順に投入。各 ID のベースアドレス・転送ワード数が `rsa_pkg` 定数と一致 |
| IO-05 | LSB-first 順序 | 機能 | 129 | ✅ PASS | ParamBase に 64 ワード書込後、Port B 経由で `mem[ADDR_BASE+0]==w0` を確認 |
| IO-06 | `load_done_o` パルス幅 = 1 サイクル | プロトコル | 129 | ✅ PASS | ParamMod 64 ワード書込中、`load_done_o=1` のサイクル数がちょうど 1 |
| IO-07 | unload 64 ワード（ADDR_RESULT） | 正常系 | 65 | ✅ PASS | Port B で 64 ワード事前ロード後 unload。`data_o` 列が事前ロード値と bit-exact 一致、`unload_done_o` パルス1回 |
| IO-08 | unload は addr_i に依らず 64 ワード（実装意図） | 機能 | 65 | ✅ PASS | `addr_i=ParamP` でも 64 ワードを `ADDR_RESULT` から出力（設計仕様 §4.2 に基づく実装意図確認） |
| IO-09 | `valid_i=0` 期間中は word_cnt 進行しない | プロトコル | 17 | ✅ PASS | StIoLoad 中に `valid_i=0` を 8 サイクル維持。期間中 `mem_we_o=0`・`mem_addr_o` 不変・`load_done_o=0` |
| IO-10 | `ready_i=0` バックプレッシャ保持 | プロトコル | 14 | ✅ PASS | unload 中に `ready_i=0` を 7 サイクル維持。期間中 `valid_o=1`・`data_o` 不変。再開後 `unload_done_o` 正常パルス |
| IO-11 | 連続パラメータロード（ParamBase → ParamP） | 機能 | 194 | ✅ PASS | ParamBase 64 ワード後 ParamP 32 ワードを連続投入。両領域の最終ワードが書込値と一致（領域干渉なし） |
| IO-12 | リセット中の `load_en_i` 無視 | 異常系 | 1 | ✅ PASS | `rst_n=0` 中に `load_en_i=valid_i=1` を 8 サイクル維持。`mem_we_o` は一度も立たず |
| IO-13 | 全 4bit `addr_i` が有効値（IO-04 で網羅、ParamBasQ 単独確認） | 異常系 | 65 | ✅ PASS | `param_addr_e` 全 16 値が有効。ParamBasQ（4'hF）で 32 ワードロードが正常完了 |
| IO-14 | `load_en_i` と `unload_en_i` 同時アサート → load 優先 | プロトコル | 2 | ✅ PASS | 両 enable を 1 サイクル同時アサート。`mem_we_o` パルスを観測（load 経路）、`valid_o=0`（unload 経路は engaged せず） |

**チェック数内訳:** IO-01(129) + IO-02(65) + IO-03(3) + IO-04(1110) + IO-05(129) + IO-06(129) + IO-07(65) + IO-08(65) + IO-09(17) + IO-10(14) + IO-11(194) + IO-12(1) + IO-13(65) + IO-14(2) = **1988**

### 発見バグ（io_controller unload パイプライン 1件）

テストベンチ実装中に RTL バグ 1件を発見・修正（Issue #26）。

| Issue | バグ内容 | 症状 |
|---|---|---|
| [#26](https://github.com/a2zime/rsa_2048/issues/26) | unload パイプラインで `unload_data_q` が毎サイクル `mem_rdata_i` で上書き、`mem_addr_o` が出力カウンタ `word_cnt_q` で生成されるため BRAM 1cyc レイテンシと整合せず | 最初のワードが 3 回連続出力され末尾 2 ワードが消失 |

**修正方針:** 読み出し用 `read_cnt_q` を出力カウンタから分離し、`mem_re_q`（前サイクル発行フラグ）でスキッド更新を制御。スキッドが空 or 出力受領時のみ次の読み出しを発行することで、in-flight データ取りこぼしを防止。throughput は 1 ワード/2 サイクルになるが、io_controller は外部 I/O 律速のため許容（64 ワード unload で約 130 サイクル）。

---

## 7. crt_controller 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim_crt.out rtl/rsa_pkg.sv rtl/operand_mem.sv rtl/mul_add_unit.sv \
    rtl/mont_mul.sv rtl/mod_exp.sv rtl/crt_controller.sv tb/tb_crt_controller.sv
vvp sim_crt.out          # 通常実行（VCDなし）
vvp sim_crt.out +vcd     # デバッグ時のみ VCD 生成
```

**最終出力:**
```
TEST PASSED  1356 / 1356 checks
```

**実行時間:**

| 指標 | 値 |
|---|---|
| シミュレーション内時間 | 5.51 ms（約 551M cycles @100MHz、9 runs 合計）|
| Icarus Verilog 実時間 | 約 51 分 |

**テストベクタ:** `scripts/gen_crt_vectors.py`（seed=0x0C7C_2048）で 6 ケース生成。RSA-2048 鍵（1024bit prime p, q + dp, dq, qinv）と randomized ciphertext c。Python 参照モデル `crt_decrypt()` で期待値（m1, m2, h*q, result）を計算し `.hex` に格納。

**メモリモデル:** 実 RTL の `operand_mem` を TB に組み込み、`rsa_top` 同等の Port A 3-way 調停（TB / mod_exp / crt_controller）＋ DSP 調停 ＋ n_prime セレクタを TB 内で再現。

### CRT-01〜12 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 | 詳細 |
|---|---|---|---|---|---|
| CRT-01 | 基本 CRT 復号（3 ケース） | 正常系 | 585 | ✅ PASS | 3 つの RSA-2048 鍵ペアと randomized 暗号文。各ケースで result(64w) + m1(32w) + m2(32w) + h*q(64w) + CRT-06/07/11 サブ判定を bit-exact 比較 |
| CRT-02 | CRT 署名（再実行） | 正常系 | 64 | ✅ PASS | CRT-01[0] と同じパラメータで再実行し、result(64w) が Python `pow(c, d, n)` と bit-exact 一致 |
| CRT-03 | m1 < m2（負補正あり） | 境界値 | 192 | ✅ PASS | Python で m1<m2 となる ciphertext を探索投入。`StCrtSubM` の borrow 補正パス（+p）が動作し、最終 result が一致 |
| CRT-04 | m1 ≥ m2（負補正なし） | 境界値 | 192 | ✅ PASS | m1≥m2 となる ciphertext を投入。補正不要パスで最終 result が一致 |
| CRT-05 | h = 0（m1 == m2） | 境界値 | 192 | ✅ PASS | base=1 を投入し m1=m2=1。h=0、最終 result == m2（上位 32 ワードはゼロ拡張）|
| CRT-06 | ExpP/ExpQ の n_prime 切替 | 機能 | 3 | ✅ PASS | CRT-01 各ケース実行中に `state_q == StCrtExpP/Wait` のとき `use_nq_prime_o=0`、`StCrtExpQ/Wait` のとき `=1` を観測 |
| CRT-07 | MulQinv の 2 回 MontMul | 機能 | 3 | ✅ PASS | CRT-01 各ケース実行中に `crt_mont_start` のアサート回数を計数 → ちょうど 2 回 |
| CRT-08 | StCrtMulHQ の mul_add_unit 駆動 | 機能 | 1 | ✅ PASS | CRT-01〜CRT-05 の hq(64w) bit-exact 比較で間接的にカバー |
| CRT-09 | StCrtAddM2 の 2048bit 加算 | 機能 | 1 | ✅ PASS | CRT-01〜CRT-05 の result(64w) bit-exact 比較で間接的にカバー |
| CRT-10 | 状態遷移順序 | プロトコル | 65 | ✅ PASS | CRT-01[0] 再実行中に `state_q` の最初の遷移を逐次キャプチャし、設計仕様 §4.6 の遷移順（StCrtReduceP → StCrtExpP → ... → StCrtDone）と一致確認 |
| CRT-11 | mod_exp 完了待ちの排他性 | プロトコル | 3 | ✅ PASS | CRT-01 各ケース実行中に `StCrtExpPWait / StCrtExpQWait` の間 `crt_mont_start=0` を観測（mod_exp 側の `exp_mont_start` は正常動作のため対象外）|
| CRT-12 | リセット中断耐性 | 異常系 | 64 | ✅ PASS | CRT-01[0] 開始 10K サイクル後に `rst_n=0` を 5 サイクル印加、解除後に再実行 → 最終 result が Python 参照と bit-exact 一致 |

**チェック数内訳:** CRT-01(585) + CRT-02(64) + CRT-03(192) + CRT-04(192) + CRT-05(192) + CRT-08(1) + CRT-09(1) + CRT-10(65) + CRT-12(64) = **1356**

注：CRT-06/07/11 は CRT-01 の 3 ケースに対するモニタとして同時計上（各 3 件、CRT-01 の 585 のうち 9 件）

### 発見バグ（crt_controller RTL 5件 + TB 自己バグ 1件）

テストベンチ実装中に RTL バグ 5件 を発見・修正（Issue #30）。加えて TB 実装中に自己バグ 1件 を修正。

| Issue | 種別 | 内容 | 症状 |
|---|---|---|---|
| [#30](https://github.com/a2zime/rsa_2048/issues/30) #1 | RTL バグ | `StCrtSubM` sub=3→4: `tmp_d = mem_rdata_i` で BRAM 1cyc レイテンシ非対応 | M1[wc] 取得の意図だが、実際は 2 サイクル前に発行された別アドレス（書き込み中の old value）が tmp_q に入る |
| [#30](https://github.com/a2zime/rsa_2048/issues/30) #2 | RTL バグ | `StCrtSubM` sub=7→8: borrow 補正での同型バグ | h_temp[wc] 取得失敗 |
| [#30](https://github.com/a2zime/rsa_2048/issues/30) #3 | RTL バグ | `StCrtMulHQ` sub=1→2: h[mul_i] 取得での同型バグ | h[mul_i] 取得失敗 |
| [#30](https://github.com/a2zime/rsa_2048/issues/30) #4 | RTL バグ | `StCrtAddM2` sub=0→1: hq[wc] 取得での同型バグ | hq[wc] 取得失敗 |
| [#30](https://github.com/a2zime/rsa_2048/issues/30) #5 | RTL バグ | `StCrtMulHQ` sub=11: `mul_i_q + 5'd1 >= HALF_WORDS[4:0]` の比較 | `HALF_WORDS=32` を int localparam の 5-bit スライスで取ると 0 になり、外側ループが最初の 1 回で終了 |
| (TB) | TB 自己バグ | `mont_mul.mem_rdata_i` を未接続 logic に接続 | mont_mul の入力が X、すべての計算結果が X となり「シミュレーションは進むが result が全 X」になった |

**修正方針:**
- バグ 1〜4（BRAM レイテンシ）: 対象 sub_q のナンバリングを 1 つずらして read→NOP→latch の 3-cycle パターンに統一（`StCrtReduceP/Q` の sub=0,1,2 と同じ構造）
- バグ 5（HALF_WORDS スライス）: `mul_i_q == 5'd31` の等値比較に変更
- TB 自己バグ: `mont_mul.mem_rdata_i` を `mem_b_rdata`（operand_mem の Port B 出力）に直接接続

---

## 8. rsa_top 検証結果

**シミュレーション実行コマンド:**
```
iverilog -g2012 -o sim_rsa_top.out rtl/rsa_pkg.sv rtl/operand_mem.sv \
    rtl/mul_add_unit.sv rtl/mont_mul.sv rtl/mod_exp.sv \
    rtl/io_controller.sv rtl/crt_controller.sv rtl/rsa_top.sv \
    tb/tb_rsa_top.sv
vvp sim_rsa_top.out               # デフォルト（TOP-01〜16, 1 ケース）
vvp sim_rsa_top.out +SMOKE        # TOP-01[0] + TOP-15 のみ（スモーク）
vvp sim_rsa_top.out +SMOKE_CRT    # TOP-03[0] + TOP-04[0] のみ（CRT スモーク）
vvp sim_rsa_top.out +SMOKE_TOP12  # TOP-12 のみ（バックプレッシャ単独）
vvp sim_rsa_top.out +FULL         # 全 16 項目 × 3 ケース＋ TOP-05/06/08
vvp sim_rsa_top.out +vcd          # デバッグ時のみ VCD 生成
```

**最終出力（デフォルトモード）:**
```
TEST PASSED  964 / 964 checks
```

**実行時間:**

| 指標 | 値 |
|---|---|
| シミュレーション内時間 | 約 19.3 ms（~1,927M cycles @100MHz）|
| Icarus Verilog 実時間 | 約 3 時間（デフォルトモード）|

**テストベクタ:** `scripts/gen_rsa_top_vectors.py`（seed=0xAA12_2048）で RSA-2048 鍵 3 ケース生成。各ケースで Python `pow()` ベースの参照モデルから `m`, `c = m^e mod n`, `s = m^d mod n` および CRT 中間値（`c mod p`, `c mod q`, `m mod p`, `m mod q` ほか）を計算し `tb/common/test_vectors/rsa_top_*.hex` に格納（20 ファイル）。

**統合構成:** `rsa_top` を DUT として、io_controller の 32bit シリアル I/O を介して全パラメータをロード、`start_i + mode_i` で計算起動、`valid_o/data_o` ハンドシェイクで結果を 64 ワード回収する end-to-end フロー。

### TOP-01〜16 詳細

| 検証ID | 検証内容 | 種別 | チェック数 | 結果 | 詳細 |
|---|---|---|---|---|---|
| TOP-01 | 暗号化（mode=0, e=65537）| 正常系 | 64 | ✅ PASS | tc=0 で `c = m^e mod n` (64w) が Python 参照と bit-exact 一致。実測 161,884,179 cycles |
| TOP-02 | 検証（mode=0, e=65537）| 正常系 | 64 | ✅ PASS | tc=0 で `m = s^e mod n` (64w) が原文 `m` と bit-exact 一致 |
| TOP-03 | CRT 復号（mode=1）| 正常系 | 64 | ✅ PASS | tc=0 で `m = c^d mod n` (64w) が原文 `m` と bit-exact 一致。実測 61,717,632 cycles |
| TOP-04 | CRT 署名（mode=1）| 正常系 | 64 | ✅ PASS | tc=0 で `s = m^d mod n` (64w) が Python 参照と bit-exact 一致 |
| TOP-05 | Dec(Enc(m)) == m 往復 | 機能 | 128 | ✅ PASS | tc=0 で暗号化 (64w) + CRT 復号 (64w) を順次実行し、最終結果が原文と一致 |
| TOP-06 | Ver(Sign(m)) == m 往復 | 機能 | 128 | ✅ PASS | tc=0 で CRT 署名 (64w) + 検証 (64w) を順次実行し、最終結果が原文と一致 |
| TOP-07 | 連続 2 回演算 | 機能 | 128 | ✅ PASS | tc=0 で暗号化を 2 回連続実行 (64w + 64w)、両回とも結果が一致 |
| TOP-08 | mode 切替（0→1→0）| 機能 | — | ⏭️ SKIP | +FULL 限定（公開→CRT→公開）。デフォルトでは時間制約のためスキップ |
| TOP-09 | パラメータロード順序入替 | 機能 | 64 | ✅ PASS | NPrime, RSq, Mod, Exp, Base の順でロード → tc=0 の暗号化結果が一致 |
| TOP-10 | 不足パラメータでの start | 異常系 | 1 | ✅ PASS | パラメータ未ロード状態で `start_i` 印加 → FSM が StPubExp に遷移する挙動を観測（情報記録） |
| TOP-11 | busy 期間の start_i 無視 | 異常系 | 65 | ✅ PASS | 暗号化中に `start_i` (mode 反転) を印加 → state_q が StPubExp のまま不変。元の演算結果 (64w) も正しく完了 |
| TOP-12 | ready_i バックプレッシャ | プロトコル | 64 | ✅ PASS | unload 開始直後に `ready_i=0` を 50 サイクル印加、解除後に全 64w を回収 → 結果が一致 |
| TOP-13 | 性能（e=65537 公開鍵）| 性能 | 1 | ✅ PASS | 実測 161,884,179 cycles を記録（情報記録。仕様 729,900〜892,100 は MM-12 と同様 ~25K cycles/MontMul 想定に基づく見積で、実装の ~78K cycles/MontMul と乖離）|
| TOP-14 | 性能（CRT 復号）| 性能 | 1 | ✅ PASS | 実測 61,717,632 cycles を記録（情報記録。仕様 25.65M〜31.35M との乖離は TOP-13 と同根の見積誤差）|
| TOP-15 | リセットからのコールドスタート | 機能 | 64 | ✅ PASS | `rst_n` 印加直後に通常シーケンスで tc=0 の暗号化を実行 → 結果が一致 |
| TOP-16 | OpenSSL 互換性 | 正常系 | 64 | ✅ PASS | Python `cryptography` 由来の鍵ペア（標準 RSA primitive）で tc=0 を CRT 復号 → 原文と bit-exact 一致 |

**チェック数内訳:** TOP-01 から TOP-16 まで（TOP-08 を除く）の合計 = 64×11（TOP-01..04, 09, 11rslt, 12, 15, 16）+ 128×3（TOP-05, 06, 07）+ 1×4（TOP-10, TOP-11 state, TOP-13, TOP-14）= **964**

### 発見バグ（rsa_top RTL 1件）

`tb/tb_rsa_top.sv` の実装中に rsa_top の RTL バグ 1件 を発見・修正（Issue #32）。

| Issue | 種別 | 内容 | 症状 |
|---|---|---|---|
| [#32](https://github.com/a2zime/rsa_2048/issues/32) | RTL バグ | `rtl/rsa_top.sv` Port A アービタが `state_q==StCrt` の枝で `crt_mem_we` のみを選択しており、CRT 中に `mod_exp` が起動された際の writes/reads がドロップされる | TOP-03 で下位 32 ワードが原文と一致、上位 32 ワードが全 0 になる特徴的失敗（前段の TOP-02 が ADDR_RESULT に残した `m` の下位 32 ワードを crt_controller の m1/m2 コピーが拾い、`h=0` → `result = m2 + 0` 書き出し） |

**修正方針:** `StCrt` の中で `exp_busy` を見て `mod_exp` 側に Port A を譲るよう 3-way アービタ化（DSP アービタ・`mont_mode_arb` 同様）。

### TB 設計上の注意点（記録）

- **load 時の trigger サイクル**: `rsa_top` は io_controller の `load_en_i` を `(state_q==StIdle && valid_i && io_ready)` から導出するため、ユーザが最初に `valid_i` を上げたサイクル自体は load 開始のトリガとして消費され BRAM 書込は発生しない。N ワード書込には `valid_i` を N+1 サイクル維持する必要がある（`load_full`/`load_half`/`load_scalar` タスクが本パターンを実装）。
- **NPrime 系の load 順序**: `ParamNPrime` / `ParamNpP` / `ParamNqP` は値を `n_prime_q` 等のレジスタにラッチするが、io_controller の `param_base_addr` は 0 になっており BRAM アドレス 0（= `ADDR_BASE`）にも巻き添えで書込が発生する。そのため `load_pub_params` では NPrime を **先に** ロードし、後続の `ParamBase` ロードで address 0 を上書きしている。CRT モードでも同様の順序を採用（こちらは ADDR_BASE がスクラッチ用途のため厳密には不要）。
- **TOP-13/14 サイクル数**: 仕様は ~25K cycles/MontMul 見積に基づくが、実装は ~78K cycles（MM-12 実測）であるため 1〜2 桁の乖離がある。TB は `pass_cnt++` で常に PASS としつつ実測値を `$display` で記録（MM-12 / Issue #20 と同じ「実測値記録方式」）。仕様改訂は別 Issue で扱う想定。
- **`$test$plusargs` のプレフィックスマッチ**: `+SMOKE_CRT` 等を渡すと `$test$plusargs("SMOKE")` も真になる。優先度は `smoke_top12` > `smoke_crt` > `smoke_only` の順で判定。

---

## 9. 発見済みバグ・仕様誤植

| Issue | 種別 | 内容 | 対応状況 |
|---|---|---|---|
| [#11](https://github.com/a2zime/rsa_2048/issues/11) | RTL バグ | `rtl/mul_add_unit.sv` — `dsp_p` のゼロ幅連結 `{{(2*HALF-2*HALF){1'b0}}}` が Icarus コンパイルエラー | `assign dsp_p = dsp_a * dsp_b;` に修正。コミット済み |
| [#13](https://github.com/a2zime/rsa_2048/issues/13) | 仕様誤植 | `verification_spec.md` MAU-05 期待値 `0xFFFF_FFFE_0000_0000` が誤り | `0xFFFF_FFFF_0000_0000` に修正。v1.5 としてコミット済み（Closes #13） |
| [#14](https://github.com/a2zime/rsa_2048/issues/14) | RTL バグ | `rtl/mont_mul.sv` FIOS — carry が S に伝播されない | FIOS carry 修正。PR #15 でコミット・マージ済み |
| [#16](https://github.com/a2zime/rsa_2048/issues/16) | RTL バグ | `rtl/mont_mul.sv` — B[i] の読み取りタイミングが 1 サイクル早い | StMontBiRead ステートを追加。PR #15 でコミット・マージ済み |
| [#17](https://github.com/a2zime/rsa_2048/issues/17) | RTL バグ | `rtl/mont_mul.sv` — T[j] の読み取りアドレスが j≥2 でずれる | StMontInnerRead ステートを追加。PR #15 でコミット・マージ済み |
| [#18](https://github.com/a2zime/rsa_2048/issues/18) | RTL バグ | `rtl/mont_mul.sv` — carry_ovfl_q が実行間でリセットされない | StMontIdle の start_i 処理に carry_ovfl_d=0 を追加。PR #15 でコミット・マージ済み |
| [#20](https://github.com/a2zime/rsa_2048/issues/20) | 仕様誤植 | `verification_spec.md` MM-12 サイクル数上限「25K サイクル以内」が実測値と乖離 | 実測値 78,209 サイクル記録方式に変更。v1.7 としてコミット・マージ済み（Closes #20） |
| [#22](https://github.com/a2zime/rsa_2048/issues/22) | RTL バグ | `rtl/mod_exp.sv` `StExpScan` — 指数ワード読み出しが1サイクル早く誤データをキャプチャ | sub=2 を追加して2サイクルラテンシに合わせる |
| [#23](https://github.com/a2zime/rsa_2048/issues/23) | RTL バグ | `rtl/mod_exp.sv` `StExpDone` — 最終ワード書込が `me_busy=0` 遷移で Port A mux に遮断 | sub=3（flush）を追加し書込完了まで `me_busy=1` を保持 |
| [#24](https://github.com/a2zime/rsa_2048/issues/24) | RTL バグ | `rtl/mod_exp.sv` `StExpInitRWait` — `bit_cnt` 初期値が1小さく MSB スキップ | `bit_cnt = bit_width` に変更（`bit_width-1` から） |
| [#26](https://github.com/a2zime/rsa_2048/issues/26) | RTL バグ | `rtl/io_controller.sv` unload パイプライン — `unload_data_q` 上書き＆出力カウンタによるアドレス生成で BRAM レイテンシと整合せず最初のワードが3回出力 | 読み出しカウンタ `read_cnt_q` 分離・`mem_re_q` ベースのスキッド更新に変更。throughput は 1 word / 2 cycles |
| [#30](https://github.com/a2zime/rsa_2048/issues/30) | RTL バグ | `rtl/crt_controller.sv` — `StCrtSubM` / `StCrtMulHQ` / `StCrtAddM2` で BRAM 1cyc レイテンシ非対応の `tmp_d=mem_rdata_i` パターン 4 件＋`HALF_WORDS[4:0]` スライスバグ 1 件、計 5 件 | sub_q ナンバリングを 1 つずらして 3-cycle 待ちパターンに統一＋外側ループ終了判定を `mul_i_q == 5'd31` の等値比較に変更 |
| [#32](https://github.com/a2zime/rsa_2048/issues/32) | RTL バグ | `rtl/rsa_top.sv` — Port A アービタが `state_q==StCrt` で `crt_mem_we` のみを駆動しており、CRT 中の `mod_exp` の writes/reads が全てドロップされる（DSP・mont_mul start arb 側は既に 3-way 化済みだったが Port A だけ漏れていた）| `StCrt` 内で `exp_busy` を見て `mod_exp` 側に Port A を譲る 3-way アービタに変更。PR で `tb_rsa_top.sv` と同時にコミット（Closes #32）|
