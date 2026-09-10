# Light/dark theme と system appearance

## 目的

Phase 8 の CFG-05 と native experience の system appearance 要求を、Dart が所有する
theme policy と汎用 `dart_appkit` の OS appearance event 境界に分離して実装する。
light/dark 固定選択、system appearance 追従、設定による custom palette を同じ通常製品経路で
扱い、appearance 変更時にも pane、PTY、screen、Metal surface、window を作り直さない。

## 背景

- 現在の `TerminalConfiguredTheme` は `default` だけを受理し、実質的な theme catalog や
  system appearance は持たない。
- palette option は schema default を含む完成済み color set として
  `TerminalProductConfiguration` へ投影されるため、built-in theme と利用者の明示 override を
  区別できない。
- `TerminalPalette` は起動時の initial color と現在値を保持するが、OSC palette override と
  appearance 由来の reset default を別レイヤーとして保持しない。
- `dart_appkit` の public event protocol は v6 で、application active/reopen/terminate はあるが
  `NSApplication.effectiveAppearance` の変更通知と typed cache はない。
- Apple SDK の AppKit header は `effectiveAppearance` を KVO で監視することを推奨し、
  `bestMatchFromAppearancesWithNames:` と `NSAppearanceNameDarkAqua` を提供している。
- ADR-001 の境界に従い、OS appearance の観測だけを `dart_appkit`、theme/palette の意味論を
  Dart Terminal が所有する。

## 範囲

1. `dart_appkit` event protocol v7 に application appearance change を追加する。
   bool state は dark/light を表し、Dart API は enum、初期 cache、typed stream を公開する。
2. `theme = system | light | dark` と組み込み light/dark pair を追加する。
   既存 `default` は互換 alias として `system` に解決する。
3. schema default ではない明示 palette option だけを selected built-in theme の custom overlay と
   して扱う。
4. `TerminalPalette` に theme reset-default と OSC override のレイヤーを持たせ、appearance
   変更を一回の generation/damage 更新として適用する。
5. system 選択 pane だけを application appearance event に追従させ、固定 theme pane は変更しない。
6. Developer JIT / Release AOT の実製品で初期選択、live 切替、custom override、resource identity、
   teardown を受け入れる。

## 対象外

- 外部 theme file の探索、named theme repository、download/install UI。
- Phase 9 の terminal light/dark escape notification。
- Phase 8 後続の settings UI、effective-config inspector、deprecated warning。
- accent color、Increase Contrast、Differentiate Without Color、その他の accessibility appearance。
- `dart_appkit` の view/control 単位の appearance/style API 全般。

## 依存関係と境界

- `dart_appkit` は application appearance を content-free な event として公開するだけで、
  terminal theme 名や色を知らない。
- Terminal config priority/provenance と reload transaction は既存契約を維持する。
  `theme` と palette は new-session option のままで、config reload は既存 pane の選択を変えない。
- system appearance は config reload と独立した live OS state であり、既存の system pane に適用する。
- initial event は event port 登録後に一度送出して cache を seed する。v1–v6 consumer へ v7 event を
  送らず、既存 protocol の decode と挙動を保つ。
- adjacent repository `/Users/remi/dart/dart_appkit` の変更はユーザーが本セッションで明示的に
  許可した。同 repository に追加の `AGENTS.md` はない。

## 設計判断

- `Dart Dark` は従来の zero-config palette と同値にし、dark appearance では表示互換を保つ。
- zero-config の theme は system とする。既存の `default` 記法は warning なしで system alias と
  して受理する。migration warning は CFG-07 の責務である。
- custom theme は本タスクでは選択した built-in pair に対する既存 palette option の明示
  override と定義する。named external catalog は対象外だが、built-in catalog は light/dark の
  stable pair を公開する。
- OSC set は値が現在値と同じでも override ownership を記録する。OSC reset は override を解除し、
  その時点の theme reset-default へ戻す。system appearance 変更時は override されていない色だけを
  更新する。
- appearance 判定は effective appearance を Aqua/Dark Aqua に best-match して二値化する。
  privacy-sensitive data や文字列 payload は event に含めない。
- live switch は palette の全 reset-default/current color を atomic batch で更新し、visual change が
  ある場合だけ一 generation と一 surface notification を発生させる。

## 順序付きサブタスク

### 1. `dart_appkit` application appearance event protocol と typed cache

- event protocol v7 と C/Dart constants、version gate、encoder、initial snapshot、KVO observer、
  shutdown cleanup を追加する。
- typed enum/event/cache/stream と fake/test API を追加する。
- native bridge/encoder、Dart unit、legacy version smoke、repository docs/roadmap を更新して検証し、
  `dart_appkit` に独立コミットする。

完了条件: v7 consumer が初期 appearance と変更を exactly once に観測でき、v1–v6 では新 event が
抑止され、observer が reset/shutdown 後に event を送らない。

### 2. built-in light/dark pair と layered palette/custom override

- typed theme selector/catalog と stable light/dark palette を追加する。
- config provenance から明示 palette overlay を構築する。
- palette に theme default/OSC override layer と atomic appearance apply を追加する。
- parser/config/palette tests と option reference freshness を更新して独立コミットする。

完了条件: system/light/dark/default alias、built-in pair、明示 override、OSC set/reset、color
16–255 維持、bounded typed storage が Dart-only test で固定される。

### 3. system appearance の live product projection

- 初期 `AppKitApplication.effectiveAppearance` を通常起動 configuration へ渡す。
- pane ごとの captured theme policy を保持し、system pane だけを live event で更新する。
- palette damage を既存 screen/surface notification 経路へ流し、resource を再生成しない。
- fake AppKit application/product tests と docs を更新して独立コミットする。

完了条件: initial light/dark、live system switch、fixed theme 非追従、new-session reload 境界、
multi-pane/resource identity/cleanup が自動検証される。

### 4. M1 両 runtime theme/appearance 受け入れと親項目完了判定

- v7 raw application appearance event を実 JIT/AOT product へ注入し、実 Metal frame の色、
  custom override、system/fixed pane、resource identity、event/PTY/worker/native handle cleanup を検証する。
- runtime smoke manifest/hash、README、FEATURE_MATRIX、verification report を更新する。
- full runtime gate と repository test を再実行し、証跡が揃った場合だけ親項目を完了する。

完了条件: M1 Developer JIT / Release AOT が同一 contract を満たし、full gate が成功し、未完了の
subtask がない。

## 検証方針

- `dart_appkit`: native bridge unit、encoder unit、Dart unit、format/analyze/test、legacy v1–v6 smoke、
  必要な repository aggregate gate。
- Dart Terminal core/config: targeted Dart tests、全 Dart suite、format/analyze、generated reference
  freshness、source/bundle audit。
- product: fake AppKit lifecycle testsと、M1 JIT/AOT の real AppKit/Metal/PTY acceptance。
- 最終: `CI=true DART_SUPPRESS_ANALYTICS=true make RUNTIME_ARCH=arm64 runtime-verify` と
  `CI=true DART_SUPPRESS_ANALYTICS=true make test`。
- 各サブタスクで差分、未追跡生成物、秘密情報、隣接 repository の無関係変更を確認する。

## 調査記録

### 2026-09-10 着手時

- Dart Terminal と `dart_appkit` の作業ツリーはいずれも clean。
- 直前の reload 親項目は commit `4847f9b` で完了し、ROADMAP の最初の未完了項目が本項目で
  あることを再確認した。
- `TerminalConfigSnapshot.resolved(option).source.kind` で schema default と file/CLI の明示値を
  区別できるため、schema の palette option を増やさず custom overlay を保持できる。
- `TerminalSession` は pane 固有 palette と screen set を所有する。palette change は screen damage を
  作るが、外部 appearance event から描画を起動するには pane owner の既存 notification 呼び出しも
  必要である。
- palette の現在 typed storage は current/initial の 256-entry `Uint32List` 2本、計 2048 bytes。
  override bitmap を32 bytes追加し、上限を 2080 bytes として検証する方針とした。
- AppKit SDK header で `NSApplication.effectiveAppearance` (macOS 10.14+) と KVO 推奨を確認した。
  deployment target macOS 14 では availability fallback は不要である。
- `dart_appkit` の current public event protocol は v6、application event type は 30–32。
  type 33 / protocol v7 を使用し、既存 generic bool `state` field を再利用できる。
- JIT/AOT host は共通 `PostNativeEventToDartPort` と bridge registration を使うため、observer は
  bridge 内へ一度実装し host ごとの重複を避ける。

## 検証記録

### 2026-09-10 `dart_appkit` appearance event

- adjacent `dart_appkit` に event protocol v7 / type 33 を追加した。payload は application-scoped、
  source identity 0、operation ID 0、bool state (`false` light / `true` dark) である。
- event port の v7 登録時に active snapshot に続いて effective appearance snapshot を送り、
  `NSApplication.effectiveAppearance` の KVO observer を登録する。再登録前と shutdown 時に observer を
  除去し、Aqua/Dark Aqua best-match が同じ通知は重複排除する。
- Dart API は `AppKitAppearance`、`ApplicationAppearanceChangedEvent`、nullable な
  `AppKitApplication.effectiveAppearance` cache、`onAppearanceChanged` stream を公開し、stream observer
  より先に cache を更新する。
- focused `CI=true DART_SUPPRESS_ANALYTICS=true make native-test event-encoder-test dart-test` は成功。
  実 `NSApp.appearance` light→dark KVO、同値 deduplication、shutdown 後の無通知、exact v7 encoding、
  malformed v6/v7、typed cache/stream、legacy selection を検証した。
- adjacent repository の full `CI=true DART_SUPPRESS_ANALYTICS=true make test` は exit 0。scaffold、
  C/C++ contract、全 native bridge/Runner/runtime/capability/renderer/PTY suite、全 Dart analyze/test、
  example Kernel、current FFI、legacy v1 fallback が成功した。
- adjacent implementation/documentation は commit `16385ce` (`Expose application appearance changes`)
  として完了した。C ABI version 1 と v1–v6 record layout は維持されている。

## リスク・引き継ぎ

- KVO observer の登録解除と event-port 再登録で stale callback を残さないことを native test で
  固定する。
- system appearance の変更を自動受け入れする際は global OS preference を変更せず、v7 raw event
  注入で product contract を検証する。native KVO bridge 自体は `dart_appkit` test が担保する。
- light palette の具体値は contrast と既存 ANSI semantics を targeted renderer/palette test で確認し、
  実 Metal pixel acceptance でも背景/前景を固定する。
