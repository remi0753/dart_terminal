# Phase 5 — Option-arrow shell word navigation regression

## 目的

macOS の terminal surface で `Option+Left`／`Option+Right` を押したとき、
`D`／`C` を入力せず、既定の `macos-option-key=escape` 設定で対話 shell の
前／次の単語へ移動できるようにする。

## 背景

現行の legacy xterm encoder は Option 付き cursor key を一律に
`CSI 1;3 D`／`CSI 1;3 C` として PTY へ送る。readline や zsh の line editor が
この修飾付き cursor sequence を binding として認識しない場合、sequence の末尾が
通常文字として解釈され、Left では `D`（Right では `C`）が入力され得る。

macOS terminal で一般的な Option 単語移動は Meta-B／Meta-F、すなわち
`ESC b`／`ESC f` として表現でき、既定の Option-as-Escape 契約とも整合する。

## 範囲

- legacy keyboard path と `macos-option-key=escape` の組み合わせで、単独の
  `Option+Left` を `ESC b`、`Option+Right` を `ESC f` に encode する。
- AppKit physical key／modifier adapter から encoder、実 PTY write までを通る
  deterministic acceptance matrix に左右の Option-arrow case を追加する。
- encoder unit test、native text-input bridge test、製品 JIT／AOT acceptance を更新する。
- README、feature matrix、手動 input-source checklist、生成済み compatibility evidence を
  現行契約へ同期する。

## 対象外

- `macos-option-key=text` の Option 文字入力契約の変更。
- Shift／Control／Command を併用した cursor key の xterm modifier contract の変更。
- Kitty keyboard protocol が明示的に有効なときの protocol encoding の変更。
- shell 側 key binding、shell plugin、SSH／remote shell 設定の変更。
- Up／Down、Home／End、PageUp／PageDown の意味変更。

## 依存関係

- `TerminalKeyEncoder` の Option-as-Escape と mode-aware key encoding。
- `TerminalTextInputClient` と native `NSTextInputClient` acceptance matrix。
- `TerminalInputAcceptanceMatrix.standard` を使う real-PTY 製品検証。

## 完了条件

- 既定設定の `Option+Left`／`Option+Right` が、それぞれ正確に
  `1b 62`／`1b 66` を一度だけ PTY へ送る。
- application cursor mode でもこの shell word-navigation contract が変わらない。
- `macos-option-key=text` では Option を modifier として除いた通常の Left／Right が
  従来どおり送られる。
- Shift などを併用した cursor keyと、active Kitty keyboard protocol の出力が
  従来の protocol sequence のまま維持される。
- native acceptance matrix が Option と Function modifier、左右の physical key、
  UTF-8 private-use key textを保持し、両製品 target が期待 byteを実 PTY で確認する。
- focused test、native test、静的解析、format、全体 gate が成功する。
- 差分、文書、生成物を見直し、ROADMAP を完了へ更新して単独 commit にする。

## 検証方針

1. encoder unit test で legacy、application cursor、Option text、modifier 併用、
   Kitty protocol の出力を byte exact に確認する。
2. standard input matrix と native bridge test で AppKit event packet の
   physical key／modifier／generation order を確認する。
3. Developer JIT と Release AOT の product input acceptance で、native event から
   real PTY までの `ESC b`／`ESC f` を byte exact に確認する。
4. `make test` で既存 terminal compatibility と生成物 freshness を確認する。

## 調査記録

### 2026-09-15 — 再現経路と原因

- `lib/src/terminal_input/terminal_key_encoder.dart` の `_encodeSpecial` は全 arrow key を
  `_cursor` へ渡し、Option modifier を持つ Left／Right を
  `CSI 1;3 D`／`CSI 1;3 C` にしていた。
- `D` が見える現象は、shell line editorがそのsequenceを未登録として扱い、末尾を
  printable inputとして解釈する症状と一致する。
- encoder は Kitty pathをlegacy pathより先に評価するため、legacy branchだけを狭く
 変更すればactive Kitty protocolを維持できる。
- `macos-option-key=text` はspecial-key encoding前にOption bitを除くため、その設定では
  plain cursor sequenceを維持できる。
- standard input acceptance matrixのnative event列は
  `packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m` に固定実装される。
  Dart側だけでなくnative matrixとcapability testも同時に更新する必要がある。

## 判断

### 採用

- Optionだけを入力modifierとして持つ Left／RightをMeta-B／Meta-Fへ変換する。
  AppKitがphysical arrowに付加するFunction bitはkey provenanceであり、併用modifierとは
  扱わない。
- Shift／Control／Commandのいずれかを併用する場合は、既存のxterm modifier sequenceを
  維持する。範囲を限定し、selectionやapplication固有bindingを壊さないためである。

### 不採用

- 全Option付きcursor keyを変更する案。今回必要なのは左右のword navigationだけで、
  上下やHome／Endの意味まで変える根拠がない。
- shellごとの設定注入。terminal emulatorの送信byteを安定させる問題であり、shell設定や
  remote環境へ副作用を広げる必要がない。

## 実装・検証記録

### 2026-09-15 — 実装

- legacy encoderのLeft／Rightに、Optionだけを意味modifierとして持つeventを
  `ESC b`／`ESC f`へ変換する狭い分岐を追加した。Function／Caps Lock／Numeric Padは
  physical-key provenanceまたはlock stateなので判定を妨げず、Shift／Control／Commandは
  既存xterm／arbitration経路を維持する。
- standard input matrixへOption-Left／Rightを追加し、native AppKit matrix generatorと
  native capability testにも同じevent順、virtual key code、Option+Function modifier、
  private-use characterを追加した。
- encoder testでapplication cursor mode、Option text mode、Option+Shift、active Kitty
  protocolを含む境界をbyte exactに固定した。

### 2026-09-15 — 検証中に発生した環境要因

- `dart format ... && dart run test/terminal_key_encoder_test.dart && ...` の初回実行は、
  formatが変更なしで成功した後、Dart CLIがsandbox外の
  `/Users/remi/.dart-tool/dart-flutter-telemetry-session.json` の更新を試み、
  `Operation not permitted`で停止した。コード／テストfailureではない。
- 再発防止として以後のDart実行は`DART_SUPPRESS_ANALYTICS=true`を明示する。
- analytics抑止だけで再実行したところ、build hookのMetal compilerがsandbox外の
  `/Users/remi/.cache/clang/ModuleCache`へmodule cacheを書こうとして再度停止した。
  さらにDartのsession metadata更新も終了時に試行された。以後は`CI=true`を併用し、
  `CLANG_MODULE_CACHE_PATH`をworkspaceから書ける`/private/tmp`配下へ限定する。
- `CLANG_MODULE_CACHE_PATH`は`xcrun metal`に反映されず、同じcache pathで停止した。
  host cache accessを許可したfocused encoder／matrix testはどちらも成功した。
- `make terminal-renderer-native-test`はsandbox内でも成功し、Objective-C／Objective-C++を
  warning-as-errorでbuildしたnative capability contractを完走した。
- Developer JIT／Release AOT display acceptanceの初回sandbox実行もDeveloper JIT build hookで
  同じMetal module-cache denialになり、製品起動前に停止した。既知のhost cache access境界で
  同じcommandを再実行する。
- host cache accessで再実行した
  `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 runtime-terminal-display-integration`
  は成功した。Developer JIT（12,464 ms）とRelease AOT（10,902 ms）の両方で、version 2の
  14行／15 event／55 byte matrixをnative text clientからproduct router、実PTYまで配送し、
  shell側のbyte exact比較を通過した。
- `runtime_integration_smoke.dart`、README、FEATURE_MATRIX、native renderer sourceの変更に
  追従してPhase 7 acceptance、compatibility regression coverage、Ghostty P0/P1 gap inventory、
  release-candidate daily-use matrixを正規generatorで再生成した。

### 2026-09-15 — 最終検証

- `dart --suppress-analytics run test/terminal_key_encoder_test.dart`: 成功。
- `dart --suppress-analytics run test/terminal_input_matrix_test.dart`: 成功。
- `make terminal-renderer-native-test`: 成功。Option-arrow 2 eventを含む全packetの順序、
  key code、modifier、text/unmodified text、queue cleanupを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 runtime-terminal-display-integration`:
  成功。Developer JIT／Release AOTの両方でversion 2 matrixの55 byte完全一致を確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。native package群、generator freshness、
  terminal compatibility／differential／application／terminfo／shell integration／distribution、
  Dart format 346 files（変更0）、`dart analyze`（issue 0）、security stress、aggregate Dart
  suiteを完走し、`dart_terminal tests passed`を確認した。
- 実入力sourceやuser設定は変更していない。物理操作の追加確認手順は
  `docs/phase5/input-source-manual-checklist.md`へ追記したが、自動検証で同じAppKit raw-key
  boundaryとreal PTY byte contractを両runtimeで確認済みである。
- 未検証事項、残課題、阻害要因はない。
- commit前の初回stageはsandboxが`.git/index.lock`作成を拒否して停止した。working treeの
  変更は保持されており、同じ明示file listをrepository metadata write権限で再実行する。
