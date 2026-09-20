# Phase 7 — Context Dock focus reactivation switch

## 目的

foreground process実行中にapplicationのfocusを外して戻した後も、Process Inspectorから
保持済みDirectory Navigatorへ手動で切り替えられるようにする。

## 背景

ECHO-offまたはmanual Secure Input中は、command開始前に確定したDirectory snapshotだけを
read-only表示する実装を追加した。初回の切替は成功するが、applicationを非activeにして再度activeにすると
Process Inspectorへ戻り、Control-Shift-Command-NによるDirectory表示が利用できなくなる。

## 範囲

- application active／inactive遷移時のprocess state、Directory snapshot、display authorityを調査する。
- 同じwindow、pane、session、foreground jobへ戻った場合に限り、安全な保持snapshotを再利用する。
- shortcut、menu、Command Paletteの共有action availabilityと表示切替を修正する。
- ECHO-offおよびmanual Secure Inputを含む回帰testを追加する。

## 対象外

- 異なるpane、session、foreground process groupへDirectory snapshotを引き継ぐこと。
- app非active中のfilesystem観測、process詳細取得、background polling。
- SSH先process introspectionおよび新しいshortcutの追加。

## 依存関係

- `TerminalContextDockProcessController`のwindow eligibility、job identity、display override。
- `TerminalContextDockDirectoryController`のretained snapshotとfresh observation policy。
- application activation policy、Secure Keyboard Entry、Context Dock presenterの再同期順序。

## リスク

- app非active中にpathやprocess argvを再観測すると既存privacy境界を破る。
- pane／session／PGIDが変わった後に古いtreeを表示すると、誤ったpath操作や情報表示につながる。
- active復帰時のcontroller同期順序によって、一時的に保持snapshotが消去される可能性がある。

## 完了条件

- 同一jobのfocus round trip後もcontent toggleが利用でき、保持済みtreeをread-only表示できる。
- app非active中は新しいfilesystem／process観測を開始せず、PTY inputも発生しない。
- pane、session、PGID、Dock visibilityの境界を越えるsnapshotはfail closedで破棄される。
- job終了後は従来どおり一回のfresh Directory refreshへ戻る。

## 検証方針

- controller unitでactive → inactive → activeの同期順序とaction availabilityを固定する。
- native-content integrationで実foreground process中のfocus round trip、menu action、保持tree、
  operation 0、PTY write 0をDeveloper JIT／Release AOTの両方で確認する。
- formatter、静的解析、関連test、repository全体test、生成証跡を再実行する。

## 調査記録

### 2026-09-20 — 着手時の仮説

- process controllerはapp非active時にwindow stateを削除し、再active時には同じjobでも新しいstateを生成する。
- directory controllerもfresh observation不可をprivacy unavailableとして処理し、保持treeを失う可能性がある。
- 再active後にProcess Inspectorだけは再取得できても、Directoryのdisplay authorityが成立しないため
  content toggleがdisabledになると予想する。codeと回帰fixtureで確認する。

### 2026-09-20 — 原因確認

- productの`canPresentWindow`はapplication active、native window visibility、focusを同時に要求する。
- applicationが非activeになるとSecure Keyboard Entryのstatus変更がprocess controllerの再同期を予約する。
  この再同期で`canPresentWindow == false`となり、既存window stateを`_removeWindow`で削除する。
- state削除により`canRetainDirectoryPane`もfalseになる。続くDirectory同期はECHO-off中のfresh observationを
  許可できず、確定済みtreeを`privacyUnavailable`へ置換する。
- application復帰後は同じforeground jobのProcess Inspectorを新しいauthority epochで再取得できるが、
  Directory snapshotは既にないためdisplay authorityが成立せず、content toggleがdisabledになる。
- focus-loss event単体はprocess詳細を直接観測しないが、Secure Inputの非active遷移から予約される同期との
  組み合わせで現象が再現する。shortcut配送やmenu metadataは原因ではない。

## 採用設計

- 非表示理由がapplicationのfocus round tripであり、同じactive logical windowがvisibleな場合だけ、process
  controllerをcontent-freeなpresentation-suspended状態にする。
- suspended状態ではprocess path／argv／member、rich request、poll、表示overrideを破棄する。一方で既に確定した
  Directory snapshotのretention authorityと、照合用のsession／foreground PGIDだけを保持する。
- application復帰時にpane、session、foreground PGIDが一致すれば、Directory snapshotを凍結したまま新しい
  Process Inspector authorityを取得する。不一致ならretained Directoryを明示的にinvalidateする。
- 非active中はDirectory snapshotを画面へ投影せず、新規filesystem operationも開始しない。
- 別windowへのfocus移動、Dock hide、pane／session変更はfocus round tripとみなさず従来どおり破棄する。

## 検証記録

### 2026-09-20 — 初回実装

- sandbox内の`dart format`は4 files中2 filesを整形した後、`~/.dart-tool` telemetry sessionのmtimeを
  更新できず終了コード1になった。source formatting自体は完了している。
- 通常のcache権限で`test/terminal_context_dock_test.dart`を実行し成功した。同一session／PGIDの
  presentation suspend／resume、process contentとpollの破棄、toggle復帰、PGID変更時invalidateを固定した。
- `dart analyze`: `No issues found!`。
- 最初のDeveloper JIT native-content integrationは、新しいECHO-off focus round trip、非active中の
  content-free suspension、復帰後のtoggleを通過した。その後の既存ECHO_ON markerからidle-shellへ戻る
  settleで10秒timeoutになった。修正assertionのfailureではないが、fixture揺らぎか状態回帰かを診断して再実行する。

### 2026-09-20 — 最終検証

- 既存ECHO_ON settleへprocess disposition／session／child／owning PGID／foreground PGID／ECHOを出す
  failure診断と20秒のbounded settleを追加した。単独Developer JIT再実行と最終の両runtime再実行ではtimeoutを
  再現せず、製品状態回帰ではないことを確認した。
- `test/terminal_context_dock_test.dart`: 最終authority条件を含め成功。
- `dart format`: 4 files／変更0、終了コード0。
- `dart analyze`: `No issues found!`。
- `make RUNTIME_ARCH=arm64 runtime-native-content-integration`: Developer JIT／Release AOTとも成功。
  実AppKit active／focus eventを使い、非active中のprocess content 0、process poll 0、Directory operation 0、
  同一PGID復帰後のmenu action enabled、保持treeとの往復、terminal focus、PTY write 0を確認した。
- `make phase7-appkit-acceptance terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory
  release-candidate-daily-use-matrix`: 成功し、最終sourceに対応する証跡を再生成した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。351 filesのformat変更0、静的解析問題0を含む
  repository全体testを通過した。
- `git diff --check`: 成功。

残存するtask固有の阻害要因、未検証事項、追加ROADMAP項目はない。
