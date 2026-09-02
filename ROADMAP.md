# Dart Terminal — Ghostty クラス品質への詳細ロードマップ

最終更新: 2026-09-02<br>
対象: macOS 14 以降、Flutter 不使用  
Ghostty 調査基準: `ghostty-org/ghostty` main の
`d4d8f62262cb1a974a7d2470d5f79f811fab15e4`  
ローカル基準: `dart_appkit` の
`5613950f15cf9837e5a025a9943c5b8010be4218`

主要な開発・実機受け入れ baseline は Apple M1/arm64 とする。x86_64 は M1 上の
cross-build、Rosetta compatibility、Universal audit を主要 gate とし、
Intel-native 実機証跡は主要ゴール後の低優先 follow-up とする。

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
| Runtime | JIT Kernel、root isolate が AppKit main thread | AOT 配布、debug/release 分離、複数 worker isolate | AOT host、isolate lifecycle、crash handling |
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
- [ ] Dart SDK source を改変しない runtime hosting へ移行する（以下を順に実施し、
  [`docs/phase1/unmodified-dart-engine-hosting.md`](docs/phase1/unmodified-dart-engine-hosting.md)
  を実施時に参照する）
  - [x] 支持する API 境界、比較対象、受け入れ条件、移行順序を固定する
  - [x] 未改変 `dart_engine` の複数 root isolate 方式を実証して採否を決める
  - [x] 不採用時は公開 Dart Embedder API による製品所有 host を実証して採否を決める
  - [ ] 公開 API が不足する場合は汎用的な `dart_engine` 改善案と process 分離を比較する
    - [x] disposable SDK checkout で汎用 Engine 改善と上流回帰テストを実証する
    - [x] 公式 Dart executable を使う process/IPC fallback を実証する
    - [ ] 所有権、性能、配布、上流採用待ちを比較して現在の製品経路を選定する
  - [ ] 選定した公式または上流採用済みの方式へ JIT/AOT lifecycle を移行する
  - [ ] patch、patch 適用処理、patch 来歴を撤去して clean Engine 前提の全 matrix を通す
  - [ ] 必要な `dart_engine` 改善を再現・API・test 込みの上流向け提案としてまとめる
- [ ] native event wire format の versioning と backward compatibility
- [ ] handle registry に thread-domain と asynchronous destruction を追加
- [ ] generic `View`、focus、visibility、occlusion、backing scale、screen event
- [ ] menu、pasteboard、application/window lifecycle API
- [ ] TerminalMetalView を attach できる generic custom-view boundary
- [ ] macOS unified logging と local crash metadata
- [ ] native/Dart の resource leak test と shutdown fault injection

終了条件:

- AOT `.app` が起動し、root UI isolate と worker isolate が共存する。
- 1000 回の window/view create-destroy で native handle が増えない。
- malformed event、late event、double dispose、worker crash で app 全体が hang しない。
- debug と release が同じ integration suite を通る。

### Phase 2 — Persistent PTY vertical slice（5–8 person-weeks）

目的: command console を本物の terminal session へ置き換える。

- [ ] stable `dt_pty_*` C ABI と Dart facade
- [ ] argv/env/cwd/login shell の安全な spawn
- [ ] kqueue/GCD reactor、read batching、write queue、backpressure
- [ ] `winsize`、SIGWINCH、process group、waitpid、exit event
- [ ] Ctrl-C/Z/\、EOF、HUP、graceful/forced close
- [ ] session ID と pane ownership、close confirmation state
- [ ] fake PTY backend と deterministic integration harness

終了条件:

- `tty` が pseudo-terminal を返す。
- `stty size` が window resize に追従する。
- zsh の interactive prompt、job control、`fg`/`bg` が動く。
- 10 MiB burst、partial UTF-8、child crash、window close を失敗なく処理する。
- UI main isolate は PTY read/write 待ちで block しない。

### Phase 3 — Dart-only VT core（12–18 person-weeks）

目的: 描画とは独立した、deterministic で fuzz 可能な terminal state machine を作る。

- [ ] streaming UTF-8 decoder と parser table generator
- [ ] C0/ESC/CSI/OSC/DCS/APC parser
- [ ] typed-array grid、cursor、margins、tabstops、modes
- [ ] SGR、palette、primary/alternate screen
- [ ] wide/grapheme cells と resize/reflow
- [ ] paged scrollback、viewport、selection/search primitives
- [ ] query/reply encoder と PTY write connection
- [ ] snapshot formatter と readable test diagnostics
- [ ] parser corpus、property tests、fuzz seeds

終了条件:

- shell prompt、`less`、`top`、`vim` の記録 stream を期待 snapshot に再生できる。
- byte chunk を全分割位置で変えても final state が一致する。
- malformed/巨大 sequence で上限を越えず、次の printable text へ復帰する。
- baseline machine で parser throughput の provisional budget を満たす。
- core package は AppKit、Metal、FFI に依存しない。

### Phase 4 — CoreText + Metal renderer（12–20 person-weeks）

目的: correctness reference を持つ高速 renderer を実装する。

- [ ] headless/reference renderer と golden image format
- [ ] CoreText font catalog、fallback、metrics、shaping cache
- [ ] monochrome/color glyph atlas
- [ ] Metal cell/glyph/decoration/cursor/selection pipelines
- [ ] damage coalescing、frame generation、stale-frame discard
- [ ] resize/scale/font change の full rebuild
- [ ] cursor blink、visual bell、occlusion pause
- [ ] device/shader/drawable failure recovery
- [ ] frame timing、atlas hit rate、uploaded byte count の metrics

終了条件:

- Latin、CJK、emoji、combining、wide cell、ligature の golden が 1x/2x で通る。
- 60/120 Hz display で同じ terminal state を安定表示できる。
- 大量 output 中も window move/resize と key input が応答する。
- renderer が遅れた際に unbounded queue や stale frame の連続描画が起きない。
- idle/occluded pane は不要な frame を生成しない。

### Phase 5 — Production input と interaction（8–13 person-weeks）

目的: 日本語を含む日常入力、選択、copy/paste を完成させる。

- [ ] mode-aware key encoder と configurable keybind engine
- [ ] `NSTextInputClient` と preedit overlay
- [ ] US/JIS/dead key/CJK/emoji/key repeat matrix
- [ ] mouse protocol と local selection arbitration
- [ ] character/word/line selection、drag autoscroll
- [ ] precision trackpad scroll
- [ ] clipboard、bracketed paste、paste safety
- [ ] hyperlink hover/open と URL safety
- [ ] VoiceOver の最小 visible text/selection/cursor support

終了条件:

- 日本語 IME の compose/convert/commit/cancel と candidate 位置が正しい。
- tmux/Neovim の key と mouse mode、通常 shell の選択が共存する。
- 10 MiB paste でも UI が止まらず、PTY queue が上限内に留まる。
- keyboard-only と VoiceOver で prompt、selection、visible output を利用できる。

この段階を最初の **daily-driver alpha** とする。

### Phase 6 — VT/xterm compatibility hardening（12–20 person-weeks）

目的: 「主要アプリがたまたま動く」から、互換性を管理できる状態へ進める。

- [ ] ECMA-48、DEC、xterm の sequence/mode inventory
- [ ] xterm/Ghostty/Kitty との black-box differential harness
- [ ] `vttest` を参考に採用/非採用項目を明文化
- [ ] tmux、ssh、mosh、Neovim、Emacs、ncurses、fzf、lazygit の matrix
- [ ] terminfo source、compile/install/fallback
- [ ] OSC title/cwd/hyperlink/palette/clipboard policy
- [ ] focus/mouse/bracketed paste/query reports
- [ ] parser inspector と sequence trace export
- [ ] compatibility bug の regression corpus 化

終了条件:

- P0 compatibility matrix に既知の silent corruption がない。
- 各 unsupported sequence は「安全に無視」「明示的に非対応」のどちらかである。
- すべての互換性 bug fix に byte-level regression test がある。
- alpha 利用 30 日相当の記録/soak で state divergence と crash がない。

### Phase 7 — Windows、tabs、splits、application UX（10–16 person-weeks）

目的: 単一 pane の製品から native macOS application へ進める。

- [ ] window → tab → split tree → terminal session の state model
- [ ] native tabs と split layout/focus/resize/zoom
- [ ] menu/action registry と command palette
- [ ] title、tab rename/color、cwd inheritance、proxy icon
- [ ] fullscreen、screen migration、restoration、reopen
- [ ] per-pane close と app quit confirmation
- [ ] multiple pane の scheduling/resource budget
- [ ] AppKit unit、integration、UI tests

終了条件:

- 複数 window × 複数 tab × 4 pane を繰り返し作成/復元できる。
- focus、key routing、IME、menu shortcut が別 pane へ漏れない。
- pane close 後に PTY/isolate/Metal/native handle が残らない。
- 1 pane の大量出力が他 pane の入力を飢餓状態にしない。

### Phase 8 — Config、themes、shell integration（8–13 person-weeks）

目的: zero-config と高度な customization を両立する。

- [ ] typed config schema と diagnostics
- [ ] theme/palette/font/window/input/scrollback options
- [ ] declarative keybind と action reference generation
- [ ] safe reload、per-option live/new-session policy
- [ ] light/dark theme と system appearance
- [ ] zsh/bash/fish/nushell integration
- [ ] cwd/title/prompt mark/jump-to-prompt/close hint
- [ ] settings UI と effective-config inspector

終了条件:

- invalid config が app 起動を破壊せず、file/line と修正案を表示する。
- reload 中も pane/PTY が失われない。
- config schema から CLI/help/settings/action docs の整合を検査できる。
- shell integration 無効時も通常の terminal として完全に動く。

### Phase 9 — Modern terminal protocols（12–20 person-weeks）

目的: 現代的 TUI が使う Ghostty クラスの protocol を追加する。

- [ ] Kitty keyboard protocol
- [ ] synchronized output/rendering
- [ ] light/dark notification と extended reports
- [ ] Kitty graphics parse/storage/placement/render
- [ ] image animation と resource eviction
- [ ] desktop notification、progress、semantic prompt extensions
- [ ] OSC 52 confirmation/policy UI
- [ ] protocol-specific fuzz、security、memory tests

終了条件:

- protocol origin terminal の挙動と documented cases を比較済み。
- image/OSC flood で configured memory cap を越えない。
- synchronized rendering が途切れた場合に timeout で表示を復旧する。
- Kitty keyboard を使う Neovim 等と legacy app の両方が regression しない。

### Phase 10 — macOS native polish と accessibility（10–16 person-weeks）

目的: macOS 専用アプリとしての完成度を上げる。

- [ ] Quick Terminal と global shortcut
- [ ] Secure Keyboard Entry と auto/manual indication
- [ ] Quick Look、Services、drag/drop、context menu
- [ ] AppleScript dictionary と object lifecycle
- [ ] App Intents/Shortcuts、notifications
- [ ] complete VoiceOver/Accessibility Inspector pass
- [ ] Reduce Motion/Contrast と localization
- [ ] terminal inspector と diagnostics bundle

終了条件:

- native feature ごとに enable/disable、permission、failure path がある。
- Secure Input は pane/window/app の異常終了後も確実に解除される。
- AppleScript から window/tab/split/input/focus/close を操作できる。
- VoiceOver と Full Keyboard Access の release checklist が全項目通る。

### Phase 11 — Distribution、performance、parity burn-down（12–24 person-weeks）

目的: feature complete build を安全に配布できる release へする。

- [ ] AOT release、Universal Binary、resource layout
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

- [ ] Intel-native no-rebuild runtime handoff と追加互換性証跡（主要ゴール達成後に
  実施し、
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
主要実機 baseline は Apple M1/arm64 とし、x86_64 は cross-build、Rosetta、
Universal audit で主要互換性を受け入れる。Intel-native の追加証跡は上記の
主要ゴール後 follow-up であり、この完了定義の必須条件には含めない。

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
