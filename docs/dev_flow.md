# RSA-2048 IP 開発フロー（プロジェクト固有）

共通開発フロー・コーディング規約は `common/` を参照。

---

## 1. ブランチ計画

```
main
  └── develop
        ├── feature/xxx   新機能・新モジュール（設計仕様確定後に決定）
        └── fix/issue-NNN バグ修正
```

---

## 3. 開発手順（工程別）

### Step 1: 要求仕様定義（docs/requirements.md）→ PR → レビュー → developマージ

**作業内容**
- 機能要件・非機能要件を定義
- インターフェース仕様（入出力ポート）を決める
- Claudeと対話しながら作成

**レビュー観点**
- [ ] RSA-2048の機能要件が網羅されているか（暗号化・復号・署名・検証）
- [ ] キー長・データ幅・動作周波数などの非機能要件が明記されているか
- [ ] 入出力ポートの定義が具体的で設計仕様に進めるレベルか
- [ ] 将来のFPGA実装の制約が考慮されているか

```bash
git checkout -b feature/requirements
git add docs/requirements.md
git commit -m "docs: 要求仕様定義"
git push origin feature/requirements
gh pr create --base develop --title "docs: 要求仕様定義"
```

---

### Step 2: 設計仕様作成（docs/design_spec.md）→ PR → レビュー → developマージ

**作業内容**
- アーキテクチャ決定（モンゴメリ乗算のアルゴリズム選定等）
- モジュール分割
- 状態機械の設計

**レビュー観点**
- [ ] 要求仕様の全項目が設計仕様に反映されているか
- [ ] モンゴメリ乗算のアルゴリズム選定に根拠があるか
- [ ] モジュール分割が適切か（責務が明確に分離されているか）
- [ ] 状態機械の状態遷移に漏れ・矛盾がないか
- [ ] コーディング規約に沿ったモジュール名・信号名になっているか

```bash
git checkout -b feature/design-spec
git add docs/design_spec.md
git commit -m "docs: 設計仕様作成"
git push origin feature/design-spec
gh pr create --base develop --title "docs: 設計仕様作成"
```

---

### Step 3: RTLコーディング → PR → レビュー → developマージ

**作業内容**
- featureブランチでモジュールごとに実装
- 実装後にVeribleでLintクリアを確認

**レビュー観点**
- [ ] 設計仕様との整合性（信号名・ポート定義・状態遷移）
- [ ] コーディング規約への準拠（`logic`使用・`always_ff`/`always_comb`・命名規則）
- [ ] lintクリア済み
- [ ] リセット時に全レジスタが初期化されているか
- [ ] `always_comb` 内でデフォルト代入があるか（ラッチ防止）
- [ ] コメントが適切か（モジュール冒頭のdescription等）

```bash
git checkout -b feature/<module-name>
verible-verilog-lint --ruleset=default rtl/<module>.sv
git add rtl/<module>.sv
git commit -m "feat: <モジュール名> 初期実装"
git push origin feature/<module-name>
gh pr create --base develop --title "feat: <モジュール名> 実装"
```

---

### Step 4: 検証仕様作成（docs/verification_spec.md）→ PR → レビュー → developマージ

**作業内容**
- 検証クライテリア定義
- 検証項目リスト
- テストベクタの方針

**レビュー観点**
- [ ] 設計仕様の全モジュール・全機能に対応する検証項目があるか
- [ ] 検証クライテリア（合否判定基準）が明確か
- [ ] 正常系・異常系・境界値のテストケースが含まれているか
- [ ] テストベクタの生成方法（手動・Python等）が明記されているか

```bash
git checkout -b feature/verification-spec
git add docs/verification_spec.md
git commit -m "docs: 検証仕様作成"
git push origin feature/verification-spec
gh pr create --base develop --title "docs: 検証仕様作成"
```

---

### Step 5: テストベンチ実装 & シミュレーション → PR → レビュー → developマージ

**作業内容**
- 検証仕様に基づきテストベンチを実装
- シミュレーション実行・波形確認
- 問題があればGit Issueに登録

**レビュー観点**
- [ ] 検証仕様の全検証項目がテストベンチに実装されているか
- [ ] シミュレーション結果が検証クライテリアを満たしているか
- [ ] 既知のバグはIssueに登録されているか

```bash
git checkout -b feature/tb-<module-name>
iverilog -g2012 -o sim.out tb/tb_<module>.sv rtl/<module>.sv
vvp sim.out
git push origin feature/tb-<module-name>
gh pr create --base develop --title "test: <モジュール名> テストベンチ"
```

