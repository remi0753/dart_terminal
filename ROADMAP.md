# Dart Terminal — Ghostty クラス品質への詳細ロードマップ

最終更新: 2026-09-04<br>
対象: macOS 14 以降、Flutter 不使用  
Ghostty 調査基準: `ghostty-org/ghostty` main の
`d4d8f62262cb1a974a7d2470d5f79f811fab15e4`  
ローカル基準: `dart_appkit` の
`be09f1a8e8f9d867cdf8d255fd40586fc9df5cc2`

主要な開発・実機受け入れ baseline は Apple M1/arm64 とする。x86_64 cross-build、
Rosetta compatibility、Universal audit、Intel-native 実機証跡は主要ゴール後の
低優先 follow-up とし、M1 の通常ロードマップを阻害しない。

24/72時間 soak、長時間連続運転など、所要時間そのものを受け入れ条件とする項目は
低優先 follow-up とし、未実施または短いbounded代替検証への置換だけを通常ロードマップの
blockerにしない。短時間でも再現するcorrectness、安全性、resource上限、data lossの失敗は
この例外に含めず、従来どおりblockerとして扱う。

## 1. 目標

macOS 上で日常利用でき、速度、端末互換性、文字品質、入力品質、
ネイティブ UI、安定性、安全性の各面で Ghostty と同じクラスに入る
ターミナルエミュレーターを作る。

「同等」は画面や設定名をコピーすることではない。次を満たすことを指す。

| 品質軸 | 最終的な到達条件 |
| --- | --- |
| 端末互換性 | 一般的な shell、tmux、ssh、Neovim、Emacs、TUI が崩れず、xterm 系の主要 VT シーケンスと現代的プロトコルを扱える |
| 性能 | 大量出力中も入力と AppKit が応答し、表示更新をディスプレイのリフレッシュレートに追従させられる |
| 文字品質 | CoreText によるフォント探索、fallback、ligature、emoji、grapheme cluster、Retina 描画が正しい |
| 入力品質 | US/JIS 配列、dead key、日本語 IME、key repeat、Kitty keyboard、マウス報告、選択、paste が共存する |
| ネイティブ体験 | 複数 window、native tab、split、menu、Quick Terminal、状態復元、VoiceOver、Secure Input を備える |
| 信頼性 | 子プロセス、PTY、GPU、Dart isolate、native handle をリークせず、長時間運転と異常終了に耐える |
| 配布品質 | AOT、Universal Binary、署名、notarization、更新、crash log、明確な privacy 方針を備える |

v1 の対象は macOS のみとする。Linux/Windows 対応、独自 shell の実装、
Ghostty の設定ファイルとの完全互換は、このロードマップの対象外とする。

## 2. 「Dart だけ」の実現可能な定義

### 採用する定義

- 端末 parser、screen model、scrollback、selection、検索、key encoding、
  config、session 管理、window/tab/split の状態管理を Dart で実装する。
- Flutter は使用しない。
- macOS の機能を呼ぶ境界だけ、`dart:ffi` と小さな C ABI を使う。
- AppKit、CoreText、Metal、PTY、code signing は OS の機能を利用する。
- Metal shader は MSL で記述する。端末の意味論は shader 側へ持ち込まない。
- Ghostty や `libghostty` を製品へ link しない。テスト時の比較対象としてのみ使う。

### 文字どおり 100% Dart source にできない理由

Ghostty クラスの macOS アプリには、少なくとも次の native 境界が必要になる。

1. AppKit の `NSApplication` と main run loop
2. `forkpty(3)` / `openpty(3)`、`ioctl(TIOCSWINSZ)`、process group、signal
3. `MTKView` / `CAMetalLayer` と Metal command submission
4. CoreText の font discovery、shaping、fallback、glyph rasterization
5. `NSTextInputClient` による marked text と IME candidate 座標
6. `NSPasteboard`、VoiceOver、Secure Event Input、Apple Events
7. Dart VM の embed、AOT snapshot、署名済み `.app` bundle

Objective-C runtime と libc をすべて Dart FFI から直接呼ぶ構成も理論上は可能だが、
AppKit subclass、callback、fork 後の安全性、thread affinity、ABI 変更への耐性が弱い。
そのため、native 側は「OS adapter」、Dart 側は「製品ロジック」という境界を守る。

### 境界の品質ルール

- C ABI は opaque handle と固定幅整数だけを基本にする。
- cell ごとの FFI 呼び出しは禁止し、byte batch、damage list、draw list 単位にする。
- native から Dart への同期 re-entry を避け、Dart port へ immutable event を送る。
- fork した child 側では async-signal-safe な処理と `execve` だけを実行する。
- AppKit API は main thread、Metal resource は明示した render domain、PTY は I/O domain に限定する。
- 所有権、thread、失敗、cancel、shutdown の契約を全 ABI 関数に記載する。

## 3. 現在地と差分

現行 `dart_terminal` は、`dart_appkit` の `Window` と単一 `TextView` を使い、
入力したコマンドごとに `/bin/zsh -lc` を起動する command console である。

| 層 | 現在 | Ghostty クラスに必要な状態 | 主な差分 |
| --- | --- | --- | --- |
| Runtime | 未改変 AppKit root、Developer は公式 Dart process worker | AOT 配布、debug/release 分離、複数の独立 worker domain | stock AOT host、process lifecycle、crash handling |
| Process | コマンドごとに `Process.start` | 1 pane = 1 persistent PTY session | controlling TTY、job control、resize、signals |
| Terminal core | plain string の履歴 | byte streaming parser と完全な grid state | VT parser、modes、scrollback、reflow |
| Renderer | AppKit が 18pt の plain text を再描画 | Metal、CoreText、glyph atlas、damage rendering | 専用 view と GPU pipeline |
| Input | key down の文字列と一部 key code | IME、layout、protocol-aware encoding、mouse | `NSTextInputClient`、key encoder、selection |
| UI | 1 window / 1 view | windows、tabs、splits、menus、restoration | AppKit API surface と app state model |
| Configuration | 起動引数 2 個 | schema、themes、keybinds、hot reload、settings | config engine 全体 |
| Compatibility | 独自 model test | VT conformance、differential、real-app matrix | corpus、fuzz、PTY integration harness |
| Distribution | developer `.app`、arm64 JIT | AOT、arm64/x86_64、signed/notarized release | release toolchain 全体 |

この差分は `TextView` の機能追加だけでは埋まらない。端末 core、platform adapter、
renderer、application shell を独立した層として作る必要がある。

## 4. 目標アーキテクチャ

```text
macOS process
├─ AppKit main thread
│  └─ Dart UI root isolate
│     ├─ application/window/tab/split model
│     ├─ menu, command palette, settings, restoration
│     ├─ input routing and focus
│     └─ session/render worker coordination
│
├─ native PTY reactor
│  ├─ safe forkpty + execve
│  ├─ kqueue/GCD read readiness
│  ├─ ordered write queue + backpressure
│  └─ resize/signal/waitpid
│
├─ one Dart terminal-engine isolate per active pane
│  ├─ UTF-8 + VT parser
│  ├─ primary/alternate screen and scrollback
│  ├─ mode/query/reply state
│  ├─ selection/search/semantic prompt state
│  └─ compact damage generation
│
├─ one Dart render coordinator isolate per window
│  ├─ damage coalescing
│  ├─ glyph/attribute run preparation
│  ├─ atlas requests
│  └─ packed Metal draw-list submission
│
└─ native TerminalMetalView
   ├─ MTKView/CAMetalLayer lifecycle
   ├─ CoreText font and glyph services
   ├─ glyph/image texture atlases
   ├─ Metal pipelines and frame presentation
   └─ last committed frame when Dart has no new damage
```

### Isolate 間の原則

- UI isolate は AppKit と軽い state coordination だけを行う。
- terminal-engine isolate だけがその pane の mutable terminal state を所有する。
- PTY output は大きめの byte batch として engine isolate へ渡す。
- engine から renderer へは全画面 object graph ではなく packed damage を渡す。
- `TransferableTypedData` または native double buffer を計測して選ぶ。
- 1 cell = 1 Dart object にはしない。hot path は typed data と index を使う。
- renderer が遅い場合は中間 frame を捨て、最新 state を優先する。
- paste や PTY write は bounded queue と high/low water mark を持つ。

### 推奨パッケージ境界

```text
dart_terminal/
├─ app/ or lib/src/app/                 macOS application state
├─ packages/
│  ├─ terminal_core/                    Dart-only parser/grid/scrollback
│  ├─ terminal_input/                   key/mouse/paste encoding
│  ├─ terminal_config/                  schema/theme/keybind
│  ├─ terminal_protocol_test/           corpus/oracles/fuzz harness
│  └─ terminal_platform_macos/          Dart FFI facade
├─ native/macos/
│  ├─ pty/                              PTY/process adapter
│  ├─ renderer/                         CoreText/Metal adapter + shaders
│  └─ integration/                      IME/pasteboard/accessibility
└─ test/, benchmark/, integration_test/

dart_appkit/
└─ generic AppKit primitives only       window/view/menu/tab/input lifecycle
```

PTY や terminal shader は汎用 AppKit API ではないため `dart_appkit` へ混ぜない。
一方、menu、pasteboard、screen、window focus、backing scale、IME-capable custom view
など再利用可能な機能は `dart_appkit` を拡張して提供する。

## 5. 必要機能の完全な棚卸し

優先度は次の意味とする。

- **P0**: daily-driver alpha に必須
- **P1**: rich beta と Ghostty クラス評価に必須
- **P2**: parity polish。P0/P1 の品質を落とさず追加する

### 5.1 PTY、process、session lifecycle

#### P0

- `forkpty`/`openpty`、controlling terminal、session、foreground process group
- shell を shell string ではなく `argv` と `envp` で起動
- login shell、任意 command、initial cwd、locale、`TERM`、`COLORTERM`
- master FD の nonblocking read/write、partial read/write、`EINTR`、`EAGAIN`
- byte ordering を守る write queue と paste backpressure
- pixel/cell size を含む `winsize` と `SIGWINCH`
- child exit、EOF、SIGHUP、SIGTERM、強制終了、zombie 回収
- Control-C/Z/\、EOF が line editor ではなく PTY へ正しく届くこと
- foreground/background job、`fg`/`bg`、`stty`、`tty` の正常動作
- pane close と app quit 時の確認、grace period、resource cleanup

#### P1/P2

- current working directory と foreground process の検出
- macOS launch services / `open` から渡された file/cwd の扱い
- SSH 用 terminfo 補助、remote fallback
- reconnectable session は P2 の独立プロジェクトとする

### 5.2 Streaming decoder と VT parser

#### P0

- chunk 境界をまたぐ UTF-8 decoder、不正 byte の deterministic な扱い
- C0/C1 control、ESC、CSI、OSC、DCS、APC の incremental state machine
- CAN/SUB/ESC による sequence cancel と parser recovery
- parameter/intermediate/subparameter、colon form SGR
- payload、parameter 数、numeric overflow への上限
- parser hot path では `String`、`RegExp`、例外、per-byte allocation を避ける
- byte stream から action への table-driven parser

#### P1

- 8-bit C1、legacy charset、DEC special graphics
- unknown sequence の安全な無視と inspector trace
- sequence ごとの compatibility quirk を parser と分離
- corpus fuzzing と coverage-guided native boundary fuzzing

### 5.3 Terminal screen model

#### P0

- primary/alternate screen、cursor save/restore、cursor shape/blink/visibility
- wrap pending、origin、insert、replace、auto-wrap、reverse video mode
- top/bottom と left/right margin、scroll region
- cursor movement、erase、insert/delete char/line、scroll up/down
- tab stop、backspace、CR/LF/IND/RI/NEL
- SGR: bold、faint、italic、underline variants、blink state、inverse、conceal、strike
- 16/256/truecolor、default foreground/background、palette mutation
- wide cell、continuation cell、combining mark、zero-width grapheme
- primary/alternate buffer の resize と reflow
- bounded paged scrollback と viewport offset
- dirty row/range と monotonically increasing generation

#### P1

- underline color、overline、protected cells、selective erase
- hyperlink ID、semantic prompt mark、command/output region
- search index、selection anchor、word/line semantic boundaries
- scrollback compression、memory pressure 時の eviction
- screen snapshot/restore を test/debug 用に提供

### 5.4 Queries、modes、terminal capability

#### P0

- DA/DA2、DSR、cursor position report、DEC private mode
- application cursor/keypad、bracketed paste、focus reporting
- mouse modesと encodings: X10、UTF-8、URXVT、SGR
- DECRQM など、主要アプリが問い合わせる mode report
- `xterm-256color` 互換から始める暫定 terminfo

#### P1

- project 固有 terminfo と capability audit
- XTGETTCAP、DECRQSS、window/size reports
- Kitty keyboard protocol と progressive enhancement
- synchronized output/rendering
- light/dark mode notification
- in-band size report と Unicode version negotiation の調査

### 5.5 OSC/DCS/APC と modern protocols

#### P0

- window/tab title
- OSC 7 current working directory
- OSC 8 hyperlink
- palette/default color query と変更
- OSC 52 clipboard は default-deny または確認付き
- desktop notification、progress、prompt markers は bounded parser で扱う

#### P1

- Kitty graphics protocol: direct、file、temporary file、shared memory transport のうち
  macOS で必要なものから実装
- image placement、z-index、scroll/erase、animation、storage limit
- image decode を main/UI isolate から分離
- synchronized rendering 中の timeout と memory upper bound

#### P2

- Sixel は compatibility 要求と利用実績を確認してから追加
- custom shader は安全な compile/cache/disable 経路を設計後に検討

### 5.6 Unicode、font、text shaping

#### P0

- Unicode grapheme break、emoji ZWJ、variation selector、regional indicator
- East Asian width、ambiguous width policy、combining sequence
- CoreText font discovery と fallback
- regular/bold/italic/bold-italic、synthetic style の policy
- cell metrics、baseline、underline/strikethrough position
- monochrome glyph、color emoji、symbol font の atlas
- 1x/2x/scale change、font size zoom、Retina pixel alignment
- CJK、Powerline、box drawing、Nerd Font の golden corpus

#### P1

- ligature と OpenType feature の on/off
- variable font axes
- font codepoint override と fallback diagnostics
- grapheme 内の Arabic/Hebrew shaping。ただし layout は左から右を初期範囲とする
- synthetic box/block glyph による cell gap 防止
- font cache invalidation と system font change

### 5.7 Metal renderer

#### P0

- `MTKView`/`CAMetalLayer` lifecycle、drawable resize、backing scale
- background、cell background、glyph、decoration、cursor、selection の pipeline
- instanced quad と packed attribute buffer
- monochrome/color glyph atlas、allocation、eviction、generation validation
- dirty row/cell のみ更新し、draw request を frame 単位で coalesce
- double/triple buffering と in-flight resource ownership
- vsync/frame pacing、occlusion 時停止、再表示時 full redraw
- cursor blink、visual bell、IME preedit overlay
- deterministic screenshot path と CPU/reference renderer
- device loss、shader compile failure、drawable unavailable の復旧

#### P1

- image layers、hyperlink hover、search overlay、inspector overlay
- sRGB/Display P3 と alpha blending policy
- transparency、background blur は readability と power cost を測定して導入
- 120 Hz、複数 window、複数 pane での fair scheduling

### 5.8 Keyboard、IME、mouse、selection、clipboard

#### P0

- physical key code、produced text、modifier、repeat を別情報として扱う
- US/JIS と layout 切替、dead key、function/navigation/keypad
- terminal mode に応じた xterm key encoding
- `NSTextInputClient`: marked text、commit、cancel、replacement range、candidate rect
- 日本語 IME、emoji picker、Unicode Hex Input の手動/自動テスト
- character/word/line selection、multi-click、drag、auto-scroll
- trackpad の precision/momentum scroll と wheel
- app mouse reporting と local selection の modifier override
- standard clipboard、copy/paste、bracketed paste、改行正規化
- multiline/control-character paste confirmation と large paste throttling
- configurable keybind、macOS menu shortcut と terminal input の競合解決

#### P1/P2

- Kitty keyboard、modifyOtherKeys、disambiguated escape codes
- Option-click cursor positioning と shell integration
- semantic prompt/output selection、jump-to-prompt
- drag and drop、Services、Quick Look、link context menu
- command palette と searchable action registry

### 5.9 Window、tab、split、native macOS experience

#### P0

- multiple windows、native tabs、split tree、focus traversal
- split resize/equalize/zoom、minimum cell size
- tab title/color、pane title、working directory inheritance
- fullscreen、window geometry、screen/backing scale changes
- close confirmation と active process detection
- standard menu bar、Edit/Window/Shell/View actions
- reopen、window/session state restoration

#### P1

- Quick Terminal、global shortcut、animation、screen selection
- proxy icon と represented URL
- system appearance に連動した light/dark theme
- Secure Keyboard Entry と明確な indication
- AppleScript object model: application → windows → tabs → terminals
- App Intents/Shortcuts、notifications、dock badge
- settings GUI、command palette、terminal inspector

#### P2

- automatic update、release notes、update rollback
- custom window/titlebar styles は accessibility を維持できる範囲に限定

### 5.10 Configuration、themes、shell integration

#### P0

- typed schema、default、file、CLI override の優先順位
- location と include、parse error の file/line/column
- color palette、font、padding、scrollback、cursor、shell、cwd
- keybind action registry、conflict detection、unbound/passthrough
- config reload と、既存 pane に適用可能/不可能な項目の区別
- user config がなくても妥当な zero-config default

#### P1

- light/dark theme pair、custom theme、built-in theme catalog
- deprecated option と migration warning
- zsh/bash/fish/nushell への shell integration injection
- prompt mark、cwd、title、cursor shape、close-confirmation hint
- SSH 時の `TERM`/terminfo fallback
- config diagnostics UI と `+show-config` 相当の CLI

### 5.11 Accessibility、localization、privacy

#### P0

- terminal custom view の visible text、selection、cursor、focused state を VoiceOver へ公開
- text/value/selection change notification
- Full Keyboard Access と keyboard-only 操作
- Reduce Motion、Increase Contrast、Differentiate Without Color
- IME preedit と accessibility selection の整合
- crash data、update check、clipboard、shell integration の privacy 文書

#### P1

- UI text localization、RTL UI、date/number locale
- Accessibility Inspector と VoiceOver の release checklist
- AppleScript/TCC permission の説明と無効化設定

### 5.12 Security と resource limit

- OSC/DCS/APC payload、CSI parameters、image count/bytes、scrollback、hyperlink table に上限
- malformed UTF-8/sequence/image で parser が停止、loop、巨大 allocation しない
- OSC 52 read/write policy、paste confirmation、notification rate limit
- URL scheme allowlist と hyperlink sanitization
- image decompression bomb、path traversal、temporary file lifetime への防御
- command 起動は shell interpolation せず `argv`/`envp` を使う
- child process と process group の所有権を追跡
- Secure Input が crash 後も有効になり続けない teardown
- native ABI を ASan/UBSan、Dart core を fuzz/property test で検査
- app signing、hardened runtime、notarization、entitlements の最小化

## 6. データ構造と hot-path 方針

### Cell/grid

- Struct of Arrays を基本とし、`Uint32List`/`Uint16List`/`Uint8List` を使う。
- codepoint/grapheme index、style index、foreground、background、width/flags を分離する。
- grapheme、style、hyperlink は intern table に置き、cell は小さい index を持つ。
- row は version、dirty start/end、wrap metadata、semantic mark を持つ。
- scrollback は固定 page の deque とし、先頭削除で全要素を移動しない。
- image と hyperlink は refcount と generation を持つ。

### Parser

- input は `Uint8List` の slice と current state/index で処理する。
- dispatch table は生成物にし、手書き switch の drift を防ぐ。
- printable ASCII の fast path と UTF-8/control の slow path を分ける。
- reply は engine isolate から bounded PTY write queue へ byte として返す。
- debug trace は compile/runtime flag で完全に hot path から外せるようにする。

### Render transfer

- engine は dirty row の packed cells と changed resource IDs だけを送る。
- renderer は最新 generation より古い damage を破棄できる。
- full snapshot は resize、atlas reset、device recovery のときだけ送る。
- Dart → native は 1 frame あたり少数の coarse FFI call に制限する。
- buffer lifetime は submit token/fence で管理し、GPU 完了前に再利用しない。

## 7. 段階別ロードマップ

工数は経験者 1 人の person-week の幅で、仕様調査、実装、テスト、文書を含む。
未知部分が多いため日付の約束ではなく、planning range として扱う。

### Phase 0 — Feasibility gate と仕様凍結（3–5 person-weeks）

目的: 長期開発に入る前に、Dart/VM/macOS 境界の致命的リスクを潰す。

- [x] Ghostty pinned commit を基準に `FEATURE_MATRIX.md` を作る
- [x] ADR-001: Dart/native boundary
- [x] ADR-002: isolate/thread/ownership model
- [x] ADR-003: packed cell/grid format
- [x] ADR-004: renderer submission と buffer lifetime
- [x] release AOT snapshot を AppKit main-thread root isolate で起動する spike
- [x] root isolate から長寿命 worker isolate を起動・停止する spike
- [x] `forkpty` → interactive zsh → resize → signal → exit の native spike
- [x] PTY output を 64 KiB 以上の batch で Dart port へ送る spike
- [x] `MTKView` に 10 万 glyph instance を継続描画する spike
- [x] CoreText で Latin/CJK/emoji/ligature の glyph run を得る spike
- [x] `NSTextInputClient` で日本語 marked text と candidate rect を確認
- [x] parser/render/input latency の benchmark harness を先に作る

終了条件:

- AOT、PTY、Metal、CoreText、IME、worker isolate の全 spike が実機で通る。
- main run loop を 4 ms 以上連続占有する設計が残っていない。
- PTY child path が fork 後に Dart runtime や Objective-C allocation を呼ばない。
- 目標性能を満たせない場合に native 側へ移す処理の境界が ADR に書かれている。
- 1 項目でも成立しなければ、機能開発へ進まず制約を再検討する。

Phase 0 の統合受け入れ記録と debug/release/Universal CI 契約は
[`docs/phase0/DT-012-build-ci-design.md`](docs/phase0/DT-012-build-ci-design.md)
に固定する。2026-09-01 の arm64 実機検証では `make phase0-verify` が全 gate
を通過した。Universal 実体の構築は下記 Phase 1 の対象であり、Phase 0 では
arm64-only bundle を Universal と扱わない監査までを受け入れた。

### Phase 1 — Release-grade runtime と platform substrate（6–10 person-weeks）

目的: 現在の hello-window 用 `dart_appkit` を製品の土台へする。

- [x] debug JIT と release AOT の build/run path を分離
- [x] arm64/x86_64 の build matrix と Universal Binary 組み立て（M1-native、
  Rosetta x86_64 compatibility、Universal audit。詳細は
  [`docs/phase1/universal-runtime-matrix.md`](docs/phase1/universal-runtime-matrix.md)）
- [x] VM/isolate の起動、error、uncaught exception、shutdown contract
- [x] 公開・未改変の Dart だけを使う runtime hosting へ移行する（順序と
  判定基準は [`docs/phase1/stock-dart-runtime-migration-plan.md`](docs/phase1/stock-dart-runtime-migration-plan.md)
  を正本として固定する）
  - [x] 不変条件、既存証拠、責務境界、受け入れ条件を正規化する
  - [x] `dart_api.h` 公開境界だけで VM 全体を所有する `dart_appkit` host を M1/arm64 JIT/AOT で実証し採否を確定する
  - [x] 固定判定基準を一度だけ適用し、採用 topology と実装所有者を確定する
  - [x] 選定された `dart_appkit` host contract を実装して回帰試験を通す
  - [x] M1/arm64 Developer JIT 製品を選定 contract へ移行する
    - [x] versioned process protocol と process-owned lifecycle coordinator を実装し、公開 Dart 実行ファイルで unit contract を通す
    - [x] clean SDK を必須にした Developer worker Kernel・bundle・provenance/audit 経路へ移す
    - [x] M1 Developer GUI/lifecycle/failure/backpressure 統合試験を通し、移行記録を閉じる
  - [x] M1/arm64 Release AOT 製品を同じ contract へ移行する
    - [x] clean Product Engine、公式 self-contained AOT worker、host-owned launch、bundle/sign 経路へ移す
    - [x] Release manifest/audit/freshness/negative gate を clean process-worker contract へ移す
    - [x] M1 Release GUI/lifecycle/failure/backpressure/PID 統合試験を通し、移行記録を閉じる
  - [x] patch 本体、適用処理、hash・来歴・監査・fixture をすべて削除する
    - [x] patch payload と SDK 変更 Make 経路を削除し、patch 前提の Phase 0 isolate 実行入口を廃止する
    - [x] patch 専用の hash・来歴・status allowance・composition 監査・fixture を clean official contract へ整理する
    - [x] 現行文書と source inventory を更新し、M1 回帰・clean SDK を確認して patch 削除を閉じる
  - [x] M1 の JIT/AOT 横断 lifecycle、性能、終了順序、clean SDK を検証して移行を閉じる
- [x] native event wire format の versioning と backward compatibility
- [x] handle registry に thread-domain と asynchronous destruction を追加
- [x] generic `View`、focus、visibility、occlusion、backing scale、screen event
  （分割と完了条件は
  [`docs/phase1/generic-view-window-state-events.md`](docs/phase1/generic-view-window-state-events.md)
  を参照して実施する）
  - [x] generic `View` の型・所有権・create/attach ABI と Dart facade
  - [x] event protocol v3 と focus/visibility/occlusion/backing-scale/screen event
  - [x] Dart Terminal の M1 Developer JIT / Release AOT 統合受け入れ
- [x] menu、pasteboard、application/window lifecycle API
  （分割と完了条件は
  [`docs/phase1/menu-pasteboard-lifecycle-apis.md`](docs/phase1/menu-pasteboard-lifecycle-apis.md)
  を参照して実施する）
  - [x] event protocol v4 と opt-in application/window lifecycle request/reply
  - [x] general pasteboard plain-text snapshot/write/clear API
  - [x] menu/menu-item ownership/action API と main-menu attachment
  - [x] Dart Terminal の M1 Developer JIT / Release AOT 統合受け入れ
- [x] TerminalMetalView を attach できる generic custom-view boundary
  （分割と完了条件は
  [`docs/phase1/terminal-metal-view-boundary.md`](docs/phase1/terminal-metal-view-boundary.md)
  を参照して実施する）
  - [x] `dart_appkit` の registered custom-view provider と Dart `View` factory
  - [x] terminal-owned `TerminalMetalView` shell と native attachment contract
  - [x] Dart Terminal の M1 Developer JIT / Release AOT 統合受け入れ
- [x] macOS unified logging と local crash metadata
  （分割と完了条件は
  [`docs/phase1/macos-unified-logging-crash-metadata.md`](docs/phase1/macos-unified-logging-crash-metadata.md)
  を参照して実施する）
  - [x] native unified logger と bounded local-run metadata contract
  - [x] Dart lifecycle phase と Developer JIT / Release AOT host integration
  - [x] M1 product acceptance と privacy/operations documentation
- [x] native/Dart の resource leak test と shutdown fault injection
  （分割と完了条件は
  [`docs/phase1/resource-leak-shutdown-fault-injection.md`](docs/phase1/resource-leak-shutdown-fault-injection.md)
  を参照して実施する）
  - [x] product resource-leak stress gate
  - [x] bounded shutdown fault injection
  - [x] M1/arm64 acceptance と Phase 1 closeout

終了条件:

- AOT `.app` が起動し、root UI isolate と独立して回収可能な公式 Dart worker
  process が共存する。
- 1000 回の window/view create-destroy で native handle が増えない。
- malformed event、late event、double dispose、worker crash で app 全体が hang しない。
- debug と release が同じ integration suite を通る。

### Phase 2 — Persistent PTY vertical slice（5–8 person-weeks）

目的: command console を本物の terminal session へ置き換える。

- [x] Dart-only application packaging boundary の目標、成果物、依存順、受け入れ条件を
  固定する（以後の7項目は
  [`docs/phase2/dart-only-application-packaging.md`](docs/phase2/dart-only-application-packaging.md)
  を参照して順に実施する）
- [x] ADRで generic macOS runtime、AppKit、native capability、Dart application の
  所有境界を確定する
- [x] `dart_macos_runtime` へ共通 Developer JIT / Release AOT host、lifecycle、
  diagnostics、bundle assembly を抽出する
- [x] versioned native asset/plugin 登録を hello-window で実証する
- [x] `TerminalMetalView` を terminal renderer capability package へ移す
- [x] Phase 2 PTYを `dart_pty_macos` capability package として実装する
- [x] `dart_terminal` から product native 実装と隣接 repository の内部 source 参照を
  除去し、Dart application sourceだけで両runtime modeを構築・検証する
- [x] stable `dpty_*` C ABI と Dart facade
- [x] argv/env/cwd/login shell の安全な spawn
- [x] kqueue reactor、read batching、write queue、backpressure
- [x] `winsize`、SIGWINCH、process group、waitpid、exit event
- [x] Ctrl-C/Z/\、EOF、HUP、graceful/forced close
- [x] session ID と pane ownership、close confirmation state
  （分割と完了条件は
  [`docs/phase2/persistent-pane-lifecycle.md`](docs/phase2/persistent-pane-lifecycle.md)
  を参照して順に実施する）
  - [x] persistent pane lifecycle の範囲、状態遷移、受け入れ条件を固定する
  - [x] pane/session identity、単一owner、close policyをDart modelとして実装する
  - [x] commandごとのPTYをpane-owned persistent login shellへ置き換える
  - [x] AppKit close確認、実PTY、Developer JIT / Release AOT受け入れを閉じる
- [x] fake PTY backend と deterministic integration harness
- [x] Ctrl-D / PTY shutdown hang の bounded recovery
  （分割と完了条件は
  [`docs/phase2/ctrl-d-pty-shutdown-recovery.md`](docs/phase2/ctrl-d-pty-shutdown-recovery.md)
  を参照して順に実施する）
  - [x] Ctrl-D natural exit を繰り返す実PTY回帰試験
  - [x] pane / PTY shutdown stage のprivacy-safe診断
  - [x] closing中も有効なidempotent force-close capability
  - [x] missing exit / reap callbackに対するfinal deadline
  - [x] deadline超過後も完了するclassified application termination
- [x] AppKit key event routing policy とterminal専有入力
  （分割と完了条件は
  [`docs/phase2/exclusive-key-event-routing.md`](docs/phase2/exclusive-key-event-routing.md)
  を参照して順に実施する）
  - [x] `dart_appkit`に選択可能なkey event routing capabilityを追加する
  - [x] `dart_terminal`をDart専有入力へ切り替え、GUI回帰を検証する
- [x] Ctrl-D write受理後のPTY停止原因を分離する
  （実施時に
  [`docs/phase2/ctrl-d-accepted-no-exit-investigation.md`](docs/phase2/ctrl-d-accepted-no-exit-investigation.md)
  を参照する）
- [x] Dart `Process.start` workerとnative PTY childのreap ownership競合を解消する
  （実施時に
  [`docs/phase2/pty-child-reap-ownership-conflict.md`](docs/phase2/pty-child-reap-ownership-conflict.md)
  を参照する）
  - [x] `dart_pty_macos`でkernel exit statusを保持し、外部reap後も終了を一度だけ公開する
  - [x] clean shell exitとabnormal shell exitのpane/window policyを実装し、runtime workerとの同時生存回帰を閉じる

終了条件:

- `tty` が pseudo-terminal を返す。
- `stty size` が window resize に追従する。
- zsh の interactive prompt、job control、`fg`/`bg` が動く。
- 10 MiB burst、partial UTF-8、child crash、window close を失敗なく処理する。
- UI main isolate は PTY read/write 待ちで block しない。

### Phase 3 — Dart-only VT core（12–18 person-weeks）

目的: 描画とは独立した、deterministic で fuzz 可能な terminal state machine を作る。

- [x] streaming UTF-8 decoder と parser table generator
- [x] C0/ESC/CSI/OSC/DCS/APC parser
- [x] typed-array grid、cursor、margins、tabstops、modes
  - [x] typed-array cell/row storage、cursor/save、tabstop、damage基盤
    （[`docs/phase3/typed-array-grid-screen-state.md`](docs/phase3/typed-array-grid-screen-state.md) を参照して実施）
  - [x] margins、screen modes、reset/clamp invariant
    （[`docs/phase3/typed-array-grid-screen-state.md`](docs/phase3/typed-array-grid-screen-state.md) を参照して実施）
  - [x] cursor/edit/scroll operations と parser action sink
    （[`docs/phase3/typed-array-grid-screen-state.md`](docs/phase3/typed-array-grid-screen-state.md) を参照して実施）
- [x] SGR、palette、primary/alternate screen
  - [x] style table、rendition state、SGR application
    （[`docs/phase3/sgr-palette-primary-alternate-screen.md`](docs/phase3/sgr-palette-primary-alternate-screen.md) を参照して実施）
  - [x] xterm-256 palette、default color、OSC color mutation
    （[`docs/phase3/sgr-palette-primary-alternate-screen.md`](docs/phase3/sgr-palette-primary-alternate-screen.md) を参照して実施）
  - [x] primary/alternate screen owner と DEC 47/1047/1048/1049
    （[`docs/phase3/sgr-palette-primary-alternate-screen.md`](docs/phase3/sgr-palette-primary-alternate-screen.md) を参照して実施）
- [x] wide/grapheme cells と resize/reflow
  - [x] Unicode 17 properties、grapheme breaker、bounded intern table
    （[`docs/phase3/wide-grapheme-resize-reflow.md`](docs/phase3/wide-grapheme-resize-reflow.md) を参照して実施）
  - [x] wide/continuation/grapheme mutation invariant
    （[`docs/phase3/wide-grapheme-resize-reflow.md`](docs/phase3/wide-grapheme-resize-reflow.md) を参照して実施）
  - [x] primary/alternate resize と visible logical-line reflow
    （[`docs/phase3/wide-grapheme-resize-reflow.md`](docs/phase3/wide-grapheme-resize-reflow.md) を参照して実施）
- [x] paged scrollback、viewport、selection/search primitives
  - [x] fixed-page bounded scrollback storage と primary full-screen capture
    （[`docs/phase3/paged-scrollback-viewport-selection-search.md`](docs/phase3/paged-scrollback-viewport-selection-search.md) を参照して実施）
  - [x] history/screen viewport offset と alternate-screen isolation
    （[`docs/phase3/paged-scrollback-viewport-selection-search.md`](docs/phase3/paged-scrollback-viewport-selection-search.md) を参照して実施）
  - [x] scrollback-aware resize/reflow と stable logical anchors
    （[`docs/phase3/paged-scrollback-viewport-selection-search.md`](docs/phase3/paged-scrollback-viewport-selection-search.md) を参照して実施）
  - [x] selection extraction、word/line semantics、bounded search
    （[`docs/phase3/paged-scrollback-viewport-selection-search.md`](docs/phase3/paged-scrollback-viewport-selection-search.md) を参照して実施）
- [x] query/reply encoder と PTY write connection
  - [x] bounded reply encoder と terminal-core query dispatch
    （[`docs/phase3/query-reply-pty-write.md`](docs/phase3/query-reply-pty-write.md) を参照して実施）
  - [x] raw parser feed と bounded PTY reply connection
    （[`docs/phase3/query-reply-pty-write.md`](docs/phase3/query-reply-pty-write.md) を参照して実施）
- [x] snapshot formatter と readable test diagnostics
  - [x] bounded versioned terminal-state formatter
    （[`docs/phase3/snapshot-formatter-test-diagnostics.md`](docs/phase3/snapshot-formatter-test-diagnostics.md) を参照して実施）
  - [x] bounded comparison diagnostics と shared test oracle
    （[`docs/phase3/snapshot-formatter-test-diagnostics.md`](docs/phase3/snapshot-formatter-test-diagnostics.md) を参照して実施）
- [x] parser corpus、property tests、fuzz seeds
  - [x] bounded product corpus manifest と replay harness
    （[`docs/phase3/parser-corpus-property-fuzz.md`](docs/phase3/parser-corpus-property-fuzz.md) を参照して実施）
  - [x] recorded shell、less、top、vim streams
    （[`docs/phase3/parser-corpus-property-fuzz.md`](docs/phase3/parser-corpus-property-fuzz.md) を参照して実施）
  - [x] deterministic property tests と fuzz seed corpus
    （[`docs/phase3/parser-corpus-property-fuzz.md`](docs/phase3/parser-corpus-property-fuzz.md) を参照して実施）
  - [x] product parser Release AOT throughput と Phase 3 exit audit
    （[`docs/phase3/parser-corpus-property-fuzz.md`](docs/phase3/parser-corpus-property-fuzz.md) を参照して実施）

終了条件:

- shell prompt、`less`、`top`、`vim` の記録 stream を期待 snapshot に再生できる。
- byte chunk を全分割位置で変えても final state が一致する。
- malformed/巨大 sequence で上限を越えず、次の printable text へ復帰する。
- baseline machine で parser throughput の provisional budget を満たす。
- core package は AppKit、Metal、FFI に依存しない。

### Phase 4 — CoreText + Metal renderer（12–20 person-weeks）

目的: correctness reference を持つ高速 renderer を実装する。

- [x] headless/reference renderer と golden image format
  - [x] bounded headless RGBA surface と reference layer compositor
    （[`docs/phase4/reference-renderer-golden-format.md`](docs/phase4/reference-renderer-golden-format.md) を参照して実施）
  - [x] versioned golden image codec、fixture、bounded comparison diagnostics
    （[`docs/phase4/reference-renderer-golden-format.md`](docs/phase4/reference-renderer-golden-format.md) を参照して実施）
- [x] CoreText font catalog、fallback、metrics、shaping cache
  - [x] versioned font catalog、style/fallback resolution、cell metrics
    （[`docs/phase4/coretext-font-shaping.md`](docs/phase4/coretext-font-shaping.md) を参照して実施）
  - [x] bounded CoreText run shaping と Dart-owned LRU shaping cache
    （[`docs/phase4/coretext-font-shaping.md`](docs/phase4/coretext-font-shaping.md) を参照して実施）
- [x] monochrome/color glyph atlas
  - [x] bounded batched CoreText monochrome/color glyph raster ABI
    （[`docs/phase4/glyph-raster-atlas.md`](docs/phase4/glyph-raster-atlas.md) を参照して実施）
  - [x] Dart-owned dual atlas pages、growth/LRU eviction、generation validation、text goldens
    （[`docs/phase4/glyph-raster-atlas.md`](docs/phase4/glyph-raster-atlas.md) を参照して実施）
- [x] Metal cell/glyph/decoration/cursor/selection pipelines
  - [x] packed native pipeline、precompiled shader、atlas texture capability
    （[`docs/phase4/metal-pipelines.md`](docs/phase4/metal-pipelines.md) を参照して実施）
  - [x] view-bound triple-buffer submission、GPU completion ownership、presentation
    （[`docs/phase4/metal-pipelines.md`](docs/phase4/metal-pipelines.md) を参照して実施）
  - [x] Dart encoder/facade、atlas bridge、CPU/GPU 1x/2x goldens
    （[`docs/phase4/metal-pipelines.md`](docs/phase4/metal-pipelines.md) を参照して実施）
- [x] damage coalescing、frame generation、stale-frame discard
  - [x] strict damage codec と retained render model
    （[`docs/phase4/damage-frame-coordinator.md`](docs/phase4/damage-frame-coordinator.md) を参照して実施）
  - [x] 100,000-cell product damage capture/transfer の Release AOT gate
    （[`docs/phase4/damage-capture-performance.md`](docs/phase4/damage-capture-performance.md) を参照して実施）
  - [x] one-in-flight TransferableTypedData outbox と exact ACK
    （[`docs/phase4/damage-frame-coordinator.md`](docs/phase4/damage-frame-coordinator.md) を参照して実施）
  - [x] newest-model frame scheduler と native outcome connection
    （[`docs/phase4/damage-frame-coordinator.md`](docs/phase4/damage-frame-coordinator.md) を参照して実施）
- [x] resize/scale/font change の full rebuild
  - [x] coalesced rebuild state と full-snapshot epoch ownership
    （[`docs/phase4/resize-scale-font-rebuild.md`](docs/phase4/resize-scale-font-rebuild.md) を参照して実施）
  - [x] CoreText/atlas/Metal resource rebuild integration
    （[`docs/phase4/resize-scale-font-rebuild.md`](docs/phase4/resize-scale-font-rebuild.md) を参照して実施）
- [x] cursor blink、visual bell、occlusion pause
  - [x] cursor/BEL presentation metadata を strict damage protocol へ追加
    （[`docs/phase4/cursor-bell-occlusion.md`](docs/phase4/cursor-bell-occlusion.md) を参照して実施）
  - [x] bounded animation clock と visibility/occlusion frame scheduling
    （[`docs/phase4/cursor-bell-occlusion.md`](docs/phase4/cursor-bell-occlusion.md) を参照して実施）
- [x] device/shader/drawable failure recovery
  - [x] typed native Metal failure state と drawable retry contract
    （[`docs/phase4/metal-failure-recovery.md`](docs/phase4/metal-failure-recovery.md) を参照して実施）
  - [x] renderer recreation、atlas republish、full-redraw coordination
    （[`docs/phase4/metal-failure-recovery.md`](docs/phase4/metal-failure-recovery.md) を参照して実施）
- [x] frame timing、atlas hit rate、uploaded byte count の metrics
  （[`docs/phase4/renderer-metrics.md`](docs/phase4/renderer-metrics.md) を参照して実施）
  - [x] native GPU completion timing と accepted atlas upload counters
    （[`docs/phase4/renderer-metrics.md`](docs/phase4/renderer-metrics.md) を参照して実施）
  - [x] Dart frame timing、atlas hit rate、aggregate metrics snapshot
    （[`docs/phase4/renderer-metrics.md`](docs/phase4/renderer-metrics.md) を参照して実施）
- [x] default Metal terminal surface と wrap-aware live viewport の製品統合
  （[`docs/phase4/product-metal-surface-integration.md`](docs/phase4/product-metal-surface-integration.md) を参照して実施）
  - [x] canonical screen-to-Metal composition と wrap-aware regression
    （[`docs/phase4/product-metal-surface-integration.md`](docs/phase4/product-metal-surface-integration.md) を参照して実施）
  - [x] default live Metal surface ownership と application connection
    （[`docs/phase4/product-metal-surface-integration.md`](docs/phase4/product-metal-surface-integration.md) を参照して実施）
  - [x] real-PTY GUI acceptance と legacy display removal
    （[`docs/phase4/product-metal-surface-integration.md`](docs/phase4/product-metal-surface-integration.md) を参照して実施）
- [x] macOS system monospace と標準サイズをzero-config既定値にする
  （[`docs/phase4/macos-system-default-font.md`](docs/phase4/macos-system-default-font.md) を参照して実施）
- [x] CoreText glyph atlas の上下反転を修正し実GUI画像で判読性を確認する
  （[`docs/phase4/glyph-raster-orientation.md`](docs/phase4/glyph-raster-orientation.md) を参照して実施）
- [x] zero-config既定フォントサイズを14ptへ拡大し実GUIで判読性を確認する
  （[`docs/phase4/larger-default-font-size.md`](docs/phase4/larger-default-font-size.md) を参照して実施）
- [x] scroll中のglyph垂直クリップを解消し、viewport移動後も行全体を安定表示する
  （[`docs/phase4/scroll-glyph-vertical-clipping.md`](docs/phase4/scroll-glyph-vertical-clipping.md)
  を参照して実施する）
  - [x] `dart_appkit`からnative content layout rectをread-only公開し、初期drawable寸法を取得できるようにする
  - [x] 初回hierarchy layoutをcontent寸法へ一致させ、scroll前後のglyph pixel安定性を検証する

終了条件:

- Latin、CJK、emoji、combining、wide cell、ligature の golden が 1x/2x で通る。
- 60/120 Hz display で同じ terminal state を安定表示できる。
- 大量 output 中も window move/resize と key input が応答する。
- renderer が遅れた際に unbounded queue や stale frame の連続描画が起きない。
- idle/occluded pane は不要な frame を生成しない。

### Phase 5 — Production input と interaction（8–13 person-weeks）

目的: 日本語を含む日常入力、選択、copy/paste を完成させる。

- [x] mode-aware key encoder と configurable keybind engine
  （[`docs/phase5/mode-aware-key-input.md`](docs/phase5/mode-aware-key-input.md) を参照して実施）
  - [x] DEC keyboard mode state と bounded xterm key encoder
  - [x] conflict検出・unbound・passthroughを備えたtyped keybind engine
  - [x] AppKit physical/produced/modifier/repeat入力とPTY writeの製品統合
- [x] `NSTextInputClient` と preedit overlay
  （[`docs/phase5/text-input-client-preedit.md`](docs/phase5/text-input-client-preedit.md) を参照して実施）
  - [x] AppKit first-responder routingとbounded native text-input client/event/geometry境界
  - [x] bounded Dart preedit model/layoutとCoreText/Metal overlay
  - [x] live pane raw/composition routingと実AppKit/PTY製品統合
- [x] US/JIS/dead key/CJK/emoji/key repeat matrix
  （[`docs/phase5/input-source-matrix.md`](docs/phase5/input-source-matrix.md) を参照して実施）
- [x] mouse protocol と local selection arbitration
  （[`docs/phase5/mouse-protocol-selection-arbitration.md`](docs/phase5/mouse-protocol-selection-arbitration.md) を参照して実施）
  - [x] DEC mouse tracking/encoding mode stateとbounded X10/UTF-8/URXVT/SGR encoder
  - [x] AppKit pointer-to-cell normalizationとterminal report/local selection arbitration
  - [x] 実AppKit/PTY製品統合と両runtimeのcross-mode acceptance
- [x] character/word/line selection、drag autoscroll
  （[`docs/phase5/selection-gesture-autoscroll.md`](docs/phase5/selection-gesture-autoscroll.md) を参照して実施）
  - [x] bounded cell/word/logical-line gesture stateとstable-anchor更新
  - [x] viewport projection・Metal selection overlay・bounded drag autoscroll
  - [x] 実AppKit製品統合と両runtimeのselection acceptance
- [x] precision trackpad scroll
  （[`docs/phase5/precision-trackpad-scroll.md`](docs/phase5/precision-trackpad-scroll.md) を参照して実施）
  - [x] `dart_appkit` event protocol v5 とbounded scroll event境界
  - [x] precision/momentum accumulatorとlocal/terminal/alternate-screen routing
  - [x] 実AppKit製品統合と両runtimeのscroll acceptance
- [x] clipboard、bracketed paste、paste safety
  （[`docs/phase5/clipboard-bracketed-paste-safety.md`](docs/phase5/clipboard-bracketed-paste-safety.md) を参照して実施）
  - [x] `dart_appkit` のbounded plain-text pasteboard read境界
  - [x] DEC bracketed-paste modeとbounded安全paste encoder
  - [x] PTY completion駆動のbounded非同期paste transport
  - [x] copy/paste menu・明示確認・両runtimeの10 MiB製品受け入れ
- [x] hyperlink hover/open と URL safety
  （[`docs/phase5/hyperlink-hover-open-url-safety.md`](docs/phase5/hyperlink-hover-open-url-safety.md) を参照して実施）
  - [x] bounded OSC 8 table・current link state・cell lifecycle
  - [x] viewport hyperlink hit test・Metal hover overlay
  - [x] `dart_appkit` のallowlist済みexternal URL open境界
  - [x] 実AppKit hover/open製品統合と両runtime受け入れ
- [x] VoiceOver の最小 visible text/selection/cursor support
  （[`docs/phase5/voiceover-visible-text-selection-cursor.md`](docs/phase5/voiceover-visible-text-selection-cursor.md) を参照して実施）
  - [x] bounded visible UTF-16 snapshotとselection/cursor mapping
  - [x] `TerminalMetalView`のAppKit accessibility contractとchange notification
  - [x] 実製品同期と両runtime VoiceOver受け入れ
- [x] CJK wide-cellの表示幅・pointer selection・clipboard抽出を一致させる
  （[`docs/phase5/cjk-wide-cell-selection-copy-geometry.md`](docs/phase5/cjk-wide-cell-selection-copy-geometry.md) を参照して実施）
- [x] 初回window close requestでscroll viewport位置を変更しない
  （[`docs/phase5/window-close-scroll-position.md`](docs/phase5/window-close-scroll-position.md) を参照して実施）

終了条件:

- 日本語 IME の compose/convert/commit/cancel と candidate 位置が正しい。
- tmux/Neovim の key と mouse mode、通常 shell の選択が共存する。
- 10 MiB paste でも UI が止まらず、PTY queue が上限内に留まる。
- keyboard-only と VoiceOver で prompt、selection、visible output を利用できる。

この段階を最初の **daily-driver alpha** とする。

### Phase 6 — VT/xterm compatibility hardening（12–20 person-weeks）

目的: 「主要アプリがたまたま動く」から、互換性を管理できる状態へ進める。

- [x] ECMA-48、DEC、xterm の sequence/mode inventory
  （[`docs/phase6/sequence-mode-inventory.md`](docs/phase6/sequence-mode-inventory.md) を参照して実施）
  - [x] versioned inventory schema、normative source pin、識別子taxonomy
  - [x] 実装由来sequence/mode manifestとfreshness checker
  - [x] support/gap分類、相互参照、review acceptance
- [x] xterm/Ghostty/Kitty との black-box differential harness
  （[`docs/phase6/black-box-differential-harness.md`](docs/phase6/black-box-differential-harness.md) を参照して実施）
  - [x] versioned case/observation/subprocess driver contractとDart backend
  - [x] pinned xterm/Ghostty/Kitty adapterとavailability/provenance self-test
  - [x] reviewed differential corpus、mismatch report、acceptance分類
    - [x] reviewed case manifest、Dart baseline、deterministic report gate
    - [x] pinned comparator capture実行とnormalized evidence
    - [x] mismatch最小化、acceptance report、harness完了判定
- [x] `vttest` を参考に採用/非採用項目を明文化
  （[`docs/phase6/vttest-adoption.md`](docs/phase6/vttest-adoption.md) を参照して実施）
- [x] tmux、ssh、mosh、Neovim、Emacs、ncurses、fzf、lazygit の matrix
  （[`docs/phase6/vttest-adoption.md`](docs/phase6/vttest-adoption.md) のadoption判断も参照して実施）
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) を参照して実施）
  - [x] versioned matrix contract、bounded runner、normal-gate validation
  - [x] pinned application execution、normalized evidence
  - [x] acceptance分類、gap最小化、matrix完了判定
- [x] terminfo source、compile/install/fallback
  （[`docs/phase6/vttest-adoption.md`](docs/phase6/vttest-adoption.md) のcharacter-set判断も参照して実施）
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) のcharacter-set/XTGETTCAP gapを参照して実施）
  （[`docs/phase6/terminfo-source-compile-install-fallback.md`](docs/phase6/terminfo-source-compile-install-fallback.md) を参照して実施）
  - [x] versioned compatible source、compiler contract、bundle resourceとfreshness gate
  - [x] product lookup、`TERMINFO` install、standard-name SSH fallback
  - [x] DEC Special Graphics、XTGETTCAP policy、real-application regression closure
- [x] OSC title/cwd/hyperlink/palette/clipboard policy
  （[`docs/phase6/vttest-adoption.md`](docs/phase6/vttest-adoption.md) のtitle判断も参照して実施）
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) のtitle-stack gapを参照して実施）
  - [x] bounded title/cwd metadata、OSC 0/1/2/7、title stack、snapshot contract
  - [x] native window title同期と両runtime製品受け入れ
  - [x] OSC 12/112 cursor color policyとrenderer反映
  - [x] deny-by-default OSC 52 policy、inventory/matrix回帰、親項目完了判定
- [x] focus/mouse/bracketed paste/query reports
  （[`docs/phase6/decrqss-sgr-gap.md`](docs/phase6/decrqss-sgr-gap.md) のgapを参照して実施）
  （[`docs/phase6/vttest-adoption.md`](docs/phase6/vttest-adoption.md) のmanual項目も参照して実施）
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) のfocus/mouse/query gapを参照して実施）
  （[`docs/phase6/focus-mouse-bracketed-paste-query-reports.md`](docs/phase6/focus-mouse-bracketed-paste-query-reports.md) の順序と完了条件を参照して実施）
  - [x] DEC focus reporting state、native routing、両runtime製品受け入れ
  - [x] SGR pixel mouse mode、native geometry、highlight mode非採用判断
  - [x] bounded DECRQSS SGR reply、differential gap解消
  - [x] XTVERSION/XTWINOPS、bracketed paste回帰、matrix/親項目完了判定
- [x] parser inspector と sequence trace export
  （[`docs/phase6/parser-inspector-sequence-trace-export.md`](docs/phase6/parser-inspector-sequence-trace-export.md) の順序と完了条件を参照して実施）
  - [x] bounded parser inspector event基盤
  - [x] versioned sequence trace export、normal gate、親項目完了判定
- [x] compatibility bug の regression corpus 化
  （[`docs/phase6/vttest-adoption.md`](docs/phase6/vttest-adoption.md) のadoption判断も参照して実施）
  （[`docs/phase6/compatibility-regression-corpus.md`](docs/phase6/compatibility-regression-corpus.md) の順序と完了条件を参照して実施）
  - [x] versioned corpus contract、harness、reviewed byte cases
  - [x] fix-family coverage reconciliation、normal gate、Phase完了判定

終了条件:

- P0 compatibility matrix に既知の silent corruption がない。
- 各 unsupported sequence は「安全に無視」「明示的に非対応」のどちらかである。
- すべての互換性 bug fix に byte-level regression test がある。
- alpha 利用 30 日相当の記録/soak で state divergence と crash がない。

### Phase 7 — Windows、tabs、splits、application UX（10–16 person-weeks）

目的: 単一 pane の製品から native macOS application へ進める。

- [x] test-only compatibility fixture と product native-source audit を分離する
  （実施時に
  [`docs/phase7/test-fixture-source-audit.md`](docs/phase7/test-fixture-source-audit.md)
  を参照する）
- [x] window → tab → split tree → terminal session の state model
  （分割と完了条件は
  [`docs/phase7/application-state-model.md`](docs/phase7/application-state-model.md)
  を参照して順に実施する）
  - [x] typed window/tab/split-node identity と immutable bounded split topology
  - [x] application/window/tab owner、focus/index、pane lifecycle mutation
  - [x] single-window product bootstrap/shutdown 統合と回帰受け入れ
- [x] native tabs と split layout/focus/resize/zoom
  （分割と完了条件は
  [`docs/phase7/native-tabs-split-layout-focus.md`](docs/phase7/native-tabs-split-layout-focus.md)
  を参照して順に実施する）
  - [x] model-owned split resize/equalize/zoom と minimum-cell geometry
  - [x] reusable AppKit native-tab/split/first-responder primitives
  - [x] terminal native hierarchy projection と adapter lifecycle
  - [x] multi-tab/four-pane product runtime 統合と M1 回帰受け入れ
- [x] menu/action registry と command palette
  （分割と完了条件は
  [`docs/phase7/menu-action-registry-command-palette.md`](docs/phase7/menu-action-registry-command-palette.md)
  を参照して順に実施する）
  - [x] bounded searchable action catalog/dispatcher と palette state
  - [x] registry-driven standard menu projection と dynamic validation
  - [x] native command palette と M1 両 runtime 回帰受け入れ
- [x] title、tab rename/color、cwd inheritance、proxy icon
  （分割と完了条件は
  [`docs/phase7/title-tab-metadata-cwd-proxy-icon.md`](docs/phase7/title-tab-metadata-cwd-proxy-icon.md)
  を参照して順に実施する）
  - [x] bounded tab presentation state と local cwd inheritance policy
  - [x] reusable AppKit proxy-icon と native-tab color primitives
  - [x] terminal 側の AppKit metadata substrate 採用記録
  - [x] native hierarchy metadata projection と M1 両 runtime 回帰受け入れ
- [x] fullscreen、screen migration、restoration、reopen
  （分割と完了条件は
  [`docs/phase7/fullscreen-screen-migration-restoration-reopen.md`](docs/phase7/fullscreen-screen-migration-restoration-reopen.md)
  を参照して順に実施する）
  - [x] bounded restoration snapshot と window placement/migration policy
  - [x] reusable AppKit frame/fullscreen primitives と versioned state events
  - [x] terminal hierarchy restoration、native projection、reopen lifecycle
  - [x] M1 両 runtime 回帰受け入れと親項目完了判定
- [x] per-pane close と app quit confirmation
  （分割と完了条件は
  [`docs/phase7/per-pane-close-app-quit-confirmation.md`](docs/phase7/per-pane-close-app-quit-confirmation.md)
  を参照して順に実施する）
  - [x] bounded foreground-process snapshot と close-risk classification
  - [x] application-owned per-pane close transaction と hierarchy collapse
  - [x] aggregate app quit confirmation と deferred native lifecycle coordination
  - [x] M1 両 runtime 回帰受け入れと親項目完了判定
- [x] multiple pane の scheduling/resource budget
  （分割と完了条件は
  [`docs/phase7/multiple-pane-scheduling-resource-budget.md`](docs/phase7/multiple-pane-scheduling-resource-budget.md)
  を参照して順に実施する）
  - [x] application-wide live-pane resource admission
  - [x] bounded round-robin pane render scheduling
  - [x] bounded PTY/parser dispatch と Developer JIT flood 回帰
  - [x] cooperative PTY batch turn yielding と full-matrix starvation 回帰
  - [x] full-matrix Release AOT resource auto-close sequencing 回帰
    （[`docs/phase7/runtime-resource-close-sequence-blocker.md`](docs/phase7/runtime-resource-close-sequence-blocker.md)
    を参照して実施する）
  - [x] cross-pane flood/input 両 runtime 回帰受け入れと親項目完了判定
- [x] AppKit unit、integration、UI tests
  （分割と完了条件は
  [`docs/phase7/appkit-unit-integration-ui-tests.md`](docs/phase7/appkit-unit-integration-ui-tests.md)
  を参照して順に実施する）
  - [x] deterministic coverage contract と repeated fake-AppKit topology
  - [x] multi-window dual-runtime UI と menu-shortcut isolation
  - [x] full regression、evidence reconciliation、Phase 7 完了判定
- [x] 通常起動でwindow/tab/splitのuser actionを有効にする
  （分割と完了条件は
  [`docs/phase7/user-facing-window-tab-split-actions.md`](docs/phase7/user-facing-window-tab-split-actions.md)
  を参照して順に実施する）
  - [x] command palette起動直後のimplemented action availabilityを同期する
  - [x] terminal product hierarchy action coordinatorを実装する
  - [x] 通常起動をmulti-window/tab/pane native hierarchyへ移行する
  - [x] native window lifecycle、per-pane close、app quitを通常階層へ接続する
  - [x] user-driven actionのM1両runtime受け入れとPhase 7再完了判定

終了条件:

- 複数 window × 複数 tab × 4 pane を繰り返し作成/復元できる。
- focus、key routing、IME、menu shortcut が別 pane へ漏れない。
- pane close 後に PTY/isolate/Metal/native handle が残らない。
- 1 pane の大量出力が他 pane の入力を飢餓状態にしない。

### Phase 8 — Config、themes、shell integration（8–13 person-weeks）

目的: zero-config と高度な customization を両立する。

- [x] typed config schema と diagnostics
- [x] theme/palette/font/window/input/scrollback options
  （分割と完了条件は
  [`docs/phase8/product-option-families.md`](docs/phase8/product-option-families.md)
  を参照して順に実施する）
  - [x] bounded option schema と immutable new-session profile
  - [x] session/screen/renderer/input/window への product projection
  - [x] M1 両 runtime 回帰受け入れと親項目完了判定
- [x] declarative keybind と action reference generation
  （分割と完了条件は
  [`docs/phase8/declarative-keybind-action-reference.md`](docs/phase8/declarative-keybind-action-reference.md)
  を参照して順に実施する）
  - [x] repeatable config occurrence と typed keybind grammar/profile
  - [x] pane/application action routing と native menu arbitration
  - [x] generated keybind/action reference と freshness gate
  - [x] M1 両 runtime 回帰受け入れと親項目完了判定
- [x] safe reload、per-option live/new-session policy
  （分割と完了条件は
  [`docs/phase8/safe-configuration-reload.md`](docs/phase8/safe-configuration-reload.md)
  を参照して順に実施する）
  - [x] option application policy と typed snapshot diff/plan
  - [x] last-known-good reload transaction と single-flight 制御
  - [x] reload action と live/new-session product projection
  - [x] M1 両 runtime reload 受け入れと親項目完了判定
- [x] light/dark theme と system appearance
  （分割と完了条件は
  [`docs/phase8/light-dark-system-appearance.md`](docs/phase8/light-dark-system-appearance.md)
  を参照して順に実施する）
  - [x] `dart_appkit` application appearance event protocol と typed cache
  - [x] built-in light/dark pair と layered palette/custom override
  - [x] system appearance の live product projection
  - [x] M1 両 runtime theme/appearance 受け入れと親項目完了判定
- [x] zsh/bash/fish/nushell integration
  （分割と完了条件は
  [`docs/phase8/shell-integration.md`](docs/phase8/shell-integration.md)
  を参照して順に実施する）
  - [x] typed shell selection/integration policy と immutable launch-plan boundary
  - [x] versioned four-shell resources と bundle/freshness contract
  - [x] new-session projection と shell execution coverage
  - [x] M1 両 runtime shell-integration 受け入れと親項目完了判定
- [x] cwd/title/prompt mark/jump-to-prompt/close hint
  （[`docs/phase8/cwd-title-prompt-mark-close-hint.md`](docs/phase8/cwd-title-prompt-mark-close-hint.md)
  を参照して順に実施する）
  - [x] bounded OSC 133 semantic state と row-flag projection
  - [x] four-shell cwd/title/prompt lifecycle emission と resource contract
  - [x] viewport prompt navigation と shared product actions
  - [x] conservative close-hint/process-snapshot composition
  - [x] M1 両 runtime semantic-shell 受け入れと親項目完了判定
- [x] settings UI と effective-config inspector
  （[`docs/phase8/settings-effective-config-inspector.md`](docs/phase8/settings-effective-config-inspector.md)
  を参照して順に実施する）
  - [x] schema-owned canonical presentation と deprecated migration diagnostics
  - [x] `--help`/`--show-config` と generated configuration reference
  - [x] shared Settings action と searchable native effective-config inspector
  - [x] M1 両 runtime settings/effective-config 受け入れと Phase 8 完了判定
- [x] schema-complete modal settings editor と contextual detail panel
  （[`docs/phase8/editable-settings-editor.md`](docs/phase8/editable-settings-editor.md)
  を参照して順に実施する）
  - [x] complete configuration document、draft validation、atomic persistence
  - [x] NORMAL/INSERT/search/detail state と mode-invariant syntax projection
  - [x] `dart_appkit` の汎用 attributed editable text surface
  - [x] native editor/detail composition、save/reload、focus/cleanup lifecycle
  - [x] M1 両 runtime editable Settings 受け入れ
  - [x] existing root permission bits retention と Phase 8 再完了判定
- [x] unavailable file option の default fallback と startup recovery
  （[`docs/phase8/configuration-value-fallback.md`](docs/phase8/configuration-value-fallback.md)
  を参照して順に実施する）
  - [x] loader availability validation と deterministic default recovery
  - [x] macOS font availability adapter と product/Settings integration
  - [x] M1 両 runtime unavailable-font 受け入れと Phase 8 再完了判定
- [x] zero-config terminal と Settings editor の default typography 統一
  （[`docs/phase8/shared-terminal-settings-typography.md`](docs/phase8/shared-terminal-settings-typography.md)
  を参照して実施する）
- [x] Retina 実表示での terminal / Settings typography parity
  （[`docs/phase8/retina-font-rendering-parity.md`](docs/phase8/retina-font-rendering-parity.md)
  を参照して順に実施する）
  - [x] `dart_terminal_renderer_macos` の CoreText raster scale と pixel regression
  - [x] product の native-scale/ink-size受け入れと Phase 8 再完了判定
- [x] Settings editor の disabled-line / cursor-line visual clarity
  （[`docs/phase8/settings-editor-visual-clarity.md`](docs/phase8/settings-editor-visual-clarity.md)
  を参照して順に実施する）
  - [x] `dart_appkit` の attributed editor line-highlight API
  - [x] commented assignment と mode-invariant cursor line の product 投影・受け入れ
- [x] Settings editor の NORMAL/SEARCH selection viewport follow
  （[`docs/phase8/settings-editor-selection-viewport-follow.md`](docs/phase8/settings-editor-selection-viewport-follow.md)
  を参照して順に実施する）
  - [x] `dart_appkit` の explicit selection reveal API
  - [x] product navigation投影と M1 両runtime受け入れ
- [x] Settings editor の initial document presentation
  （[`docs/phase8/settings-editor-initial-document-presentation.md`](docs/phase8/settings-editor-initial-document-presentation.md)
  を参照して順に実施する）
  - [x] `dart_appkit` line-highlight prepaint layoutの確定
  - [x] productの初回実描画と M1 両runtime受け入れ

終了条件:

- invalid config が app 起動を破壊せず、file/line と修正案を表示する。
- reload 中も pane/PTY が失われない。
- config schema から CLI/help/settings/action docs の整合を検査できる。
- shell integration 無効時も通常の terminal として完全に動く。

### Phase 9 — Modern terminal protocols（12–20 person-weeks）

目的: 現代的 TUI が使う Ghostty クラスの protocol を追加する。

- [x] Kitty keyboard protocol
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) のinput protocol gapを参照して実施）
  （分割と完了条件は
  [`docs/phase9/kitty-keyboard-protocol.md`](docs/phase9/kitty-keyboard-protocol.md)
  を参照して順に実施する）
  - [x] protocol state、controls、bounded per-screen stack、reply
  - [x] canonical key-event encoding と press/repeat/release routing
  - [x] product acceptance、compatibility closure、親項目完了判定
- [x] synchronized output/rendering
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) のsynchronized-output gapを参照して実施）
  （分割と完了条件は
  [`docs/phase9/synchronized-output-rendering.md`](docs/phase9/synchronized-output-rendering.md)
  を参照して順に実施する）
  - [x] bounded parser-to-presentation hold、timeout、compatibility closure
  - [x] real PTY/Metal product acceptance、親項目完了判定
- [x] light/dark notification と extended reports
  （[`docs/phase6/real-application-compatibility-matrix.md`](docs/phase6/real-application-compatibility-matrix.md) のtheme report/update gapを参照して実施）
  （目的、境界、完了条件は
  [`docs/phase9/light-dark-notification-extended-reports.md`](docs/phase9/light-dark-notification-extended-reports.md)
  を参照して順に実施する）
  - [x] immutable source pins、appearance/size/Unicode protocol core
  - [x] product appearance/resize projection、compatibility closure
  - [x] M1 real PTY/Metal acceptance、親項目完了判定
- [x] Kitty graphics parse/storage/placement/render
  （分割、境界、完了条件は
  [`docs/phase9/kitty-graphics.md`](docs/phase9/kitty-graphics.md)
  を参照して順に実施する）
  - [x] immutable source pins、bounded APC command grammar、reply contract
  - [x] process-worker direct decode と bounded static image storage
    - [x] typed generation-safe base64/zlib/PNG/RGB(A) worker decode
    - [x] per-screen storage、multipart/FIFO replies、failure/teardown semantics
  - [x] placement/delete/z-index/scroll/screen semantics と reference projection
    - [x] bounded placement state、put/delete actions、cursor/z semantics
    - [x] scroll/erase/reflow/alternate/RIS semantics、immutable viewport projection
    - [x] CPU reference compositor/golden、placement child完了判定
  - [x] Metal product acceptance、compatibility/documentation closure、親項目完了判定
- [x] image animation と resource eviction
  （分割、境界、完了条件は
  [`docs/phase9/kitty-image-animation-resource-eviction.md`](docs/phase9/kitty-image-animation-resource-eviction.md)
  を参照して順に実施する）
  - [x] animation protocol、worker decode、bounded frame state
  - [x] monotonic playback、CPU/Metal projection、scheduler/recovery
  - [x] deterministic resource eviction、product/compatibility closure、親項目完了判定
- [x] desktop notification、progress、semantic prompt extensions
  （分割、境界、完了条件は
  [`docs/phase9/desktop-notification-progress-semantic-extensions.md`](docs/phase9/desktop-notification-progress-semantic-extensions.md)
  を参照して順に実施する）
  - [x] immutable source pins、bounded notification/progress/semantic protocol core
  - [x] rate-limited native projection、progress/semantic lifecycle integration
  - [x] real PTY/native product acceptance、compatibility/documentation closure、親項目完了判定
- [x] OSC 52 confirmation/policy UI
  （分割、境界、完了条件は
  [`docs/phase9/osc52-confirmation-policy-ui.md`](docs/phase9/osc52-confirmation-policy-ui.md)
  を参照して順に実施する）
  - [x] bounded OSC 52 protocol/configuration core
  - [x] exact application confirmation and pasteboard projection
  - [x] shipped-runtime acceptance、compatibility/documentation closure、親項目完了判定
- [x] protocol-specific fuzz、security、memory tests
  （分割、境界、完了条件は
  [`docs/phase9/protocol-fuzz-security-memory.md`](docs/phase9/protocol-fuzz-security-memory.md)
  を参照して順に実施する）
  - [x] deterministic Phase 9 parser/state properties
  - [x] authority/retained-resource state-machine stress
  - [x] shipped-runtime/resource acceptance、Phase 9 closure、親項目完了判定

終了条件:

- protocol origin terminal の挙動と documented cases を比較済み。
- image/OSC flood で configured memory cap を越えない。
- synchronized rendering が途切れた場合に timeout で表示を復旧する。
- Kitty keyboard を使う Neovim 等と legacy app の両方が regression しない。

### Phase 7 follow-up — split pane表示とdivider操作

- [x] split paneのRetina表示、drag resize同期、keyboard divider操作
  （分割、境界、完了条件は
  [`docs/phase7/split-pane-resolution-resize-controls.md`](docs/phase7/split-pane-resolution-resize-controls.md)
  を参照して順に実施する）
  - [x] 新規splitへ既存windowのbacking scaleを投影する
  - [x] native divider dragを論理layout/viewport/gridへ同期して表示倍率を固定する
    - [x] `dart_appkit` にboundedなnative split fraction queryを追加する
    - [x] divider gestureをmodel/layout/renderer/PTYへ同期してmouse漏洩を防ぐ
  - [x] 方向別divider action、Command+矢印、製品受け入れ、親項目完了判定

### Phase 10 — macOS native polish と accessibility（10–16 person-weeks）

目的: macOS 専用アプリとしての完成度を上げる。

- [x] Quick Terminal と global shortcut
  （分割、境界、完了条件は
  [`docs/phase10/quick-terminal-global-shortcut.md`](docs/phase10/quick-terminal-global-shortcut.md)
  を参照して順に実施する）
  - [x] typed Quick Terminal configuration、action、logical lifecycle contract
  - [x] `dart_appkit` exclusive global shortcut registration/event substrate
  - [x] `dart_appkit` Quick Terminal window/screen/presentation substrate
  - [x] product integration、両runtime acceptance、documentation closure、親項目完了判定
- [x] Secure Keyboard Entry と auto/manual indication
  （分割、境界、完了条件は
  [`docs/phase10/secure-keyboard-entry.md`](docs/phase10/secure-keyboard-entry.md)
  を参照して順に実施する）
  - [x] `dart_pty_macos` content-free terminal echo observation substrate
  - [x] `dart_appkit` balanced Secure Event Input/indication substrate
  - [x] terminal policy/configuration/action/lifecycle integration
    - [x] `dart_appkit` checked menu-item projection prerequisite
    - [x] controller、live config、shared action、UI/lifecycle integration
  - [x] 両runtime acceptance、manual checklist、documentation closure、親項目完了判定
- [x] Quick Look、Services、drag/drop、context menu
  （分割、境界、完了条件は
  [`docs/phase10/quick-look-services-drag-drop-context-menu.md`](docs/phase10/quick-look-services-drag-drop-context-menu.md)
  を参照して順に実施する）
  - [x] bounded terminal interaction contracts、shared action metadata
  - [x] `dart_appkit` context-menu、Quick Look substrate
    - [x] View context-menu attachment、ownership substrate
    - [x] Quick Look request event、definition presentation substrate
  - [x] `dart_appkit` Services、drop-destination substrate
    - [x] cached plain-text Services requestor、returned-text event substrate
    - [x] bounded text/file-URL drop-destination substrate
    - [x] application folder Services provider substrate
  - [x] `dart_macos_runtime` service declaration substrate
  - [x] product integration、両runtime acceptance、documentation closure、親項目完了判定
    - [x] focused product wiring、deterministic policy/lifecycle tests
    - [x] Developer JIT／Release AOT native acceptance、manual checklist
    - [x] documentation/evidence closure、親項目完了判定
- [x] AppleScript dictionary と object lifecycle
  （分割、境界、完了条件は
  [`docs/phase10/applescript-dictionary-object-lifecycle.md`](docs/phase10/applescript-dictionary-object-lifecycle.md)
  を参照して順に実施する）
  - [x] typed configuration、snapshot、command、lifecycle contract
  - [x] native AppleScript capability、runtime dictionary packaging
    - [x] `dart_macos_runtime` scripting-definition manifest／bundle substrate
    - [x] terminal-specific cached hierarchy／suspended-command native package
    - [x] dependency gates、consumer declaration、bundle audit
  - [x] product integration、両runtime acceptance、manual checklist
    - [x] product session adapter、snapshot／command policy tests
    - [x] Developer JIT／Release AOT self-automation acceptance、manual checklist
  - [x] documentation/evidence closure、親項目完了判定
- [x] App Intents/Shortcuts、notifications
  （分割、境界、完了条件は
  [`docs/phase10/app-intents-shortcuts-notifications.md`](docs/phase10/app-intents-shortcuts-notifications.md)
  を参照して順に実施する）
  - [x] `dart_appkit` notification permission／result／response substrate
  - [x] App Intents native capability、runtime metadata packaging
    - [x] `dart_macos_runtime` App Intents manifest／metadata bundle substrate
    - [x] terminal-specific Swift App Intents capability／bounded command queue
    - [x] consumer declaration、dependency gates、bundle audit
  - [x] product configuration、shared-action、Settings、lifecycle integration
  - [x] Developer JIT／Release AOT acceptance、manual checklist、documentation closure、親項目完了判定
- [x] complete VoiceOver/Accessibility Inspector pass
  - [x] configured terminal padding の accessibility hit/range geometry を
    renderer content origin と一致させる
    - [x] renderer accessibility content-origin contract／native geometry tests
    - [x] product projection、両runtime acceptance、manual checklist、親項目完了判定
- [x] `dart_appkit` から製品固有実装を分離する
  （分割、境界、完了条件は
  [`docs/phase10/dart-appkit-generic-boundary.md`](docs/phase10/dart-appkit-generic-boundary.md)
  を参照して順に実施する）
  - [x] 全件inventoryと所有権境界、移設順、検証方針を確定する
  - [x] PTY native asset packageを製品repositoryへ移設する
  - [x] Metal renderer capability packageを製品repositoryへ移設する
  - [x] AppleScript capability packageを製品repositoryへ移設する
  - [x] App Intents capability packageを製品repositoryへ移設する
  - [x] Finder folder Servicesをapplication注入の汎用actionへ変更する
  - [x] Secure Input表示をapplication注入の汎用badgeへ変更する
  - [x] 汎用repositoryのbuild、test fixture、現行文書を製品非依存にする
  - [x] 両repositoryの完全gateと製品runtime受け入れを行い親項目を完了する
- [x] Reduce Motion/Contrast と localization
  （分割、境界、完了条件は
  [`docs/phase10/accessibility-display-localization.md`](docs/phase10/accessibility-display-localization.md)
  を参照して順に実施する）
  - [x] accessibility preference／UI text inventoryとtyped contractを確定する
  - [x] `dart_appkit`の汎用accessibility display preference snapshot／event substrate
  - [x] Reduce Motion／Increase Contrast／Differentiate Without Colorの製品投影
  - [x] English／Japanese catalog、locale fallback、RTL application UI投影
    - [x] locale／direction model、typed catalog基盤、action metadataを実装する
    - [x] menu／palette／confirmation／status UIをcatalogへ移行する
    - [x] Settings／application UI、RTL composition、resource宣言を移行する
    - [x] static UI leak auditとcatalog completeness検証で子項目を完了する
  - [x] 両runtime受け入れ、文書／matrix更新、Phase 10完了判定
- [x] terminal inspector と diagnostics bundle
  （分割、privacy境界、完了条件は
  [`docs/phase10/terminal-inspector-diagnostics-bundle.md`](docs/phase10/terminal-inspector-diagnostics-bundle.md)
  を参照して順に実施する）
  - [x] field inventory、privacy分類、versioned inspector／bundle contract
  - [x] `dart_appkit`の汎用save-destination panel substrate
  - [x] bounded live parser inspector／diagnostics export model
  - [x] localized product window、shared actions、atomic export integration
  - [x] static privacy audit、両runtime受け入れ、文書／matrix更新、Phase 10完了判定

終了条件:

- native feature ごとに enable/disable、permission、failure path がある。
- Secure Input は pane/window/app の異常終了後も確実に解除される。
- AppleScript から window/tab/split/input/focus/close を操作できる。
- VoiceOver と Full Keyboard Access の release checklist が全項目通る。

### Phase 11 — Distribution、performance、parity burn-down（12–24 person-weeks）

目的: feature complete build を安全に配布できる release へする。

- [ ] AOT release、Universal Binary、resource layout
  （分割、bundle境界、完了条件は
  [`docs/phase11/aot-universal-resource-layout.md`](docs/phase11/aot-universal-resource-layout.md)
  を参照して順に実施する）
  - [x] distribution inventory、thin／Universal bundle contract
  - [x] `dart_macos_runtime`の汎用target-architecture thin Release AOT build
  - [x] `dart_macos_runtime`の汎用atomic Universal release assembly
  - [ ] product thin／Universal build、resource audit、runtime受け入れ、親項目完了判定
- [ ] Developer ID signing、hardened runtime、notarization
- [ ] update feed、署名検証、rollback
- [ ] local crash report、hang sample、privacy-safe diagnostics
- [ ] startup/input/render/parser/memory/power benchmark regression gate
- [ ] 24/72 hour soak、sleep/wake、display attach/detach、memory pressure
- [ ] native ASan/UBSan、fuzz corpus、fault injection
- [ ] Ghostty pinned matrix の P0/P1 gap burn-down
- [ ] release candidate の daily-use program matrix

終了条件:

- signed/notarized build を clean machine へ install/update/uninstall できる。
- release benchmark が下記予算と relative parity gate を満たす。
- blocker/crash/data-loss/security bug が 0。
- known limitation が文書化され、silent misbehavior がない。
- 30 日の daily-driver と 72 時間の automated soak を通る。

### 主要ゴール後の低優先 follow-up

- [ ] 公開・未改変 runtime の x86_64 cross-build、Rosetta、Universal compatibility
  再検証、Intel-native no-rebuild runtime handoff と追加互換性証跡（主要ゴール達成後に実施し、
  [`docs/phase1/universal-runtime-matrix.md`](docs/phase1/universal-runtime-matrix.md)
  を実施時に参照する）

## 8. テスト戦略

| レベル | 対象 | 必須内容 |
| --- | --- | --- |
| Unit | parser、grid、key encoder、config、split tree | table-driven tests、境界値、全 chunk 分割、snapshot |
| Property | parser/grid/reflow | 同じ byte 列の chunk 非依存性、resize round-trip、cursor/grid invariant |
| Fuzz | UTF-8、ESC family、OSC/DCS/APC、image | timeout、memory cap、crash 0、recovery 後 printable text |
| PTY integration | spawn、job control、signals、resize、exit | fake backend と real PTY の両方 |
| Conformance | ECMA/DEC/xterm/modern protocols | source と期待挙動を test 名に記録 |
| Differential | xterm、Ghostty、Kitty | byte reply、screen snapshot、mode state の差分 |
| Golden | font、Unicode、renderer、themes | 1x/2x、light/dark、複数 font、GPU/reference 比較 |
| GUI | window、tab、split、IME、clipboard、restoration | XCTest 相当の AppKit UI harness |
| Accessibility | VoiceOver、Full Keyboard Access | visible range、selection、cursor、通知 |
| Performance | parse、damage、atlas、frame、latency、memory | baseline machine と release AOT で継続計測 |
| Reliability | soak、fault injection、sleep/wake | child/GPU/isolate crash、FD/handle/leak audit |
| Release | signing、notarization、update | clean account と複数 macOS version |

### Compatibility program matrix

- shells: zsh、bash、fish、nushell
- multiplexers: tmux、zellij
- editors: Neovim、Vim、Emacs
- pagers/monitoring: less、man、top、htop、btop
- TUIs: fzf、lazygit、yazi、ranger、ncurses demos
- remote: ssh、mosh、serial-like raw applications
- text: Latin、Japanese、Korean、Chinese、emoji、combining marks、RTL grapheme samples

各 bug は「アプリ名だけ」の test にせず、最小 byte sequence と terminal state の
regression test へ還元する。

## 9. 暫定性能予算

Phase 0 で baseline machine、Ghostty build、corpus、測定方法を固定し、数値を改訂する。
以下は設計を bounded に保つための初期予算である。

| 指標 | 暫定 gate |
| --- | --- |
| AppKit event handler | p95 1 ms 未満。重い処理を UI isolate で行わない |
| Key → PTY queue | p95 2 ms 未満 |
| Key echo → visible | p95 で 1 display refresh + 4 ms 以内 |
| Frame work | p95 で refresh budget の 70% 未満 |
| Parser | AOT、単一 engine isolate で 100 MiB/s 以上を最初の目標にする |
| Burst output | 100 MiB で UI hang 0、queue と memory が設定上限内 |
| Idle | animation 無効時、全 pane 合計 CPU 0.5% 未満を目標 |
| Occluded | PTY/state は進むが GPU frame submit を停止 |
| Scrollback | 100 万行 test で bounded、viewport 操作 p95 16 ms 未満 |
| Pane isolation | 1 pane の flood が別 pane の key latency を 2 倍以上にしない |

最終 parity gate は同じ Mac、同じ shell/config/corpus で Ghostty と比較する。

- input latency: Ghostty の p95 に 4 ms を加えた値、または 1.25 倍の大きい方以下
- parser/output completion: Ghostty の 0.75 倍以上
- steady frame rate: Ghostty と同じ refresh tier
- idle memory/CPU: Ghostty の 1.5 倍以内
- 重大な差が出た場合、micro-optimization より allocation、copy、thread/isolate 境界を見直す

## 10. リスク登録簿

| リスク | 影響 | 早期検証/対策 |
| --- | --- | --- |
| Dart isolate は shared mutable memory を持たない | frame data copy と latency | Phase 0 で damage transfer と native double buffer を比較 |
| GC pause と object allocation | output flood 時の jitter | typed arrays、interning、page pool、allocation benchmark |
| AppKit main-thread 制約 | UI freeze/deadlock | UI isolate の責務を限定し、同期 native callback を禁止 |
| fork と multi-threaded Dart VM | child deadlock/crash | native child path を async-signal-safe に固定、即 `execve` |
| Metal/CoreText FFI が細かすぎる | FFI overhead | coarse batch ABI、atlas/run cache、1 frame 数 call |
| IME と terminal key protocol の競合 | 日本語入力破損 | Phase 0 spike、marked/commit と raw key を分離 |
| AOT と embedded main-thread isolate | 配布不能 | 最初の feasibility gate に置く |
| Universal/signing/notarization | 最後に bundle を作り直す | Phase 1 から release-like bundle を継続生成 |
| VT の de facto behavior | endless compatibility bugs | pinned matrix、xterm優先順位、regression corpus |
| Images/clipboard sequences | memory/security issue | default limits、confirmation、fuzz を機能と同時実装 |
| 複数 pane | isolate/FD/GPU resource 増大 | 1 pane 安定後に導入、per-pane budget と fairness test |
| Ghostty は継続的に進化する | 完了条件が動く | 比較 commit を milestone ごとに固定し、追随は別 backlog |

## 11. 完了定義

Ghostty クラス到達を宣言できるのは、次をすべて満たしたときだけとする。
主要実機 baseline は Apple M1/arm64 とする。x86_64 cross-build、Rosetta、Universal
audit、Intel-native の追加証跡は上記の主要ゴール後 follow-up であり、この完了定義の
必須条件には含めない。

- pinned feature matrix の P0/P1 に未説明の欠落がない。
- compatibility suite と daily-use program matrix が release AOT で通る。
- 日本語 IME、emoji、ligature、wide/combining text の visual/input test が通る。
- 60 Hz/120 Hz、Retina、複数 display、sleep/wake で rendering fault がない。
- windows/tabs/splits の create/restore/close で PTY、FD、isolate、GPU、handle leak がない。
- parser/image/clipboard の security limit と fuzz gate が通る。
- VoiceOver、Full Keyboard Access、Secure Input の checklist が通る。
- signed/notarized Universal app の fresh install と update が通る。
- relative performance gate と 72-hour soak が通る。
- crash/data loss/security blocker が 0 で、known limitations が公開されている。

## 12. 見積もりと体制

| 到達点 | 累積目安 |
| --- | --- |
| Feasibility 完了 | 3–5 person-weeks |
| 本物の PTY vertical slice | 14–23 person-weeks |
| VT core + Metal 表示 | 38–61 person-weeks |
| daily-driver alpha | 46–74 person-weeks |
| rich multi-pane beta | 76–123 person-weeks |
| Ghostty クラス release | 110–183 person-weeks + long-tail bug fixing |

単独で full-time 開発する場合は、おおむね 2.5–4 年規模で、その後も互換性の
継続保守が必要になる。3 人の経験者が terminal core、macOS/UI、renderer/QA を
並行できれば 12–24 か月を狙えるが、単純に人数分だけ短縮はできない。

推奨 workstream:

1. **Terminal core** — parser、grid、scrollback、protocol、fuzz
2. **macOS platform** — runtime、PTY、AppKit、IME、accessibility、release
3. **Renderer/performance** — CoreText、Metal、golden、benchmark
4. **Compatibility/product** — UI、config、shell integration、real-app matrix

## 13. 直近に着手する issue 順

1. `DT-000` — Ghostty pinned feature matrix と P0/P1/P2 の確定
2. `DT-001` — Dart/native boundary ADR
3. `DT-002` — release AOT main-thread root isolate spike
4. `DT-003` — worker isolate lifecycle/throughput spike
5. `DT-004` — safe `forkpty`/exec/job-control spike
6. `DT-005` — PTY kqueue batching/backpressure spike
7. `DT-006` — MTKView packed glyph benchmark
8. `DT-007` — CoreText CJK/emoji/ligature spike
9. `DT-008` — NSTextInputClient 日本語 IME spike
10. `DT-009` — packed cell/grid ADR と microbenchmark
11. `DT-010` — parser corpus format と snapshot harness
12. `DT-011` — benchmark baseline と regression output format
13. `DT-012` — debug/release/Universal bundle CI design

最初の実装 milestone は「PTY を急いで製品コードへ追加する」ことではなく、
`DT-002` から `DT-009` の feasibility report を完成させることとする。

## 14. 参照資料

Ghostty 公式:

- [Ghostty repository — pinned commit](https://github.com/ghostty-org/ghostty/tree/d4d8f62262cb1a974a7d2470d5f79f811fab15e4)
- [Ghostty roadmap and architecture overview](https://github.com/ghostty-org/ghostty/blob/main/README.md)
- [Feature overview](https://ghostty.org/docs/features)
- [Terminal API / VT](https://ghostty.org/docs/vt)
- [VT sequence reference](https://ghostty.org/docs/vt/reference)
- [Configuration reference](https://ghostty.org/docs/config/reference)
- [Shell integration](https://ghostty.org/docs/features/shell-integration)
- [AppleScript](https://ghostty.org/docs/features/applescript)
- [Terminal source layout](https://github.com/ghostty-org/ghostty/tree/main/src/terminal)
- [Renderer source layout](https://github.com/ghostty-org/ghostty/tree/main/src/renderer)
- [macOS source and tests](https://github.com/ghostty-org/ghostty/tree/main/macos)

Dart / Apple 公式:

- [Dart concurrency and isolates](https://dart.dev/language/concurrency)
- [Dart C interop](https://dart.dev/interop/c-interop)
- [Apple openpty/forkpty manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/openpty.3.html)
- [MTKView](https://developer.apple.com/documentation/metalkit/mtkview)
- [Core Text](https://developer.apple.com/documentation/CoreText)
- [NSTextInputClient](https://developer.apple.com/documentation/AppKit/NSTextInputClient)
- [NSPasteboard](https://developer.apple.com/documentation/AppKit/NSPasteboard)
- [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)

ローカル資料:

- [`dart_terminal` README](README.md)
- [`dart_appkit` MVP roadmap](../dart_appkit/ROADMAP.md)
- [`dart_appkit` architecture](../dart_appkit/docs/ARCHITECTURE.md)
