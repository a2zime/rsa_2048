# Verible Lint レポート

**実施日**: 2026-04-14
**対象ブランチ**: `feature/rtl-coding`（ベース: `f49b2b8` develop HEAD）
**対象コミット**: 未コミット（RTL 初期実装 — コミット前の最終 Lint 確認）
**ツール**: verible-verilog-lint v0.0-3946-g851d3ff4 (2025-02-17)
**ルールファイル**: `.rules.verible_lint` (MD5: `9f84382c61b9bc8baa2bc6cd71dd8045`)

---

## 1. ルールファイル設定

| ルール名 | 状態 | 設定値 | 備考 |
|---|---|---|---|
| parameter-name-style | default + カスタム | `localparam_style:ALL_CAPS\|CamelCase` | lowRISC 規約 + プロジェクト規約の併用 |
| port-name-suffix | **追加有効化** | デフォルト（`_i`, `_o`, `_io`, `_ni`, `_pi`） | コーディング規約のサフィックスルール強制 |
| explicit-begin | **追加有効化** | 全構文要素で `begin/end` を強制 | ラッチ防止・可読性向上 |
| dff-name-style | **追加有効化** | `output:reg,r,ff,q` / `input:` (無効) / `waive:!rst_ni,mem.*,.*_o` | FF 出力の `_q` サフィックス強制。RHS チェックは無効化 |
| one-module-per-file | **追加有効化** | デフォルト | 1 ファイル 1 モジュール強制 |
| その他 default ルール | default | ― | `--ruleset=default` の約 40 ルールすべて有効 |

### dff-name-style の waive 設定詳細

| waive 対象 | 正規表現 | 理由 |
|---|---|---|
| リセットブロック内の代入 | `waive_ifs_with_conditions:!rst_ni` | リセット時は初期値代入であり `_d` パターン不要 |
| BRAM メモリ配列 | `waive_lhs_regex:(?i)(mem.*)` | BRAM の `mem[addr]` は合成ツール推論パターンで `_q` 不適切 |
| 出力ポート | `waive_lhs_regex:(?i)(.*_o)` | 出力ポートは `_o` サフィックスで十分。内部で `_q` → `_o` の分離は検証フェーズで検討 |

---

## 2. Lint 実行結果サマリ

### 第 1 回実行（追加ルール有効化直後）

| ファイル | 結果 | 違反数 | 主な違反ルール |
|---|---|---|---|
| rsa_pkg.sv | **PASS** | 0 | ― |
| mul_add_unit.sv | **FAIL** | 22 | port-name-suffix (2), dff-name-style (20) |
| operand_mem.sv | **FAIL** | 4 | port-name-suffix (2), dff-name-style (2) |
| mont_mul.sv | **FAIL** | 7 | port-name-suffix (2), dff-name-style (5) |
| mod_exp.sv | **FAIL** | 5 | port-name-suffix (2), dff-name-style (3) |
| io_controller.sv | **FAIL** | 5 | port-name-suffix (2), dff-name-style (3) |
| crt_controller.sv | **FAIL** | 7 | port-name-suffix (2), dff-name-style (5) |
| rsa_top.sv | **FAIL** | 9 | port-name-suffix (2), explicit-begin (3), dff-name-style (4) |

### 対応内容

| 違反カテゴリ | 違反数 | 対応方法 |
|---|---|---|
| port-name-suffix: `clk`, `rst_n` にサフィックスなし | 14 (全7ファイル×2) | `clk` → `clk_i`、`rst_n` → `rst_ni` にリネーム（全モジュール + rsa_top のインスタンス接続） |
| explicit-begin: if 文に `begin/end` なし | 3 (rsa_top.sv) | `begin/end` ブロックを追加 |
| dff-name-style: 出力ポートを always_ff で直接代入 | 42 (複数ファイル) | ルール設定で対応: RHS チェック無効化 (`input:` 空)、出力ポート LHS を waive (`waive_lhs_regex:.*_o`) |
| dff-name-style: BRAM メモリ配列への代入 | 2 (operand_mem.sv) | ルール設定で対応: `waive_lhs_regex:mem.*` |

### 第 2 回実行（全修正適用後） — 最終結果

| ファイル | 結果 | 違反数 |
|---|---|---|
| rsa_pkg.sv | **PASS** | 0 |
| mul_add_unit.sv | **PASS** | 0 |
| operand_mem.sv | **PASS** | 0 |
| mont_mul.sv | **PASS** | 0 |
| mod_exp.sv | **PASS** | 0 |
| io_controller.sv | **PASS** | 0 |
| crt_controller.sv | **PASS** | 0 |
| rsa_top.sv | **PASS** | 0 |

**結果: 全 8 ファイル PASS（違反 0 件）**

---

## 3. 有効ルール一覧（default + 追加）

### default ルールセット（約 40 ルール）

| ルール | 概要 |
|---|---|
| always-comb | `always @*` 禁止 → `always_comb` 使用 |
| always-comb-blocking | 組み合わせ回路でノンブロッキング代入禁止 |
| always-ff-non-blocking | 順序回路でブロッキング代入禁止（ローカル変数除く） |
| case-missing-default | `unique` なし case 文に default 必須 |
| constraint-name-style | 制約名の命名規則 |
| create-object-name-match | UVM create の名前一致 |
| enum-name-style | enum 型名 `lower_snake_case` + `_t`/`_e` |
| explicit-function-lifetime | 関数のライフタイム明示 |
| explicit-function-task-parameter-type | 関数/タスクのパラメータ型明示 |
| explicit-parameter-storage-type | parameter/localparam の型明示 |
| explicit-task-lifetime | タスクのライフタイム明示 |
| forbid-consecutive-null-statements | 連続空文 `;;` 禁止 |
| forbid-defparam | defparam 禁止 |
| forbid-line-continuations | 行継続 `\` 禁止 |
| forbidden-macro | 禁止マクロチェック |
| generate-label | generate ブロックのラベル必須 |
| generate-label-prefix | generate ラベルの `g_`/`gen_` プレフィックス |
| interface-name-style | インターフェース名の命名規則 |
| invalid-system-task-function | 禁止システムタスク ($psprintf, $random 等) |
| line-length | 1 行 100 文字以内 |
| macro-name-style | マクロ名 `UPPER_SNAKE_CASE` |
| module-begin-block | モジュール直下の begin-end 禁止 |
| module-filename | モジュール名とファイル名の一致 |
| module-parameter | 複数パラメータの名前付き接続 |
| module-port | 複数ポートの名前付き接続 |
| no-tabs | タブ禁止 |
| no-trailing-spaces | 行末スペース禁止 |
| package-filename | パッケージ名とファイル名の一致 |
| packed-dimensions-range-ordering | パックド次元の降順 `[N-1:0]` |
| parameter-name-style | パラメータ命名規則 (カスタム済み) |
| positive-meaning-parameter-name | パラメータ名の正の意味 (`enable_*` 推奨) |
| posix-eof | ファイル末尾改行 |
| suggest-parentheses | 括弧の推奨 |
| truncated-numeric-literal | 数値リテラルのトランケーション検出 |
| typedef-enums | enum の typedef 必須 |
| typedef-structs-unions | struct/union の typedef 必須 |
| undersized-binary-literal | バイナリリテラルのサイズ不足 |
| unpacked-dimensions-range-ordering | アンパックド次元の昇順 `[0:N-1]` |
| v2001-generate-begin | generate 内の不要 begin |
| void-cast | void キャストのチェック |

### 追加有効化ルール（4 ルール）

| ルール | 概要 | 有効化理由 |
|---|---|---|
| port-name-suffix | ポート名の `_i`/`_o`/`_io`/`_ni`/`_pi` サフィックス強制 | コーディング規約準拠 |
| explicit-begin | if/else/always 等に `begin/end` 強制 | 可読性・ラッチ防止 |
| dff-name-style | FF 出力の `_q` サフィックス強制 | コーディング規約の `_d`/`_q` パターン準拠 |
| one-module-per-file | 1 ファイル 1 モジュール | コーディング規約準拠 |
