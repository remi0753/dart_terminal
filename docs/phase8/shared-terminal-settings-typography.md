# zero-config terminal / Settings editor shared typography

Status: complete (2026-09-11)

## 目的

zero-config terminal の本文と Settings の主編集面が、同じ macOS system
monospace font、weight、point size を使うことを製品契約として固定する。現在の静かな
editor-first Settings UI と terminal 本文の視覚的な統一感を保ち、将来どちらか一方の
直書き値だけが変更される drift を防ぐ。

## 背景と確認済みの事実

- `TerminalProductConfigSchema.fontFamily` の既定値は空文字で、renderer 側では
  AppKit の system monospace 選択を意味する。
- `TerminalProductConfigSchema.fontSize` と
  `TerminalLiveMetalSurface.defaultFontPointSize` の既定値は 14pt である。
- Settings の主編集面 `terminalSettingsEditorConfiguration` も system monospace、
  regular、14pt を指定している。
- `dart_appkit` の TextEditor は
  `NSFont.monospacedSystemFont(ofSize:weight:)` 相当を使い、terminal renderer も
  font family が空なら同じ AppKit API と regular weight を使う。したがって現状も
  native font 解決結果は同じだが、Dart 側の family/size は別々に直書きされている。
- Settings の status/detail surface は補助情報の視覚階層として 12pt/13pt を使う。
  ユーザーが比較している主たる設定画面は editable document surface である。

## 範囲

- system monospace family、regular weight、14pt を表す platform-neutral な product
  default typography を一か所に定義する。
- typed config schema、zero-config Metal surface、Settings editor が同じ定義を参照する。
- unit/integration policy test で、schema、renderer、Settings editor の family/size/weight
  が一致することを検査する。
- README と feature matrix に、共有される既定値の契約を反映する。

## 対象外

- ユーザーが `font-family` / `font-size` で明示した terminal 設定を Settings editor
  自体へ live 適用すること。
- Settings の status/detail、command palette、旧 inspector の補助的な文字サイズ変更。
- Metal と NSTextView の rasterization、line height、glyph atlas の描画方式の統一。
- `dart_appkit` の公開 API または native font resolver の変更。両経路はすでに同じ
  AppKit system monospace API を使用している。

## 依存関係とリスク

- 共有定義は AppKit に依存させず、typed config の platform-neutral 性を維持する。
- terminal renderer constructor の optional default は compile-time constant が必要なため、
  schema object の runtime `defaultValue` ではなく const policy を正本にする。
- 表示値そのものは変えない。リスクは import 境界と generated acceptance hash の
  freshness に限られる。

## 完了条件

- zero-config schema と renderer が共有 family/size を使う。
- Settings editor が同じ system monospace / regular / size を使う。
- 一方だけを変更すると失敗する regression test がある。
- formatter、analyzer、全 Dart test、関連する M1 Developer JIT / Release AOT runtime
  acceptance と bundle/source freshness gate が成功する。
- 検証結果をこの文書へ記録し、ROADMAP の本項目を完了にして単独コミットする。

## 検証方針

1. AppKit policy/config/renderer test で shared contract を確認する。
2. `make test` でgenerated freshness、format、analyzer、全Dart回帰を確認する。
3. M1 arm64 の terminal display と Settings/configuration runtime suite を Developer JIT /
   Release AOT の両方で実行する。
4. package/bundle/source freshness audit を実行し、generated evidence に drift があれば
   正規 generator で同期する。

## 設計判断

2026-09-11 時点では、見た目の値を新しく変更するのではなく、既存の system monospace /
regular / 14pt を共有 const policy に昇格させる。これはユーザーが求める現在の Settings
editor を基準とした統一を維持しつつ、設定 schema と実 renderer の両方まで同じ正本へ
結び付ける最小の変更である。補助 surface の小さい文字は、全要素を一様にして情報階層を
失わないため対象外とする。

## 実装結果

- `lib/src/terminal_typography.dart` に、system monospaceを表す空familyと14ptを持つ
  `TerminalDefaultTypography`を追加した。
- typed config schemaの`font-family` / `font-size`、および
  `TerminalLiveMetalSurface`のconstructor defaultを同じconst policyへ接続した。
- Settingsの主編集面と旧display-only inspectorのsystem monospace sizeも同じpolicyへ
  接続した。主編集面のregular weightはrenderer native resolverのregular weightと一致する。
- `terminal_appkit_policy_test.dart`でschema、renderer、Settings editorのfamily kind、
  family、weight、sizeの対応を一括検査し、`terminal_live_metal_surface_font_test.dart`では
  実CoreText catalog metricsを共有sizeと照合するようにした。
- READMEとfeature matrixに共有契約を明記し、compatibility regression coverageの
  source hashを正規generatorで同期した。
- `dart_appkit`の変更は不要だった。TextEditorとterminal rendererのnative実装は、すでに
  同じAppKit system monospace resolverをregular weightで使用している。

## 実装・検証ログ

- 2026-09-11: `dart format` は対象6ファイルの整形を完了した後、sandbox外の
  `~/.dart-tool/dart-flutter-telemetry-session.json` のmtime更新を拒否されて非0終了した。
  `DART_SUPPRESS_ANALYTICS=true`を付けたsandbox内再試行も同じmtime更新で非0終了したが、
  いずれもformatter結果は`0 changed`まで確認できた。以降はsandbox外の`make test`に含まれる
  format gateで検証する。
- 2026-09-11: sandbox外で開始した最初の`make test`は、VT table、parser trace、config
  reference、keybind/action reference、Phase 7 AppKit evidence、compatibility regression
  replayまで成功した後、`terminal_live_metal_surface_font_test.dart`の変更に対応する
  compatibility regression coverage reportがstaleとして停止した。正規generatorで
  source hashを更新し、全gateを最初から再実行する。
- 2026-09-11: generator差分の確認により、stale箇所はfont testではなく、このタスクで
  更新した`README.md`と`FEATURE_MATRIX.md`のsource hashだけだったと判明した。上記の
  初期推定を訂正する。生成結果はこの2 hash以外を変更していない。
- 2026-09-11: source evidence同期後の`CI=true DART_SUPPRESS_ANALYTICS=true make test`
  は成功した。generated/freshness gate一式、246 Dart filesのformat check、analyzer
  (`No issues found!`)、全Dart test (`dart_terminal tests passed`)を確認した。
- 2026-09-11: `make RUNTIME_ARCH=arm64 runtime-source-check runtime-bundle-audit
  runtime-terminal-display-integration runtime-configuration-integration`は成功した。
  source auditは新規2ファイルのstage前に`tracked=452`、stage後の最終再実行で
  `tracked=454 product_native_sources=0 reviewed_test_native_sources=1`、
  Developer JIT / Release AOT bundle auditはいずれもpassした。terminal display suiteは
  Developer JIT 3292ms / Release AOT 2265ms、Settings editor、save、permission retention、
  reload、font fallback、effective configを含むconfiguration suiteはDeveloper JIT
  1689ms / Release AOT 1145msでpassした。
- 未検証事項および残存blockerはない。共有値自体は既存と同一なので、明示的なfont設定、
  Settings補助surface、rasterization/line-heightの挙動にも変更はない。
