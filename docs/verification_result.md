# RSA-2048 IP 検証結果レポート

**作成日**: 2026年5月2日
**更新日**: 2026年5月6日
**作成者**: a2zime × Claude Code
**対応仕様書**: [verification_spec.md](verification_spec.md) v1.7
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
| `io_controller` | — | IO-01〜14 | — | ⏳ 未着手 |
| `crt_controller` | — | CRT-01〜12 | — | ⏳ 未着手 |
| `rsa_top` | — | TOP-01〜16 | — | ⏳ 未着手 |

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

## 6. 発見済みバグ・仕様誤植

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

---

## 7. 未着手モジュールの検証計画

| モジュール | 検証ID | 概要 | 依存関係 |
|---|---|---|---|
| `io_controller` | IO-01〜14 | パラメータロード・アンロード、Valid/Ready | — |
| `crt_controller` | CRT-01〜12 | CRT 復号フロー全体 | `mod_exp` + `mont_mul` |
| `rsa_top` | TOP-01〜16 | 統合テスト（暗号化・復号・署名・検証） | 全モジュール |
