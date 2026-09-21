# CM-12 R0 hidden manual qualification checklist

日付: 2026-09-22
状態: 完了（R0 hidden qualification pass）

## 目的と判定規則

R0 hidden candidateのJapanese IME、keyboard-only、VoiceOver、appearance、scale、small-pane、
alternate-screen／TUI共存を実AppKitで確認する。通常releaseのdefaultは変更せず、各candidateは
明示的な`notes=true`と`/private/tmp`配下の一時`XDG_STATE_HOME`だけを使う。

- `pass`: 記載した実runtime／実system stateで期待結果を直接観測した。
- `fail`: 機能、privacy、input、focus、geometry、cleanupのいずれかが期待結果と異なる。R0を停止する。
- `not available`: 必要な物理hardwareまたはthird-party executableが検証hostにない。推測でpassにしない。
- Note本文、persistent ID、timestamp、path、terminal text、process IDは結果表へ記録しない。
- Wrong-context attachment、store overwrite、本文/privacy leak、unintended PTY byte、terminal geometry change、
  IME／accessibility regressionは一件でもR0 failureとする。

## Candidateと安全な起動

対象はmacOS 26.6.2、Apple M1／arm64のfresh Developer JIT／Release AOT bundleとする。
各modeで別の一時directoryを作り、終了後にその明示pathだけを削除する。

```shell
manual_state="$(mktemp -d /private/tmp/dart-terminal-note-r0-manual.XXXXXX)"
XDG_STATE_HOME="$manual_state" DART_SUPPRESS_ANALYTICS=true \
  make RUNTIME_ARCH=arm64 \
  RUNTIME_ARGUMENTS='--no-config --notes=true --notes-on-return=true --notes-next-prompt=false --notes-font-size=15' \
  developer-jit-run
```

Release AOTでは末尾targetだけを`release-aot-run`へ置き換える。12／24 ptのcaseは
`--notes-font-size`だけを変更し、同じstoreを再利用しない。起動前後にnormal user state directoryへ
Note store accessがないこと、一時store以外へartifactが残らないことを確認する。

## A. Japanese IMEとinput isolation

1. `Control+Command+N`でeditorを開き、日本語ローマ字入力を選ぶ。
2. 非機密の短い語をpreeditし、候補windowがNote caret付近へanchorされることを確認する。
3. 候補を一回commitし、`Command+Return`で一回だけ保存する。Terminal preedit、terminal text、PTY inputは変化しない。
4. 別draftでmarked textを作り、EscapeでcompositionをcancelしてからCancel／Discardを完了する。Terminal Escapeは0 byte。
5. Editor中にraw key、paste、scrollを使い、Note側だけが一回consumeし、terminal selection／mouse report／scrollが変化しないことを確認する。

合格条件: candidate anchor true、commit once、cancel empty、terminal preedit 0、PTY byte 0、owner復帰一回。

## B. Keyboard-onlyとfocus order

1. Pointerを使わず`Control+Command+N`、Tab／Shift-Tab、arrow、Space／Return、Escapeで
   badge→rail header→collection→card body→card actionへ移動する。
2. Create、edit、color、On Return trigger、Move Earlier／Later、resolve／reopen、delete confirmationを一回ずつ実行する。
3. Current／Detachedを切り替え、明示的reattachだけが現在terminalへattachすることを確認する。
4. Focus ringが常に見え、EscapeまたはFocus Terminal actionで同じpaneのterminal responderへ戻ることを確認する。
5. 同じpaneのterminal↔NoteではDEC 1004 focus report 0、別paneへ移る場合だけold blur 1／new focus 1であることを確認する。

合格条件: mouse 0で全flow到達、keyboard trap 0、action duplicate 0、terminal command insertion 0、focus order deterministic。

## C. VoiceOverとaccessibility tree

1. Collapsed時、terminal text areaのsiblingとしてbody-freeな`Notes` button一つだけが見えることを
   VoiceOver／Accessibility treeで確認する。
2. Explicit open後、`Notes` group、toolbar、Current／Detached selector、scrollable list、ordered card group、
   visible body、status、actionsの順で移動する。Internal ID、timestamp、detached reasonは公開されない。
3. Editorのgroup、multiline body、color、trigger、Save／Cancel／Discard／Keep Editingがlocalized labelを持ち、
   keyboard順とspoken orderが一致することを確認する。
4. Auto dueはterminal focusを移さず、本文を含まないready countを一batch一回だけannounceする。
5. Collapse、background、occlusion、pane close後にcard bodyまたはdisposed elementがtreeへ残らない。

合格条件: bodyはexplicitly visibleなsurfaceだけ、generic announcement一回、focus steal 0、stale element 0。

## D. Appearance、font、scale、small pane

1. 12／15／24 ptで別candidateを起動し、English／Japanese label、body、marked text、selection、focus ring、
   narrow／normal railにclippingまたはoverlapがないことを確認する。
2. Light／Darkをlive変更し、opaque sticky-card surface、text、status shape、selection、focus ringを確認する。
   Terminal background opacityやwallpaperがcard本文へ透過しない。
3. Increase Contrast、Differentiate Without Color、Reduce Motionをstandard System Settingsから一つずつlive変更する。
   Draft、selection、scroll、owner、card identityを保持し、non-color state cueを残し、Reduce Motion時はNote transitionを補間しない。
4. Retina 2×と、物理的に利用可能なら1×または異なるscaleのdisplayへwindowを移動する。Glyph、caret、hit target、
   card edgeがlogical geometryと一致し、double scalingがないことを確認する。
5. Paneを264×184 pt未満へ縮め、本文を含まないsmall-pane badgeだけ、rail 0、due ack 0であることを確認する。
   元へ戻すと同じcard identityで復帰し、terminal rows／columns／drawable／winsizeはNote開閉だけでは変化しない。

合格条件: visual／non-color識別、content opacity、owner/draft保持、Note由来geometry delta 0。利用できない物理scaleは`not available`。

## E. Alternate screen、Vim、Codex、mouse TUI

1. 実alternate screen／Vimでmouse reporting、application cursor、bracketed paste、focus reportingを有効にする。
2. Passive Noteはbadgeだけで、明示open前にrailを展開しない。Open／closeしてもscreen、mode、viewport、selection、
   preedit、cursor phase、terminal accessibility snapshotが変わらない。
3. Note bounds内のclick／drag／scrollはNote actionだけを一回行い、terminal mouse protocol、selection、scrollへ0件とする。
   Bounds外は既存TUI arbitrationを維持する。
4. On Return dueはrail一つをnon-blocking表示し、TUI inputを継続できる。Visible ack前のconsume 0。
5. 利用可能なら実Codex TUIでも同じbadge／explicit open／input isolationを確認する。利用不能時は独立して`not available`とする。

合格条件: TUI state delta 0、terminal input block 0、unintended PTY/mouse byte 0、rail一つ、cleanup owner 0。

## F. Runtime parity、privacy、cleanup

1. A〜Eの適用可能なcaseをDeveloper JITとRelease AOTで繰り返し、同じrole、label、focus、layout、input isolationを確認する。
2. Appを通常終了し、shell、worker、native surface、text client、window handleが残らないことを確認する。
3. 一時store以外のNote fileにaccessせず、結果、console、diagnostics、window title、notificationへ本文、ID、time、color、trigger、pathが出ないことを確認する。
4. System appearance、accessibility preference、input sourceを開始時の値へ戻し、作成した明示的な一時directoryだけを削除する。

## Content-free結果表

| Case | Developer JIT | Release AOT | Evidence |
| --- | --- | --- | --- |
| A Japanese IME／isolation | pass | pass | 両runtimeで実system IME key eventを使用。AOTはinline live conversionをNote caretへanchorし、commit/save一回、Escapeでmarked rangeを除去、terminal text delta 0、PTY=0 |
| B Keyboard-only／focus | pass | pass | reachability=true、deterministic=true、trap=0、duplicate=0、terminal_insert=0 |
| C VoiceOver／AX tree | pass | pass | collapsed／expanded／editor role・順序・stale=pass。両runtimeで実VoiceOver有効、caption panel有効を確認してOn Returnを実minimize→returnで一回発火。rail一回、terminal responder保持、generic announcement生成一回、本文非含有。background／occlusion body=0、復帰後は同一bodyを一回だけ再公開 |
| D 12／15／24 pt、Light／Dark | pass | pass | clipping=0、overlap=0、opacity=true、identity=true、live_theme=true |
| D Contrast／non-color／motion | pass | pass | live_update=true、non_color=true、reduced_motion=true、identity=true |
| D Retina 2× | pass | pass | physical_scale=2.0、logical_geometry=true、double_scale=0 |
| D 1×／alternate physical scale | not available | not available | connected alternate physical display=0 |
| D Small pane | pass | pass | body_free_badge=true、rail=0、false_ack=0、identity=true、geometry_delta=0 |
| E Alternate screen／Vim／mouse TUI | pass | pass | mode_delta=0、input_block=0、Note-origin mouse／PTY=0、owners=0 |
| E Codex TUI | pass | pass | executable=true、trust_grant=0、input_isolation=true、owners=0 |
| F Privacy／cleanup | pass | pass | body／ID／path leak=0、candidate owners=0、VoiceOver off、input source ABC、appearance／accessibility設定復元、検証用一時directory 15件削除済み |

## 完了結果と環境制約

- Release AOT candidateを前面化し、Note本文を表示した状態からSystem Settingsへ移動してwindowをしまう実遷移を行った。
  background／occlusion中のAccessibility treeはbody 0、candidateをRaiseした復帰後は同一bodyを一回だけ再公開し、
  stale element 0を確認した。本文そのものは結果表へ記録していない。
- Release AOTでは入力ソースを日本語へ一時変更し、物理key eventによるinline live conversion、marked text、確定、
  Escape cancellationを実candidate上で直接観測した。Terminal accessibility valueは全操作の前後で同一だった。
- Release AOTではVoiceOverを実際に有効化し、既存のcaption panel設定が有効であることを確認した。On Returnの
  minimize→returnはrailを一回だけ自動展開し、terminal first responderを保持した。同じproduction pathは本文を使わない
  localized ready countを`NSAccessibilityAnnouncementRequestedNotification`としてgenerationごとに一回だけ送る。
  Developer JITでもfresh temporary storeから同じminimize→returnを一回実施し、同じ自動rail、terminal responder保持、
  body-free generic announcement pathを確認した。両candidate終了後にVoiceOverをoff、入力ソースをABCへ戻した。
- 12 pt Release AOT candidateを最初に起動した時点でmacOSがlockされ、Computer Useがautomatic unlockできなかった。Candidateを停止してunlock後に再開し、
  fresh 12／24 pt editor／card、Dark、Contrast、Differentiate Without Color、Reduce Motionを実画面で完了した。
- 両candidateはordered shutdownを完了し、各worker、PTY、native surface ownerを解放した。明示した検証用temporary storeと
  module cacheの計15 directoryだけを削除し、全path absent、build/runtime candidate process 0を確認した。
  既に起動していた通常インストール版は検証候補ではないため終了・変更していない。

## Automated companion evidence

`make RUNTIME_ARCH=arm64 contextual-memory-r0-qualification`はpure／codec／fault／native／product、
actual AppKit 1×／2× native apply、Developer JIT／Release AOT、alternate-screen／mouse-mode sentinel、
arm64／x86_64／Universal、privacy／resource／teardownを検証する。ただしsystem IME、spoken VoiceOver、
実system preference、物理display、視覚品質のmanual claimは行わないため、この表の代用にはしない。
