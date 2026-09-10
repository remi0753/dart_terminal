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

### 2026-09-10 built-in theme / layered palette focused 検証

- 最初の sandbox 内 targeted Dart test は dependency build hook の Metal compiler が
  `/Users/remi/.cache/clang/ModuleCache/...` へ module cache を作れず exit 255 になった。source や
  assertion の失敗ではない。同じ command を workspace 外 cache 書き込みを許可した環境で再実行する。
- cache 書き込みを許可した最初の再実行では、新しい sealed
  `ApplicationAppearanceChangedEvent` により `terminal_application.dart` の既存2箇所の switch が
  non-exhaustive として compile error になった。これは dependency protocol 拡張に必要な source
  adaptation であるため、本サブタスクでは明示的 no-op case を追加する。live product projection は
  次の順序付きサブタスクまで実装しない。
- palette option は値だけでなく schema-default か明示値かが theme overlay の意味を変える。
  例えば light theme で明示 `#e5e5e5` は schema default と scalar が同じでも foreground を固定する。
  そのため option metadata に `sourceKindAffectsSemantics` を追加し、palette 19項目だけは
  schema-default と explicit の境界変更も new-session change plan に含める。file と CLI の間の
  同値移動、path/line だけの変更、他 option の provenance-only 変更は引き続き無視する。
- source audit の最初の `rg` invocation は shell の double-quoted command 内に Markdown backtick を
  含めたため、zsh が `default` を command substitution として解釈し `command not found` を出した。
  ファイル変更は発生しておらず、pattern 全体を single quote した command で再実行して stale な
  旧文言・旧 storage size がないことを確認した。今後の audit pattern は shell 展開されない quoting を使う。
- generated reference の所在調査では最初に存在しない `tools/` も検索対象へ渡したため `rg` が exit 2 に
  なった。正しい `tool/` で再実行し、現行 generator は keybinding/action reference のみで config option
  reference はまだ存在しないこと、aggregate `make test` がその freshness check を含むことを確認した。
- `TerminalBuiltInTheme` は既存 zero-config 色をそのまま `Dart Dark` とし、高 contrast の `Dart Light` と
  合わせた順序固定の2件 catalog を提供する。両 theme の logical foreground/background contrast ratio は
  7:1 以上を test で固定し、ANSI 16色は theme ごと、index 16–255 は既存 xterm table を共用する。
- config の正規 selector は `system`、`light`、`dark` で、旧 `default` は `system` に normalize する。
  programmatic caller 用 `defaultTheme` enum alias も system policy として扱う。zero-config は system policy
  だが、live appearance 接続前の本サブタスクでは既存挙動維持のため palette factory の fallback を dark とした。
- `TerminalProductPaletteConfiguration` は各 logical/ANSI color の explicit ownership を immutable に保持する。
  theme 解決時は built-in defaults、明示 config overlay、terminal OSC override の順に合成する。OSC set は
  同じ表示値でも ownership を獲得し、OSC reset は直近の theme/config reset default を表示する。
- `TerminalPalette` は256色分32-byte bitmap と logical color の override state を保持し、typed array は
  2048 bytes から bounded 2080 bytes になった。`applyResetDefaults` は全入力を先に検証し、OSC override を
  保持して current/reset default を一括更新し、visible change ごとに palette generation と全 attached screen
  damage を最大1回だけ進める。cursor-only change は既存 cursor-only damage を使う。
- dependency v7 event に対する2箇所の application switch は本サブタスクでは明示 no-op とした。
  system appearance cache/event を productへ接続する責務は次のサブタスクに残し、先行実装していない。
- 最初の aggregate `make test` は `terminal_application.dart` の reviewed source hash 変更により既存 Phase 7
  AppKit acceptance freshness check で停止した。`make phase7-appkit-acceptance` を実行し、生成差分が同ファイルの
  2つの同一 SHA-256 値だけであることを確認して証跡を更新した。
- 最終 focused verification は `dart format`、`dart analyze`、`terminal_config_test.dart`、
  `terminal_product_configuration_test.dart`、`terminal_palette_test.dart` がすべて exit 0。system/default alias、
  fixed selector、sparse config overlay、default↔explicit と file↔CLI provenance、same-value OSC override、
  atomic invalid input、idempotence、screen damage、catalog contrast を検証した。
- 最終 `CI=true DART_SUPPRESS_ANALYTICS=true make test` は exit 0。generated VT parser、parser trace、
  keybinding/action reference、Phase 7 AppKit acceptance、compatibility/differential/application/terminfo gates、
  format/analyze、全 Dart test が成功し、`dart_terminal tests passed` を確認した。
- 最初の staging は sandbox が `.git/index.lock` を作成できず失敗した。working tree は保持されており、
  repository metadata 書き込みを許可した同じ明示 path の `git add` で再実行する。

### 2026-09-10 system appearance live product projection 着手

目的:

- `AppKitApplication.effectiveAppearance` の初期 cache と v7 live event を通常 hierarchy の
  session palette へ接続し、system policy の pane だけを in-place 更新する。

背景と確認済み境界:

- `db51eb5` の完了直後に ROADMAP と本メモを再読し、Dart Terminal と adjacent `dart_appkit` の
  working tree が clean、最初の未完了項目が本サブタスクであることを確認した。
- 通常製品の `configuration()` は immutable な `newSessionConfiguration` を session 作成前に capture し、
  `paneConfigurations` へ pane 単位で保持する。resource disposal は同 map と session/owner map を同時に除去する。
- `AppKitApplication` は appearance event を application stream へ渡す前に `effectiveAppearance` cache を更新する。
  したがって attach 後すでに届いた initial snapshot と、subscription 後に届く snapshot/change の双方を一つの
  application-owned projection で race なく扱える。
- palette mutation は両 screen を dirty にするが、live surface の frame scheduling は
  `_TerminalHierarchyProductPane.notifyScreenChanged()` を明示的に呼ぶ既存経路を必要とする。
- fake AppKit 調査の最初の `rg` は存在しない旧想定 path `packages/appkit/{lib,test}` を指定して exit 2 になった。
  正しい `packages/dart_appkit/{lib,test}` で再実行し、test-only raw event injection と v7 cache-first routing を確認した。
- ADR-001/002 を再確認し、AppKit observation は UI root の短い処理、theme/palette 意味論と damage policy は Dart
  ownership のままにする。PTY、screen、font/atlas、Metal surface、window の再生成や worker 境界変更は行わない。

範囲:

- application-specific projection を追加し、current system brightness、pane key、captured configuration、既存 palette、
  surface notification callback、appearance subscription を単一 owner として管理する。
- pane 作成時はその時点の appearance で palette を生成し、live event は登録済み system pane の既存 palette に
  atomic reset-default batch を適用する。fixed light/dark pane は無変更とする。
- pane resource removal と application shutdown で登録/subscription を解除する。
- fake AppKit raw v7 event を使い、initial light/dark、multi-pane、fixed 非追従、new-session reload 境界、
  palette/screen identity、pane removal、projection disposal を自動検証する。

対象外:

- v7 raw event を packaged Developer JIT / Release AOT へ注入する実 Metal pixel acceptance、runtime manifest、
  README/FEATURE_MATRIX の完了表記、親項目の完了判定。これらは次の順序付きサブタスクで行う。
- config reload による既存 pane の theme policy 変更、OS global preference の変更、view 単位 appearance。

依存関係・リスク:

- initial snapshot が projection 作成前に届いた場合は cache を読み、作成後に届いた場合は owned subscription で扱う。
  Dart の同一 UI isolate 上で constructor 内の cache read と subscription 設置の間に event callback は割り込まない。
- pane 登録後かつ native resource 作成前に event が届いた場合、palette は更新済みとなり、後から attach する surface が
  latest full state を読む。存在しない owner への通知 callback は no-op とする。
- callback の再入で pane が除去されても stale target を続けて呼ばないよう、snapshot iteration と identity check を使う。

完了条件と検証方針:

- fake AppKit product test、focused format/analyze/test、source/reference freshness、aggregate `make test` が成功する。
- appearance 更新後も各 registered palette/screen identity が同一で、system pane の visible change だけが一度 notify され、
  removed/disposed/fixed pane は変化しない。
- accepted reload 後も既存 pane は captured system policy を保持し、新規 pane だけが新しい fixed policy を capture する。

実装・focused 検証:

- `TerminalApplicationThemeProjection<Key>` を application layer に追加した。constructor は cache された
  effective appearance を dark fallback 付きで取得してから typed appearance stream を購読し、pane key ごとに
  creation-time configuration、既存 palette、surface notification callback を保持する。
- pane factory は projection の current appearance から independent palette を生成・登録する。appearance event は
  target snapshot と registration identity を確認しながら既存 palette の reset defaults を更新し、visible change が
  あった system pane だけを一度 notify する。fixed pane、removed pane、disposed projection は変更しない。
- product cleanup は theme subscription/target map を window、text input、surface teardown より先に停止する。個別 pane
  resource removal も theme registration を先に除去し、teardown 中の late appearance から disposed surface を隔離する。
- fake AppKit v7 record を cache seed と live update の両方に使用した。initial light、live dark、dark 中の later system pane、
  accepted system→fixed-light reload、旧 system pane の追従、新 fixed pane の非追従、removed pane、両 screen damage、
  palette/style/scrollback identity、重複 appearance の idempotence、projection disposal 後の無通知を同じ product
  boundary test で確認した。
- focused `dart format`、`dart analyze`、`dart run test/terminal_native_hierarchy_test.dart` は exit 0、analyzer は
  `No issues found!`。最初の Phase 7 AppKit acceptance freshness check は、予想どおり変更した application source と
  fake-AppKit test の reviewed hash が stale になったため停止した。生成差分を確認してから証跡を再生成する。
- `make phase7-appkit-acceptance` の生成差分は `terminal_application.dart` の同一 source hash 2箇所と
  `terminal_native_hierarchy_test.dart` の同一 test hash 4箇所だけであり、criterion、件数、entrypoint、UI evidence は
  変化していない。再生成後の freshness check は aggregate gate 内で成功した。
- 最終 `CI=true DART_SUPPRESS_ANALYTICS=true make test` は exit 0。全 generated reference/acceptance/
  compatibility/differential/application/terminfo gate、223 Dart files の format、analyze、全 test が成功し、
  `dart_terminal tests passed` を確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make runtime-source-check` は
  `DART_ONLY_SOURCE_AUDIT_PASS tracked=417 product_native_sources=0 reviewed_test_native_sources=1` で成功した。
  新しい projection は Dart application layer に留まり、native product source や internal native path を追加していない。

## リスク・引き継ぎ

- KVO observer の登録解除と event-port 再登録で stale callback を残さないことを native test で
  固定する。
- system appearance の変更を自動受け入れする際は global OS preference を変更せず、v7 raw event
  注入で product contract を検証する。native KVO bridge 自体は `dart_appkit` test が担保する。
- light palette の具体値は contrast と既存 ANSI semantics を targeted renderer/palette test で確認し、
  実 Metal pixel acceptance でも背景/前景を固定する。
