# Dart Terminal feature matrix

最終更新: 2026-09-05<br>
比較基準: [`ghostty-org/ghostty@d4d8f62262cb1a974a7d2470d5f79f811fab15e4`](https://github.com/ghostty-org/ghostty/tree/d4d8f62262cb1a974a7d2470d5f79f811fab15e4)  
対象: macOS 14 以降、Flutter 不使用<br>
主要実機 baseline: Apple M1/arm64

## 目的と読み方

この表は Ghostty の画面、設定名、内部構造をコピーするための表ではない。
固定コミットで利用者と terminal application に提供される挙動を、Dart で独立実装する
際の受け入れ単位へ分解したものである。製品へ Ghostty、`libghostty`、Ghostty の
Zig/Swift 実装を link または移植しない。比較対象、byte-level oracle、性能基準として
のみ使用する。

Ghostty の互換性判断と同じく、挙動が競合する場合は原則として次を優先する。

1. xterm 互換
2. protocol を定義した terminal の実挙動
3. 広く採用された de facto behavior

優先度は `ROADMAP.md` と同じである。

- **P0**: daily-driver alpha に必須
- **P1**: rich beta と Ghostty クラス評価に必須
- **P2**: parity polish。P0/P1 を不安定にせず追加する
- **対象外**: v1 では意図的に実装しない

「Phase」は最初に production acceptance を要求する段階であり、Phase 0 の spike は
production 実装の代わりではない。`P0 / Phase 7` のような項目は daily-driver 品質には
必須だが、依存する core が安定してから実装することを意味する。

## 調査方法と証跡

GitHub が生成した固定コミットの source archive を展開し、terminal、PTY、renderer、
font、input、config、macOS UI、release workflow の実装とテストを確認した。
調査時 archive の SHA-256 は
`3111538f70b1a7fed43646395906724db9ef92eb85d66410c5bce2067ad2b7d2` である。

下表の `G:` は固定コミット内の path を表す。代表 path だけを記載し、実装の有無を
ファイル名だけで断定せず、関連する dispatch、state、test も確認した。公式の
[feature overview](https://ghostty.org/docs/features)、
[VT overview](https://ghostty.org/docs/vt)、
[configuration reference](https://ghostty.org/docs/config/reference) は利用者向け意味の
照合に使った。公式サイトは更新されるため、機能凍結の根拠は常に pinned source を
優先する。

現在の Dart Terminal は、M1/arm64 Developer JIT / Release AOT の未改変 AppKit
main-thread root、manifest-declared Dart worker helper、generic `View` / `TextView`、
dependency-owned renderer capability、v4 native event、privacy-safe な local-run metadata、
およびtyped pane/session ownerが保持するpersistent login zshまでである。製品
repositoryのnative sourceは削除済みである。通常表示はまだ`TextView`上の
plain-text投影であり、VT coreとMetal rendererは後続Phaseへdeferする。
下表の「現在」が `未実装` でも欠落ではなく、指定 Phase まで明示的に defer した
backlog である。

実機受け入れは Apple M1/arm64 を優先する。x86_64 cross-build、Rosetta、Universal、
Intel-native handoff は、M1 の製品 contract 完了後に行う低優先 follow-up であり、
M1 の各 Phase や主要ゴールの完了条件ではない。

## Runtime、PTY、process lifecycle

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| RT-01 | release AOT root isolate が AppKit main thread に attach し、main run loop を所有しない | P0 | 1 | `G:macos/Sources/App/main.swift`, native macOS app lifecycle | M1 Developer/Release stock root 完了 |
| RT-02 | pane ごとの長寿命 runtime worker と window ごとの render coordinator を起動、停止、異常回収できる | P0 | 1 | `G:src/termio/Thread.zig`, `G:src/renderer/Thread.zig` | M1 Developer/Release process worker の lifecycle/再生成/bounded traffic 完了、pane/render は後続 |
| RT-03 | UI、PTY I/O、terminal state、render resource の thread/owner が一意 | P0 | 1 | `G:src/termio/mailbox.zig`, `G:src/renderer/message.zig` | M1 両 mode の root/process owner、v1–v4 event generation、generic/custom View、dependency-owned TerminalMetalView shell、window/application state、menu action、AppKit handle domain/async destruction、1,000 Window/View handle churn、main-thread diagnostics phase、PTY capabilityとtyped pane/session owner完了。terminal core/render stateは後続 |
| PTY-01 | 1 pane = 1 persistent PTY。slave が controlling terminal になり、新 session/process group を持つ | P0 | 2 | `G:src/pty.zig`, `G:src/pty.c`, `G:src/termio/Exec.zig` | 製品persistent paneとcapability完了 |
| PTY-02 | shell/command を `argv`、`envp`、cwd で起動し、shell interpolation を行わない | P0 | 2 | `G:src/Command.zig`, `G:src/termio/Exec.zig` | `dart_pty_macos` 完了 |
| PTY-03 | macOS login shell、`TERM`、`COLORTERM`、locale、initial cwd が zero-config で妥当 | P0 | 2 | `G:src/termio/Exec.zig`, `G:src/os/shell.zig` | login zsh/cwd/env/TTY contract 完了 |
| PTY-04 | master FD は nonblocking。partial read/write、`EINTR`、`EAGAIN`、順序、bounded backpressure を処理 | P0 | 2 | `G:src/termio/Thread.zig`, `G:src/termio/stream_handler.zig`, `G:src/termio/mailbox.zig` | kqueue/ACK credit/bounded writeに加え、連続read中もcontrolを処理するreactor turn budget完了 |
| PTY-05 | cell/pixel winsize、`TIOCSWINSZ`、`SIGWINCH` が resize に追従 | P0 | 2 | `G:src/pty.zig`, `G:src/termio/Exec.zig` | capability と application resize 接続完了 |
| PTY-06 | Ctrl-C/Z/\\、EOF、foreground/background job、`fg`/`bg`、`stty`、`tty` が PTY semantics で動く | P0 | 2 | `G:src/pty.zig`, `G:src/termio/Exec.zig` | persistent session、AppKit Control-D route、clean/IGNORE_EOF/nonempty/foreground reader/raw/stopped-job実PTY matrixに加え、clean shell exitは自動close、abnormal exitはstatus付きretainまで完了 |
| PTY-07 | EOF、child exit、HUP/TERM/KILL、grace period、`waitpid`、zombie 回収が deterministic | P0 | 2 | `G:src/Command.zig`, `G:src/termio/Exec.zig` | tracked writeからsignal/reap/exit公開までの診断、closing中force、最終期限、classified host終了、kernel statusを使う外部reap回復、runtime worker同時生存回帰まで完了 |
| PTY-08 | current cwd と foreground process を検出し、title/close confirmation/cwd inheritance に使う | P1 | 7 | `G:src/termio/Exec.zig`, `G:macos/Sources/Ghostty/Ghostty.Surface.swift` | live-shell再操作confirmationは完了、process/cwd検出は未実装 |
| PTY-09 | reconnectable session | P2 | 対象外 | pinned target との差は許容。独立 project とする | v1 対象外 |

## Streaming parser と terminal screen

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| PAR-01 | UTF-8 を chunk 境界に依存せず decode。不正 byte の置換と recovery が deterministic | P0 | 3 | `G:src/terminal/UTF8Decoder.zig`, `G:src/terminal/stream.zig` | Dart-only product decoderとvalid/malformed/all-split回帰を完了 |
| PAR-02 | C0/C1、ESC、CSI、OSC、DCS、APC を incremental table-driven state machine で解析 | P0 | 3 | `G:src/terminal/Parser.zig`, `G:src/terminal/parse_table.zig` | 14-state/21-actionの生成tableを使うDart-only product parserと全family/all-split回帰を完了 |
| PAR-03 | CAN/SUB/ESC cancel、unknown sequence、malformed sequence の後に printable text へ復帰 | P0 | 3 | `G:src/terminal/Parser.zig`, parser tests in same file | product parserのcancel/malformed/limit/EOF後recovery回帰を完了 |
| PAR-04 | private marker、intermediate、parameter、subparameter、colon SGR を保持して dispatch | P0 | 3 | `G:src/terminal/csi.zig`, `G:src/terminal/sgr.zig` | retain可能なtyped CSI/DCS headerとして保持・dispatchを完了。SGR適用は後続 |
| PAR-05 | payload/parameter count/numeric value に hard limit。hot path に per-byte allocation、regex、例外なし | P0 | 3 | `G:src/terminal/Parser.zig`, `G:src/terminal/osc.zig`, `G:src/terminal/dcs.zig` | 固定typed bufferとsequence/payload/count/value上限、非保持sequence/payload経路、Release AOT 100 MiB/s gateをproduct parserで完了 |
| SCR-01 | primary/alternate screen、save/restore cursor、cursor shape/blink/visibility | P0 | 3 | `G:src/terminal/Screen.zig`, `G:src/terminal/ScreenSet.zig`, `G:src/terminal/cursor.zig` | shared-resource/independent-state primary・alternate SoA screen、position/rendition save/restore、shape/blink/visibility、DEC 47/1047/1048/1049を完了 |
| SCR-02 | wrap-pending、origin/insert/replace/autowrap/reverse-video mode | P0 | 3 | `G:src/terminal/Terminal.zig`, `G:src/terminal/modes.zig` | typed mode state、home/clamp、atomic resetとnarrow print/editへの適用を完了 |
| SCR-03 | top/bottom、left/right margin と scroll region | P0 | 3 | `G:src/terminal/Screen.zig`, `G:src/terminal/Terminal.zig` | validated vertical/horizontal margin、origin境界、ring/rectangle scroll適用を完了 |
| SCR-04 | cursor movement、erase、ICH/DCH、IL/DL、SU/SD、tab、BS、CR/LF/IND/RI/NEL | P0 | 3 | `G:src/terminal/Terminal.zig`, `G:src/terminal/Tabstops.zig` | allocation-free SoA編集操作、C0/C1/ESC/CSI action sink、chunk-independent統合回帰を完了 |
| SCR-05 | bold/faint/italic/underline variants/blink/inverse/conceal/strike と 16/256/truecolor | P0 | 3 | `G:src/terminal/sgr.zig`, `G:src/terminal/style.zig`, `G:src/terminal/color.zig` | bounded immutable style ID、current/saved rendition、全P0属性、ANSI/extended/default色SGR、typed xterm-256 palette/default色mutationを完了 |
| SCR-06 | wide/continuation cell、combining sequence、zero-width grapheme の invariant を維持 | P0 | 3 | `G:src/terminal/page.zig`, `G:src/terminal/Screen.zig`, `G:src/unicode/grapheme.zig` | Unicode 17 width/grapheme、bounded intern、wide/continuation atomic mutationと1-column containmentを完了 |
| SCR-07 | primary/alternate resize と reflow。cursor、selection、wrapped-line identity を保つ | P0 | 3 | `G:src/terminal/PageList.zig`, `G:src/terminal/Screen.zig` | primary historyを含むatomic reflow、cursor/viewport、reuse epoch付きstable anchorとend-exclusive selectionを完了 |
| SCR-08 | paged bounded scrollback、viewport offset、先頭 eviction が O(page) 以下 | P0 | 3 | `G:src/terminal/PageList.zig`, `G:src/terminal/page.zig`, `G:src/terminal/compress/` | fixed-page SoA履歴、独立line/byte cap、O(1) page eviction、primary capture、bounded viewport、target幅へのhistory repaginationを完了 |
| SCR-09 | row/range damage と monotonic generation。全画面転送を通常 path にしない | P0 | 3/4 | `G:src/terminal/render.zig`, `G:src/renderer/row.zig` | clean→dirty時だけ進むrow version、coalesced半開区間、monotonic screen generation基盤を完了。wire/rendererは後続 |
| SCR-10 | underline color、overline、protected/selective erase | P1 | 6 | `G:src/terminal/style.zig`, `G:src/terminal/Terminal.zig` | 未実装 |
| SCR-11 | hyperlink、semantic prompt、search、selection anchor/word/line semantics | P1 | 3/6 | `G:src/terminal/hyperlink.zig`, `G:src/terminal/search/`, `G:src/terminal/Selection.zig` | cell/word/logical-line selection、semantic row hint、bounded exact forward/backward searchを完了。hyperlink tableと詳細semantic rangeは後続 |
| SCR-12 | versioned snapshot/restore と readable formatter を test/debug oracle にする | P1 | 3 | `G:src/terminal/snapshot/`, `G:src/terminal/formatter.zig` | bounded version 1 terminal-state formatterとfirst-difference diagnosticsを完了。restoreは後続 |

## Queries、modes、modern terminal protocols

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| CAP-01 | DA/DA2、DSR/CPR、DEC private mode、DECRQM の request/reply | P0 | 3/6 | `G:src/terminal/device_attributes.zig`, `G:src/terminal/device_status.zig`, `G:src/terminal/modes.zig` | bounded 7-bit encoder、terminal-core dispatch、raw PTY parse、native write queue connectionを完了 |
| CAP-02 | application cursor/keypad、bracketed paste、focus report | P0 | 3/5 | `G:src/input/key_encode.zig`, `G:src/terminal/paste.zig`, `G:src/terminal/focus.zig` | 未実装 |
| CAP-03 | mouse X10、UTF-8、URXVT、SGR mode/encoding | P0 | 3/5 | `G:src/terminal/mouse.zig`, `G:src/input/mouse_encode.zig` | 未実装 |
| CAP-04 | xterm-256color 互換 terminfo と SSH fallback | P0/P1 | 6/8 | `G:src/terminfo/`, `G:src/cli/ssh.zig` | 未実装 |
| CAP-05 | window/tab title、OSC 7 cwd、OSC 8 hyperlink、palette/default color query/change | P0 | 3/6 | `G:src/terminal/osc/parsers/` | bounded OSC 4/10/11 palette/default色query/changeと104/110/111 resetを完了。title/cwd/hyperlinkは後続 |
| CAP-06 | OSC 52 は read/write policy、confirmation、size limit 付き | P0/P1 | 6/9 | `G:src/terminal/clipboard.zig`, `G:src/terminal/osc/parsers/clipboard_operation.zig` | 未実装 |
| CAP-07 | XTGETTCAP、DECRQSS、window/size report | P1 | 6 | `G:src/terminal/dcs.zig`, `G:src/terminal/size_report.zig` | 未実装 |
| CAP-08 | Kitty keyboard と progressive enhancement。legacy encoding を regression させない | P1 | 9 | `G:src/input/kitty.zig`, `G:src/terminal/kitty/key.zig` | 未実装 |
| CAP-09 | synchronized output/rendering に timeout と bounded pending state | P1 | 9 | `G:src/terminal/modes.zig`, `G:src/renderer/State.zig` | 未実装 |
| CAP-10 | light/dark notification、extended size/Unicode reports | P1 | 9 | `G:src/terminal/size_report.zig`, `G:src/terminal/kitty/color.zig` | 未実装 |
| CAP-11 | Kitty graphics: transmit/storage/placement/z-index/scroll/erase/animation/eviction | P1 | 9 | `G:src/terminal/kitty/graphics*.zig`, `G:src/renderer/image.zig` | 未実装 |
| CAP-12 | desktop notification、progress、semantic prompt extensions は rate/memory limited | P1 | 9 | `G:src/terminal/osc/parsers/kitty_desktop_notification.zig`, `semantic_prompt.zig` | 未実装 |
| CAP-13 | Sixel | P2 | 対象外 | pinned parity より、実利用要求を確認して別判定 | v1 保留 |
| CAP-14 | custom user shader | P2 | 対象外 | `G:src/renderer/shadertoy.zig` | 安全な compile/cache 設計まで保留 |

## Unicode、font、CoreText

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| TXT-01 | extended grapheme、emoji ZWJ/VS/RI、combining sequence | P0 | 3/4 | `G:src/unicode/grapheme.zig`, `G:src/terminal/page.zig` | CoreText/format gate |
| TXT-02 | East Asian width と ambiguous-width policy。terminal mode と app cursor width が同期 | P0 | 3 | `G:src/unicode/props.zig`, `G:src/terminal/size_report.zig` | 未実装 |
| TXT-03 | CoreText discovery、ordered fallback、Apple Color Emoji、symbol font | P0 | 4 | `G:src/font/discovery.zig`, `G:src/font/DeferredFace.zig`, `G:src/font/face/coretext.zig` | generation-owned catalogとCJK/color emoji fallback resolveを完了。全run shapingは同roadmap項目の次subtask |
| TXT-04 | regular/bold/italic/bold-italic、synthetic style policy | P0 | 4 | `G:src/font/Collection.zig`, `G:src/font/face/coretext.zig` | actual/syntheticを区別する4-style policyとstable face identityを完了 |
| TXT-05 | cell metrics、baseline、underline/strike、1x/2x/scale/zoom の pixel alignment | P0 | 4 | `G:src/font/Metrics.zig`, `G:src/renderer/generic.zig` | cell advance/height、baseline、underline/strike metricsを完了。scale/pixel alignmentはresize/rebuild項目で接続 |
| TXT-06 | Latin/CJK/emoji/Powerline/box/Nerd Font golden corpus | P0 | 4 | `G:src/font/res/`, `G:src/font/sprite/`, font tests | corpus Phase 0 |
| TXT-07 | ligature/OpenType feature toggle と cursor 下の shaping break | P1 | 4/8 | `G:src/font/shaper/coretext.zig`, `G:src/font/shaper/feature.zig` | Phase 0 gate |
| TXT-08 | variable axes、codepoint override、fallback diagnostics | P1 | 4/8 | `G:src/font/opentype/`, `G:src/font/CodepointMap.zig` | 未実装 |
| TXT-09 | grapheme 内 Arabic/Hebrew shaping。terminal layout 自体は LTR | P1 | 4 | `G:src/font/shaper/testdata/arabic.txt`, `G:src/font/shaper/coretext.zig` | Phase 0 で設計確認 |
| TXT-10 | synthetic box/block/braille/Powerline glyph で cell gap を防ぐ | P1 | 4 | `G:src/font/sprite/draw/` | 未実装 |

## Metal renderer と frame scheduling

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| REN-01 | `MTKView`/Metal lifecycle、drawable resize/backing scale、device/shader/drawable failure path | P0 | 4 | `G:src/renderer/Metal.zig`, `G:macos/Sources/Helpers/MetalView.swift` | Phase 0 gate に加え、Phase 1 で system device を持つ paused/on-demand TerminalMetalView shell の生成・attach 境界を完了。renderer lifecycle/failure path は Phase 4 |
| REN-02 | background、cell background、glyph、decoration、cursor、selection を packed instance で描画 | P0 | 4 | `G:src/renderer/shaders/shaders.metal`, `G:src/renderer/cell.zig` | Phase 0 gate |
| REN-03 | grayscale/color atlas、growth/eviction/generation validation | P0 | 4 | `G:src/font/Atlas.zig`, `G:src/renderer/generic.zig` | Phase 0 gate |
| REN-04 | damage coalescing、stale generation discard、full snapshot は recovery/resize のみ | P0 | 4 | `G:src/renderer/row.zig`, `G:src/renderer/State.zig`, `G:src/renderer/message.zig` | ADR gate |
| REN-05 | double/triple buffering と submit token/fence。GPU 完了前に buffer を再利用しない | P0 | 4 | `G:src/renderer/metal/Frame.zig`, `G:src/renderer/metal/buffer.zig` | ADR gate |
| REN-06 | vsync/frame pacing、cursor blink、occlusion pause、resume full redraw | P0 | 4 | `G:src/renderer/generic.zig`, `G:src/renderer/Thread.zig` | benchmark gate |
| REN-07 | deterministic screenshot と CPU/reference renderer を golden oracle にする | P0 | 4 | `G:src/terminal/render.zig`, renderer test paths | bounded Dart-only RGBA compositor、versioned checksum付きgolden format、1x/2x fixture、first-pixel診断を完了。Metal screenshot接続は後続 |
| REN-08 | image/search/hyperlink/inspector overlay、P3/sRGB blending | P1 | 4/9 | `G:src/renderer/image.zig`, `Overlay.zig`, `link.zig` | 未実装 |
| REN-09 | 60/120 Hz、複数 window/pane の fair scheduling。遅延時は中間 frame を捨てる | P1 | 4/7 | `G:src/renderer/Thread.zig`, `G:src/renderer/generic.zig` | benchmark gate |

## Keyboard、IME、mouse、selection、clipboard

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| IN-01 | physical key、produced text、modifiers、repeat を別 field として保持 | P0 | 5 | `G:src/input/key.zig`, `G:macos/Sources/Ghostty/Ghostty.Input.swift` | field分離済みの一部key eventと、AppKit responderへ二重配送しないwindow単位のDart専有routing基盤まで完了 |
| IN-02 | US/JIS/layout switch/dead key/function/navigation/keypad と terminal mode-aware encoding | P0 | 5 | `G:src/input/KeymapDarwin.zig`, `G:src/input/key_encode.zig`, keyboard tests | 未実装 |
| IN-03 | `NSTextInputClient` marked/commit/cancel/replacement/candidate rect。raw key と IME を二重送信しない | P0 | 5 | `G:macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Phase 0 gate |
| IN-04 | 日本語 IME、emoji picker、Unicode Hex Input、key repeat の automated/manual matrix | P0 | 5 | same AppKit surface implementation and macOS tests | Phase 0 gate |
| IN-05 | char/word/line multi-click selection、drag、autoscroll | P0 | 5 | `G:src/terminal/Selection.zig`, `SelectionGesture.zig`, SurfaceView | 未実装 |
| IN-06 | precision/momentum scroll と terminal mouse report/local selection arbitration | P0 | 5 | `G:src/input/mouse.zig`, `G:src/input/mouse_encode.zig` | 未実装 |
| IN-07 | standard clipboard、bracketed paste、newline normalization | P0 | 5 | `G:src/input/paste.zig`, `G:src/terminal/paste.zig`, NSPasteboard helpers | plain-text general pasteboard と明示的 Paste action の基盤のみ完了。bracketed paste/newline policy は Phase 5 |
| IN-08 | multiline/control paste confirmation と large-paste bounded throttle | P0 | 5 | `G:macos/Sources/Features/ClipboardConfirmation/`, `G:src/termio/mailbox.zig` | 未実装 |
| IN-09 | keybind/action registry、conflict、unbound/passthrough、menu shortcut arbitration | P0 | 5/8 | `G:src/input/Binding.zig`, `G:src/input/config.zig`, MenuShortcutManager | 未実装 |
| IN-10 | Option-click cursor、semantic prompt selection、drag/drop、Services、Quick Look | P1/P2 | 5/10 | macOS Surface View, `G:macos/Sources/Features/Services/` | 未実装 |

## Native macOS application experience

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| UI-01 | multiple windows、native tabs、split tree、focus traversal | P0 | 7 | `G:macos/Sources/Features/Terminal/`, `Splits/SplitTree.swift` | 単一 window のみ |
| UI-02 | split resize/equalize/zoom/min cell、pane/tab title/color、cwd inheritance | P0 | 7 | `G:macos/Sources/Features/Splits/`, `Terminal/` | 未実装 |
| UI-03 | fullscreen、geometry、display/scale migration、reopen/restoration | P0 | 7 | `G:macos/Sources/Helpers/Fullscreen.swift`, `TerminalRestorable.swift` | v3 display/scale event substrate のみ完了。migration policy 等は未実装 |
| UI-04 | close/quit confirmation と active process detection。pane resource を完全 teardown | P0 | 7 | `G:macos/Sources/Features/Terminal/`, Ghostty surface process metadata | live-shell再操作confirmation、clean shell auto-close、abnormal shell retain後のone-step close、pane teardown完了。active-process検出はPhase 7 |
| UI-05 | standard menu と Edit/Window/Shell/View action。terminal input と競合しない | P0 | 7 | `G:macos/Sources/App/MainMenu.xib`, action registry | 最小 Application/File/Edit menu と action routing 基盤は完了。完全な action registry/競合解決は Phase 7/8 |
| UI-06 | Quick Terminal、global shortcut、screen selection/animation | P1 | 10 | `G:macos/Sources/Features/QuickTerminal/`, `Global Keybinds/` | 未実装 |
| UI-07 | proxy icon、Quick Look、Secure Keyboard Entry indication | P1 | 10 | macOS Terminal/Surface, `G:macos/Sources/Features/Secure Input/` | 未実装 |
| UI-08 | AppleScript application→windows→tabs→terminals と App Intents | P1 | 10 | `G:macos/Sources/Features/AppleScript/`, `App Intents/` | 未実装 |
| UI-09 | settings UI、command palette、terminal inspector | P1 | 8/10 | `G:macos/Sources/Features/Settings/`, `Command Palette/`, InspectorView | 未実装 |

## Configuration、theme、shell integration

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| CFG-01 | typed schema と default/file/CLI priority。zero-config default | P0 | 8 | `G:src/config/Config.zig`, `G:src/config/file_load.zig` | 起動引数2個のみ |
| CFG-02 | location/include、diagnostic file/line/column、invalid config で起動を破壊しない | P0 | 8 | `G:src/config/file_load.zig`, `ErrorList.zig` | 未実装 |
| CFG-03 | palette/font/padding/scrollback/cursor/shell/cwd/keybind の typed options | P0 | 8 | `G:src/config/Config.zig`, `theme.zig`, `key.zig` | 未実装 |
| CFG-04 | reload と live/new-session/restart policy を option ごとに宣言 | P0 | 8 | `G:src/config/Config.zig`, macOS Config | 未実装 |
| CFG-05 | light/dark pair、custom/built-in themes、system appearance | P1 | 8 | `G:src/config/theme.zig`, theme testdata | 未実装 |
| CFG-06 | zsh/bash/fish/nushell integration、cwd/title/prompt mark/close hint | P1 | 8 | `G:src/shell-integration/`, `G:src/termio/shell_integration.zig` | 未実装 |
| CFG-07 | deprecated migration warning、effective config/action docs の schema generation | P1 | 8 | `G:src/config/`, CLI config commands | 未実装 |

## Accessibility、security、privacy

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| AX-01 | visible text、selection、cursor、focus を VoiceOver に公開し change notification を送る | P0 | 5/10 | `G:macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | 未実装 |
| AX-02 | Full Keyboard Access、Reduce Motion、Increase Contrast、Differentiate Without Color | P0 | 5/10 | macOS Surface/Splits/QuickTerminal accessibility code | 未実装 |
| AX-03 | IME preedit と accessibility selection/range/candidate rect が同じ text model を使う | P0 | 5 | `G:macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Phase 0 gate |
| SEC-01 | parser payload/count/value、scrollback、hyperlink、image、queue に hard cap | P0 | 3/5/9 | `G:src/terminal/Parser.zig`, kitty graphics storage, termio mailbox | parser、64-byte reply、scrollback、selection extraction、word scan、search query/work/result capを完了。後続hyperlink/image/queue capは未実装 |
| SEC-02 | URL scheme allowlist/sanitization、OSC 52 policy、paste confirmation、notification rate limit | P0/P1 | 5/9 | `G:macos/Sources/Helpers/UntrustedURL.swift`, clipboard confirmation | 未実装 |
| SEC-03 | fork child は async-signal-safe setup と `execve` だけ。Dart runtime/ObjC allocation を呼ばない | P0 | 2 | `G:src/pty.zig`, `G:src/Command.zig` | `dart_pty_macos` child symbol audit 完了 |
| SEC-04 | Secure Input を abnormal teardown 後も必ず解除 | P1 | 10 | `G:macos/Sources/Features/Secure Input/SecureInput.swift` | 未実装 |
| SEC-05 | crash/update/clipboard/shell integration の data flow と opt-in/out を privacy 文書化 | P0 | 10/11 | pinned crash/update/config behaviorを比較対象にする | Phase 1 local-run metadata の local-only/no-content policy を文書化。crash/update/clipboard/shell 全体は Phase 10/11 |

## Compatibility、performance、distribution

| ID | parity unit / acceptance | 優先度 | Phase | pinned Ghostty evidence | 現在 |
| --- | --- | --- | --- | --- | --- |
| QA-01 | byte corpus、all chunk splits、property/fuzz、snapshot diagnostics | P0 | 3/6 | parser tests, `G:src/terminal/snapshot/`, `G:test/fuzz-libghostty/` | product parser全family・UTF-8 precedence、version 1 final-state/diagnostics、4件のsemantic corpusとshell/less/top/vim記録をall-split/bytewise検証。固定seed property、7件の境界別fuzz seed、112 mutationを完了。black-box differentialはPhase 6 |
| QA-02 | xterm/Ghostty/Kitty black-box differential と real-app matrix。bug を最小 byte regression に還元 | P1 | 6 | `G:src/terminal/` tests and VT C examples | 未実装 |
| PERF-01 | parser AOT ≥100 MiB/s、AppKit event p95 <1 ms、key→PTY p95 <2 ms | P0 | 0–11 | `G:src/benchmark/`, `G:macos/Tests/BenchmarkTests.swift` | product parserはRelease AOT反復で107.67–111.92 MiB/sを確認。AppKit event/key→PTYの継続gateは後続Phase |
| PERF-02 | 100 MiB burst で UI hang 0、bounded memory/queue。1 pane flood が他 pane latency を2倍にしない | P0/P1 | 2/7/11 | Ghostty termio/renderer threaded design | PTY reactorの連続output下force-close fairness完了。100 MiB/UI/複数paneは後続 |
| REL-01 | child/GPU/runtime-worker fault、late event/double dispose、sleep/wake/display change、24/72h soak | P0/P1 | 1–11 | pinned tests, crash and renderer recovery paths | M1 両 mode の process fault、malformed/late event、double dispose/shutdown、1,000 Window/View leak gate、early/nonzero diagnostic metadata 完了。GPU/sleep/soak は後続 |
| DIST-01 | release AOT `.app`、arm64/x86_64、Universal Binary | P0 | 1/11 | native Ghostty app and universal release workflow | stock-runtime M1 arm64 Release 完了。x86_64/Universal は低優先 follow-up |
| DIST-02 | Developer ID、hardened runtime、notarization、minimal entitlements | P0/P1 | 11 | `G:.github/workflows/release-tag.yml`, `G:macos/Ghostty.entitlements` | 未実装 |
| DIST-03 | signed update feed、rollback/failure path、release notes | P2 | 11 | `G:macos/Sources/Features/Update/`, `G:dist/macos/` | 未実装 |
| DIST-04 | local crash/hang metadata と privacy-safe diagnostics | P1 | 11 | `G:src/crash/`, release dSYM workflow | Phase 1 で local-run metadata、previous-unclean marker、Unified Logging、retention/privacy contract を完了。crash/hang report、dSYM、consent は Phase 11 |

## 明示的な非目標

| ID | 非目標 | 理由 |
| --- | --- | --- |
| OUT-01 | Ghostty UI、設定名、内部型、Zig/Swift source のコピー | 同等とは observable behavior と品質 class であり、製品 identity の複製ではない |
| OUT-02 | Ghostty/libghostty の product link | terminal semantics を Dart で実装するというプロジェクト境界に反する |
| OUT-03 | Ghostty config 完全互換 | typed Dart schema を優先し、必要な移行補助だけを検討する |
| OUT-04 | v1 Linux/Windows | macOS 版の correctness、IME、Metal、配布品質を先に閉じる |
| OUT-05 | 独自 shell | persistent PTY 上で利用者の shell/application を正しく動かすことが目的 |
| OUT-06 | source-level/perf-level 完全同一 | 同じ Mac/corpus で ROADMAP の relative gate を満たすことを parity とする |

## Phase 0 で凍結する gate

この matrix から Phase 0 に直接入る検証は次の七つである。

1. `RT-01`: release AOT + AppKit main-thread root isolate
2. `RT-02`: long-lived worker isolate lifecycle と transfer throughput
   （Phase 0 の歴史的 spike。製品は公式 Dart process worker を選定）
3. `PTY-01/04/05/06/07`, `SEC-03`: safe PTY child path と 64 KiB 以上の batch
4. `REN-01/02/03/05/06`: 100,000 instance Metal frame と buffer lifetime
5. `TXT-01/03/04/05/07/09`: CoreText run/fallback/emoji/ligature
6. `IN-03/04`, `AX-03`: Japanese marked text と candidate rect
7. `PAR-01/02/03/05`, `SCR-06/08/09`, `PERF-01/02`: benchmark/corpus/packed transfer

一つでも実機で成立しない場合は production feature phase へ進まず、該当する境界を
ADR で再決定する。固定コミット以後に Ghostty が追加した機能は、この matrix を暗黙に
変更せず、milestone 更新時の明示的な再 pin と差分レビューでのみ取り込む。
