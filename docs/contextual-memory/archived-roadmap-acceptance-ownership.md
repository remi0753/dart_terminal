# Archived roadmap compatibility acceptance ownership

## 目的

Terminal emulator release roadmapのarchive後も、互換性acceptanceがhistorical ownerを正しい文書で検証し、
通常のaggregate gateを通過できるようにする。

## 背景

CM-01の`make test`で、`terminal-compatibility-regression-coverage-check`が`hilite-mouse owner is not a
reviewed ROADMAP owner`として失敗した。旧roadmapは意図どおり
`docs/archive/terminal-emulator-release-roadmap.md`へ移されたが、application acceptance manifestとvalidatorは
`ROADMAP.md#phase-6-focus-mouse-query`を固定参照し、rootの新roadmap本文だけを検索していた。

## 範囲

- historical owner pathをarchived release roadmapへ更新する
- validatorがowner phraseをarchive本文で確認するよう更新する
- derived compatibility coverage reportを正規generatorで再生成する
- focused checkと`make test`を実行する

## 対象外

- compatibility classification、hilite-mouse対応方針、terminal behaviorの変更
- current contextual-memory roadmapの順序や仕様の変更
- CM-01 Note modelの変更

## 依存関係

- `docs/archive/terminal-emulator-release-roadmap.md`
- `compatibility/application_matrix_acceptance.json`
- `tool/terminal_application_acceptance.dart`
- `tool/terminal_compatibility_regression_coverage.dart`

## 完了条件

- manifestとderived reportがarchive ownerを指す
- validatorがarchive本文の既存reviewed phraseを検証する
- focused compatibility checksとaggregate gateがpassする
- CM-01の未コミット差分を含めず、修復だけを一つのcommitにする

## 検証方針

- generatorを使い、手作業でderived hash/countを書き換えない
- focused application acceptance／regression coverage checkを実行する
- `git diff --check`と`make test`で既存製品の回帰がないことを確認する

## 調査・実施記録

### 2026-09-20: 着手

- `ROADMAP.md`の先頭未完了へ本前提修復を追加し、CM-01を一時停止した。
- 最初の`make test`は既存PTY diagnosticの到着競合で一度失敗したが、`make dpty-dart-test`単独再実行はpassした。
- 2回目の`make test`はcompatibility coverageで決定的に失敗した。Validatorはroot `ROADMAP.md`だけを読み、
  manifest ownerも旧pathのままである一方、review対象phraseはarchiveのPhase 6に存在することを確認した。
- CM-01の変更はworktreeに残っているが、本taskのcommitでは明示pathだけをstageする。

### 2026-09-20: 実装・検証結果

- Application acceptanceのhistorical ownerを
  `docs/archive/terminal-emulator-release-roadmap.md#phase-6-focus-mouse-query`へ移し、validatorの全reviewed
  owner keyとPhase 9 prefixも同じarchive pathへ更新した。
- `make terminal-compatibility-regression-coverage`でderived reportを再生成した。Archive前後に変更された
  `README.md`／`FEATURE_MATRIX.md`のpinも同時にfreshになった。
- 下流freshness gateで`ghostty_p0_p1_gap_inventory.json`と
  `release_candidate_daily_use_matrix.json`のstale hashを検出したため、それぞれ正規generatorで再生成した。
  Classification、count、known limitation、release blocker値は変わらず、source path/hashだけが更新された。
- Focused validation:
  `make terminal-application-acceptance-check terminal-compatibility-regression-coverage-check`はpass、
  `make ghostty-p0-p1-gap-inventory-check release-candidate-daily-use-matrix-check`は再生成後pass、
  `make terminal-distribution-policy-test`はpassした。
- Aggregate validation: `CI=true DART_SUPPRESS_ANALYTICS=true make test`は最終実行でpassした。
  formatは353 files 0 changes、root analyzeはissues 0、全Dart/native/compatibility/distribution testがpassした。
- 途中のaggregate試行は、最初にroot owner残存、次に下流gap inventory staleを順に検出して失敗した。
  いずれも生成物を直接編集せずdependency順にgeneratorを実行して解消した。
- `git diff --check`はpass。Terminal behavior、compatibility disposition、`dart_appkit`、CM-01 model contractは
  変更していない。
