# Terminal background opacity

## 目的

terminal本文を描画する背景色へ利用者指定の透過度を適用する。設定はapplication全体で
一つとし、既存および新規のwindow、native tab、split pane、Quick Terminalに同じ値を
即時反映する。Settings windowとCommand Paletteはterminal surfaceではないため不透明の
まま維持する。

## 背景

- `ROADMAP.md`のP1 renderer候補はtransparencyをreadabilityとpower costの確認後に導入する
  項目としていたが、Phase 8のoption-family実装時点ではbackground opacity/blurを対象外と
  していた。今回の利用者要求によりopacityだけを完了済み機能の拡張として再開する。
- typed configuration schemaはCLI、生成リファレンス、Settings document、reload差分計画の
  正本である。作業開始時のschemaは52 optionを持つ。
- terminal本文はpackage-owned `DtrTerminalMetalView`へ表示され、SettingsとCommand Paletteは
  別の通常AppKit viewである。このnative view境界に透明合成を限定できる。
- `TerminalMetalFrameHeaderV1.background_rgba`とMetal clear colorは既にstraight-alpha RGBAを
  保持する。一方、現在のcompositorはdefault background alphaを常に`0xff`へ変換し、native
  view/windowもopaqueな既定状態のままである。
- pane作成時の`TerminalProductConfiguration`はsessionごとにcaptureされる。opacityまで
  new-session値にするとreload前後のpaneで値が分かれるため、共有presentation設定として
  全live surfaceへ投影する必要がある。

## 範囲

1. `background-opacity`を0.0（完全透明）から1.0（不透明）、既定1.0の有限doubleとして
   typed schemaへ追加し、live application policy、canonical formatter、CLI、Settings
   document、生成configuration referenceへ接続する。
2. product configurationへ値を保持し、default backgroundだけのframe alphaへ変換する。
   glyph、cursor、selection、明示ANSI cell background、Kitty imageのalphaは変更せず、文字と
   明示色の可読性および既存source-over意味を保つ。
3. terminal専用custom-view operationをversioned packed contractとして追加する。opacityが
   1未満なら`CAMetalLayer`と、それを所有する`NSWindow`をnon-opaque/clearにし、1へ戻した時は
   opaque状態へ復帰する。viewが後からwindowへattachされる場合も保持値を適用する。
4. reload成功時に全live surfaceを同じaccepted値へ更新しfull redrawを要求する。後から作る
   window/tab/pane/Quick Terminalも最新値でattachする。
5. parser/schema、product profile、frame encoding、native view、複数階層live projection、
   cleanupをunit/native/product acceptanceで検証する。

## 対象外

- Settings window、Command Palette、Terminal Inspector、確認dialogなどterminal本文以外のUI
- background blur、material/vibrancy、windowごと・tabごと・paneごとの個別opacity
- foreground/glyph、cursor、selection、明示ANSI background、画像の一括alpha変更
- opacityに応じた配色やcontrastの自動変更

## 実施順と依存関係

1. **typed schema、Settings document、product configuration**
   - schema option、parse/format、immutable profile、reload分類、生成referenceを追加する。
   - 完了条件: 境界値0/1と中間値を受理し、非有限・範囲外を拒否し、既定値1を維持する。
2. **Metal frame alphaとmacOS transparent surface contract**
   - compositor/surfaceとrenderer packageのDart/native custom operationを追加する。
   - 完了条件: base clear alphaだけが指定値になり、view/window透明状態がattach順序とlive変更の
     両方で整合し、1への復帰も検証できる。
3. **既存／新規の全window・tab・paneへのlive投影と両runtime受け入れ**
   - hierarchy attach/reloadを共有値へ接続し、Settings/Command Paletteの非対象境界を固定する。
   - 完了条件: reload前から存在するsurfaceとreload後に作る全surfaceが同じ値を持ち、通常の
     Developer JIT/Release AOT product acceptanceとaggregate gateが通る。

各subtaskは個別に検証、記録、`ROADMAP.md`更新、完了commitを行い、前のsubtask完了前に
次へ進まない。

## 検証方針

- Dart unit: config decode/format/provenance/change policy、Settings document、product profile、
  compositor frame header、surface live update/no-op/invalid state。
- Native: custom operationのsize/version/range/reserved検証、layer opacity、window attach前後、
  transparentからopaqueへの復帰、owner teardown、ABI/capability test。
- Product: 2 window、native tab、split pane、Quick Terminalを含むsurface全体で初期値とreload値を
 確認し、Settings/Command Paletteがterminal operationの対象に入らないことを検証する。
- Gates: format、analyze、unit/native package tests、configuration reference freshness、
  Developer JIT/Release AOT configuration integration、変更範囲に対応するaggregate gate。

## 判明事項・判断記録

- 2026-09-14: 作業開始時のworktreeはclean、基点は`0d42ad7 Keep command palette selection visible`。
- 2026-09-14: opacityはnew-session値ではなくliveなapplication-wide presentation値とする。
  既存paneのfont/theme等のcapture semanticsを変えず、opacityだけを全surfaceへ別途投影する。
- 2026-09-14: native transparencyは汎用`dart_appkit` window APIへ広げず、terminal rendererの
  custom view operationへ閉じる。これによりSettingsとCommand Paletteは影響を受けない。
- 2026-09-14: opacityはdefault terminal backgroundにだけ適用する。明示cell backgroundまで
  透過するとANSI applicationの意図と可読性を変えるため採用しない。
- 2026-09-14: interactive productのterminal surfaceはすべて1つの`createResources`を通り、
  standard window/tab/splitとQuick Terminalが同じowner mapで管理されることを確認した。
  新規surfaceはconfiguration authorityの最新opacityでattachし、accepted reloadはowner mapの
  snapshotを走査して全live surfaceを同期更新する。破棄済みsurfaceは対象から外す。
- 2026-09-14: SettingsとCommand Paletteはterminal hierarchyのowner/viewを作らない別windowで、
  terminal renderer custom operationを受ける経路がない。product acceptanceで別window identity、
  pane resource数の不変、terminal opacity値の不変を確認して非対象境界を固定する。

## 検証結果

- 2026-09-14: sandbox内の`dart run test/terminal_product_configuration_test.dart`は、
  native asset buildが`~/.cache/clang/ModuleCache`へ書けず、Dart telemetry fileのmtimeも
  更新できない`Operation not permitted`で開始前に失敗した。実装failureではないため、同じ
  検証を通常のbuild cache権限で再実行する。
- 2026-09-14: 通常cache権限でfocused product-configuration testは成功した。続く
  `make test`はconfiguration reference（53 option、live 12、new-session 41）、keybind reference、
  localization、privacy auditまで成功し、schema countを含むPhase 7 AppKit acceptance生成物が
  staleとして停止した。正本から再生成してfreshnessを再検証する。
- 2026-09-14: Phase 7 acceptance再生成後の`make test`は同checkを通過し、次に
  `FEATURE_MATRIX.md`のcurrent-state更新を入力に持つPhase 6 compatibility coverageの
  freshnessで停止した。coverage内容の受け入れ件数は変えず、正本hashを再生成する。
- 2026-09-14: compatibility coverage再生成後は、全unit/native checksとapplication
  acceptanceまで成功した後、同じFeature Matrix hashを持つP0/P1 gap inventoryのfreshnessで
  停止した。gap分類や件数は変更せずinventoryを再生成する。
- 2026-09-14: inventoryとdaily-use matrix再生成後の`make test`はformat/analyzeまで成功し、
  Settings初期documentのnative hierarchy testに残っていた固定option数52の期待で停止した。
  schema-derived内容は正しく53件だったため、Settings lifecycleと診断fixtureの期待数を53へ
  更新した。
- 2026-09-14: focused native hierarchy testは成功した。期待数変更に伴うPhase 7 acceptanceを
  再生成した後、`make test`はP0/P1 gap inventoryまで成功し、その新しいacceptance hashを
  参照するdaily-use matrixのfreshnessで停止した。matrixを再生成してから再確認する。
- 2026-09-14: Settings native hierarchy focused testは更新後に成功した。そのtest sourceを
  入力に持つPhase 7 acceptance hashが再びstaleになったため、最終test前に再生成する。
- 2026-09-14: 再生成後の`make test`はmain unit suite内のSettings Inspectorに残った
  52-entry固定期待で停止した。effective snapshot自体は53件を公開しているため、検索件数と
  表示範囲期待、および通常configuration acceptance内の全option集合期待を53へ更新した。
- 2026-09-14: Settings Inspector focused testは成功した。通常configuration acceptanceの
  source更新はPhase 7 acceptanceだけでなくP0/P1 gap inventoryにも連鎖するため、daily-use
  matrixの生成がstale inventoryをfail closedした。依存順に両生成物を更新する。
- 2026-09-14: dependency順に全生成物を更新した後、`make test`はexit 0で完了した。
  configuration referenceは53 option（live 12、new-session 41、repeatable 6）、formatは
  338 file変更なし、root analyzeはissueなし、native/package/unit/security/update/distribution
  checksを含む全aggregateが成功した。第1subtaskのschema、Settings document、profile、
  localization、reload分類と生成freshnessを完了とする。
- 2026-09-14: 第2subtaskのDart対象をsandbox内でformatし、5 file中compositor 1 fileの
  整形を適用した。整形後、Dart telemetry fileのmtime更新が`Operation not permitted`と
  なりcommand自体はexit 1となった。code formattingの失敗ではなくsandbox境界によるため、
  analytics無効化と通常cache権限を持つaggregate testでformatと終了statusを再確認する。
- 2026-09-14: compositor focused testはexit 0。opacity 0.5がframeのdefault clearのalphaのみを
  0x80へ変え、明示ANSI cell backgroundを0xffのまま保つこと、および範囲外・NaNの
  拒否を確認した。
- 2026-09-14: `make terminal-renderer-native-test terminal-renderer-dart-test`はexit 0。ABI 12、
  custom operationのsize/version/operation/reserved/range検証、viewとlayerのnon-opaque化、window
  attach後のclear/non-opaque化、opacity 1へのopaque復帰、Dart payload encoderを確認した。
- 2026-09-14: 第2subtaskの`make test`はformat/analyze、全native/package/unit、および
  application acceptanceまで成功後、renderer ABI source更新を入力に持つP0/P1 gap inventoryの
  freshnessで停止した。受け入れ件数やgap判定の変更ではないため、正本からinventoryと
  それに依存するdaily-use matrixを順に再生成する。
- 2026-09-14: inventoryとdaily-use matrixを依存順に再生成した後の`make test`は
  exit 0。formatは338 file変更なし、root/package analyzeはissueなし、renderer native/Dartを
  含む全native、unit、application、security、update、distributionのaggregate checkが成功した。
  第2subtaskのframe alphaとmacOS transparent surface contractを完了とする。
- 2026-09-14: 第3subtask実装後の`dart analyze`はissueなし。最初のDeveloper JIT
  configuration integrationは、fixtureに明示`background-opacity`行が1つ増えたのに
  `--show-config`のentry数期待が55のままで停止した。実出力は53 option、56 entry、
  opacity 0.8をlive/file provenanceで正しく公開していたため、期待entry数を56へ更新する。
- 2026-09-14: entry数修正後の`make RUNTIME_ARCH=arm64 runtime-configuration-integration`は
  exit 0。Developer JITとRelease AOTの両packaged runtimeで、初期0.8、既存一面への0.45
  live reload、その後作った2 window/3 native tab/4 pane全体への0.6 live reload、後続
  Quick Terminalへの0.6継承、Settings/Command Paletteの別owner境界、5 session/native handleの
  clean teardownが成功した。
- 2026-09-14: 第3subtaskの最初の`make test`はrendererを含むpackage/native check、
  configuration reference、localization、privacy auditまで成功し、application source変更を入力に
  持つPhase 7 AppKit acceptanceのfreshnessで停止した。受け入れ基準の変更はないため、
  Phase 7 acceptance、Feature Matrix依存のcompatibility coverage、P0/P1 gap inventory、
  daily-use matrixを依存順に再生成する。
- 2026-09-14: 上記4証跡を正本から依存順に再生成した後の`make test`は
  exit 0。configuration referenceは53 option（live 12、new-session 41）、formatは338 file
  変更なし、root/package analyzeはissueなし、全native/package/unit/application/security/update/
  distribution checkが成功した。第3subtaskと親taskの完了条件をすべて満たす。

## 完了状態

- schemaからnative windowまで、application-wideのterminal背景透過度を接続した。
- 既存と後続のwindow/native tab/split pane/Quick Terminalはすべて同じlive値を使う。
- SettingsとCommand Paletteはterminal renderer operationから分離され、透過度の対象外のままである。
- 本task由来の未検証項目、追加ROADMAP項目、阻害要因はない。

## リスク・引き継ぎ

- split windowでは複数terminal viewが同じ`NSWindow`を共有する。全surface同値をcontractに
  することでwindow opaque policyの競合を防ぎ、product testで同値性を固定する。
- alpha付きdrawableだけでは背後windowがopaqueだと透過しないため、frame alphaと
  `CAMetalLayer`/`NSWindow`の双方を更新する必要がある。
- 透明背景は背後内容によって可読性が下がり得る。既定1.0、明示opt-in、文字・明示背景を
  opaqueのまま保つことで安全側とする。blurは今回導入しない。
