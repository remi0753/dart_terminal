# Phase 7 — Context Dock transition and action reliability

## 目的

foreground process実行中にwindow、native tab、split pane、app focus、Dock visibility、Navigator input ownershipを
どの順で遷移しても、同じlive pane／session／foreground jobへ戻った時にProcess InspectorとDirectory Navigatorを
明示的に切り替えられる状態を保つ。また、`view.refresh-directory-navigator`を表示中の対象paneへexactly onceで
dispatchし、同じdirectoryを参照する複数paneと設定keybindを含めて確実に動作させる。

## 背景

app focus、split pane、tab focusの個別回帰は修正済みだが、process controller、Directory controller、Dock state、
native presentation policyが別々にretained stateを管理している。複数の遷移を組み合わせると、片方のcontrollerだけが
保持authorityを失い、Process Inspectorは復帰してもDirectory content toggleまたはmanual refreshが利用不能になる余地がある。
またrefresh actionのavailabilityとdispatch先がwindow snapshot、focused pane、retained paneのどれに依存するかを全経路で
固定できておらず、同じworking directoryを持つ複数paneで誤った対象または無効状態になる可能性がある。

## 分割と実施順

1. foreground Directory保持authorityと画面遷移stateを整理し、全遷移matrixの回帰testを追加する。
   - 依存: 既存app-focus／split／tab retention実装。
   - 完了条件: window／tab／split／app focus／Dock visibility／job identityの組合せを一つのmodel testで網羅し、
     toggle availabilityと古いsnapshotのfail-closedを固定する。
2. `view.refresh-directory-navigator`をpane単位の表示authorityと設定keybindから確実にdispatchできるようにする。
   - 依存: 1で確定するauthority model。
   - 完了条件: idle／foreground Directory表示、同一cwdの複数pane、Navigator／terminal input ownership、menu／palette／
     configured keybindからexactly onceで現在の対象paneだけをrefreshし、Inspector表示中は誤観測しない。
3. native Developer JIT／Release AOTで遷移・refresh・keybindを受け入れ、仕様と検証証跡を更新する。
   - 依存: 1と2。
   - 完了条件: 実AppKit hierarchyとPTYを使う両runtime fixture、全repository gate、README／FEATURE_MATRIX／manual checklist、
     versioned acceptance evidenceが一致する。

各subtaskは個別に実装、検証、記録、ROADMAP更新、コミットを行い、全subtask完了後に親項目を完了する。

## 範囲

- Context DockのProcess Inspector／Directory Navigator content state、retained snapshot、native presentation suspension。
- standard window内外のtab／split pane focus移動、app deactivate／reactivate、Dock hide／show、pane／tab close。
- manual content toggle、Directory navigation focus、manual refresh、stable action registry、設定keybind routing。
- 同じcwdを参照する複数paneでもpane ID／session／PGIDに結びついた独立したrefresh generationを保つ。
- 重複した条件分岐や複数controller間の暗黙契約が原因であれば、責務と命名を整理するリファクタリング。

## 対象外

- SSH先filesystemとremote process introspection。
- filesystem watcherによる常時自動更新。
- foreground processへのpath insertion、自動`cd`、shell plugin依存。
- Context Dock以外のterminal renderer、PTY protocol、window/tab機能の新規仕様。

## 依存関係

- `TerminalContextDockState`のwindow snapshot、target pane、input ownership。
- `TerminalContextDockProcessController`のforeground identity、content override、presentation／pane suspension。
- `TerminalContextDockDirectoryController`のretained snapshot、refresh generation、operation cancellation。
- `TerminalApplication`のnative hierarchy reconcile、action registry、keybind engine、menu／palette dispatch。

## リスク

- path文字列をidentityとして扱うと、同一cwdの別paneへrefreshやsnapshotを誤配送する。
- transient native focus lossとapp非activeを同じ条件で扱うと、必要な保持を破棄するかprivacy境界を越える。
- foreground Inspector表示中のrefreshを許すと、利用者が明示していないfilesystem観測が再開する。
- action availabilityだけを直してhandlerの対象解決が異なると、menu／paletteとkeybindの挙動が分岐する。
- controller間の更新順へ依存した修正は、複合遷移で再び片側だけを失効させる。

## 完了条件

- 全ての許可された同一job round tripでcontent toggleが利用でき、Directory表示・tree操作・manual refreshができる。
- window／pane／tab／session／PGID authorityが変わる全失効経路では古いDirectory snapshotを表示しない。
- refreshは現在表示中のDirectory paneへ一回だけ届き、同じcwdの他paneのgeneration／selection／treeを変更しない。
- `keybind = <chord>=view.refresh-directory-navigator`が設定parser、conflict判定、native key routing、action dispatchを通る。
- menu、Command Palette、設定keybindが同じstable actionとavailabilityを共有し、terminalへのwriteは0。
- controllerの責務、state transition、cleanup条件をtestと文書から追跡でき、不要な重複分岐が残らない。

## 検証方針

- model/unitでtransition tableを生成し、各遷移後のprocess mode、toggle／refresh availability、retention、operation countを検証する。
- 同一cwdの2 paneを独立filesystem probe／generationで検証し、refresh対象がpane IDに束縛されることを確認する。
- keybind設定をparseし、physical chordからshared actionへexactly once dispatchしてPTY write 0を確認する。
- native-content fixtureへ複合pane／tab round trip、Directory切替、refresh、設定keybindを追加する。
- formatter、analyzer、生成証跡、全repository test、Developer JIT／Release AOTを実行する。

## 調査記録

### 2026-09-20 — 着手時

- 直前の個別修正はapp focus、split pane、tab focusをそれぞれ独立fixtureで扱っている。今回の報告は、それらを連続して
  組み合わせた時のcontroller間authority不一致が残っていることを示す。
- refreshのidentityはworking directory pathではなくpane ID、session、表示中のDirectory snapshot generationでなければならない。
- まず既存stateとaction routingを一覧化し、失敗を再現するmatrix testを作ってからproduction codeを変更する。

### 2026-09-20 — 複合遷移の原因

- process controllerは投影中stateをwindow ID、pane／tab移動後のstateをpane ID、native tab focus gapをwindow単位の
  pending markerで別々に管理していた。app focusだけの非投影、同一windowのretarget、通常のfocused pane変更はそれぞれ
  異なるpolicyとcleanup分岐を通り、個別fixtureは通っても組合せの順序で結果が変わっていた。
- 再現した失敗は、foreground pane AとBを同じwindowで保持した後、native presentationがない期間にwindow activation、
  tab selection、split focusを複数回変更する経路である。app非active用policyとtab retarget用policyの選択がtarget変更の
  タイミングに依存し、ある分岐はwindow内の全pane cacheを破棄した。
- Dock非表示もwindow closeと同じdestructive cleanupを使っていた。pane／session／jobはliveのままなのにcommand開始前の
  Directory snapshotを失うため、Dock再表示後にProcess Inspectorは再構築できてもcontent toggleを復元できなかった。
- `TerminalContextDockProcessController`と`TerminalContextDockDirectoryController`はprocess同期を先に行う契約を持つ。
  path文字列ではなくpane IDに結びついたprocess retentionとDirectory snapshotの両方が残って初めてtoggle可能になる。

### 2026-09-20 — foreground authorityのリファクタリング

- native presentationの理由別policyとpending markerを削除し、pane、tab、logical window、app focus、native visibility、
  Dock visibilityの全てを一つの`_suspendWindowProjection`経路へ統合した。投影stateからrich process content、request、poll、
  content overrideを除去し、live pane ID、session ID、foreground PGID、Directory retention eligibilityだけをpane単位で
  operation-freeに退避する。
- foreground activationの75 ms debounce中でもcandidate PGIDが確定していれば同じ退避経路を使う。これにより、command開始直後に
  pane／tabを移動した場合もcommand開始前snapshotを保持し、復帰時にPGIDを再検証できる。
- logical windowやDockが非投影でもlive pane cacheは保持する。pane close、window close、session変更、PGID変更、controller
  disposalだけがdestructive cleanupを行う。復帰時は必ず現在のprocess snapshotとsession／PGIDを照合し、不一致なら
  Directory controllerへ明示invalidateを送って古いpathを表示しない。
- Directory controllerはDock hide時にroot／expanded snapshotをcancelせず、全operationを止めたimmutable stateとして凍結する。
  同一cwdの別paneもpathではなくpane ID別のsnapshotとして保持する。
- production codeでは理由別retention callback、2個のpolicy typedef／field、native retarget markerと分岐を削除した。
  application側のnative hierarchy policyも不要になり、画面遷移順に依存するコードを減らした。

### 2026-09-20 — 画面遷移matrix検証

- process controllerとDirectory controllerを実際のproduction順序で同期する結合model fixtureを追加した。二つのsplit paneが
  同じ`/root`を参照し、それぞれ独立したforeground PGIDとDirectory snapshotを持つ状態を作る。
- fixtureはsplit A→B、別tab、別logical window、app/native presentation消失中のtab／pane再選択、元pane復帰、Dock hide／show、
  logical window focus往復を連続して実行する。各復帰でProcess Inspector、content toggle、`/root` Directory projection、
  Navigator input ownershipを確認する。
- 非投影期間はprocess snapshotがnull、rich request 0、Directory operation 0で、A／B両方のpane-bound authorityだけが残る。
  これによりbackground process詳細やfilesystem走査を再開せずに複合遷移を許可する。

### 2026-09-20 — 第一subtask検証

- `dart format lib/src/terminal_context_dock_process.dart lib/src/terminal_context_dock_directory.dart
  lib/src/terminal_application.dart test/terminal_context_dock_test.dart`: 成功。最終実行は1 test fileを整形した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
  既存app focus／split／tab fixtureと新しい複合matrixを全て通過した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `git diff --check`: 成功。
- 最初のリファクタリング後は、非投影中にidle pane stateをcancelする際にもDirectory invalidation callbackを送ったため、
  tab fixtureの診断countが1増えた。idle stateにはforeground retention authorityがなく、Directory controller自身が現在projectionを
  安全にcancelするため、destructive callbackはsession／PGID不一致とwindow teardownだけへ戻した。

### 2026-09-20 — refreshと設定keybindの原因

- `TerminalContextDockKeyController`はNavigatorがfirst responderの時、設定engineを解決していたが、application actionを
  dispatchするのはContext Dock境界移動の2 actionだけだった。それ以外の明示設定actionは最後の`consumed`へ落ちるため、
  `view.refresh-directory-navigator` keybindはterminal入力中だけ動き、Navigator入力中は無反応になっていた。
- 全application actionを無条件にdispatchすると、built-inのCommand+矢印がpane focusへ変わり、Navigatorのtree開閉を壊す。
  resolver結果へ`defaults`／`overrides`のoriginを追加し、Navigatorでは明示overrideを全てshared dispatcherへ渡しつつ、
  Context Dock専用の既定境界移動だけを従来どおり許可する。built-in Command+Left／Rightはtree intentを維持する。
- terminal pane側の`TerminalKeyEventRouter`はapplication actionのkey-downで一度dispatchする一方、key-upを消費するのが
  Context Dock境界移動だけだった。Kitty release reportingが有効なら、refreshを含む別application actionのrelease byteが
  foreground PTYへ流れる可能性があった。application action bindingは種類にかかわらずreleaseを消費するよう統一した。
- manual refreshのcontroller自体はwindow／pane IDを受け取り、Directory projectionと同一paneであることを検証していた。
  不安定さの主因はpath identityではなく、上記key routingと複合遷移後のretention喪失だった。

### 2026-09-20 — pane-bound refresh検証

- 複合matrixを、同じ`/root`を持つforeground pane A／Bのmanual refreshまで拡張した。filesystemへ新しいfileを追加し、
  Aをshared actionからrefreshするとAだけが新fileを表示し、非投影のBは古い独立snapshotを保つ。
- Bへ戻してDirectory Navigatorを明示表示した時点では新fileがないことを確認し、設定相当のControl+R →
  `view.refresh-directory-navigator`をNavigator first responderからdispatchする。root listは一回だけ増え、Bだけが新fileを
  表示し、Navigator ownershipは変化しない。
- Process Inspectorへ戻るとrefresh actionは即時disabledになり、明示Directory overrideがないbackground filesystem観測を
  開始しない。unavailableなconfigured keybindもNavigatorで消費され、PTY writeへfall throughしない。
- keybinding engineのoriginは、通常のterminal router動作を変更しないread-only metadataである。ordered config override、
  unbind、passthrough、native shortcut優先の既存contractは維持する。

### 2026-09-20 — 第二subtask検証

- `dart format`（変更した6 Dart source／test）: 成功。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_key_binding_test.dart`: 成功。
  default／override originとapplication action identityを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_context_dock_test.dart`: 成功。
  Navigator-owned configured refresh、unavailable消費、同一cwd A／Bの独立snapshotとexactly-once refreshを確認した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_config_test.dart`: 成功。全stable application action IDを含む
  keybind parser target matrixで`view.refresh-directory-navigator`を受理した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/terminal_product_configuration_test.dart`: 成功。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart run test/run_tests.dart`: 最終再実行は成功し、`dart_terminal tests passed`。
  Kitty event-type modeでapplication actionのdownを一回dispatchし、releaseをignored、PTY write 0とする回帰を含む。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、`No issues found!`。
- `make phase7-appkit-acceptance terminal-compatibility-regression-coverage ghostty-p0-p1-gap-inventory
  release-candidate-daily-use-matrix`: 成功し、第一・第二subtaskのsource hashへ生成証跡を更新した。
- 初回`test/run_tests.dart`はsource変更後のgap inventory staleを意図どおり検出した。正規generatorで全関連証跡を更新後、
  同じsuiteを再実行して成功した。
- `git diff --check`: 成功。

### 2026-09-20 — 実AppKit複合遷移と設定keybind

- native-content fixtureの従来split round tripとtab round tripは、別々のforeground `/bin/cat` jobを開始して各々を
  cleanupしていた。この構造では報告された遷移の組合せを検出できないため、同じforeground jobを維持したまま
  split A→B→A、new native tab→元tab、B→Aを連続する一つのfixtureへ統合した。各復帰でProcess Inspectorと
  Directory toggleを確認し、最後に同じjobを終了してsplit／tabを個別cleanupする。
- second splitは通常のcwd継承metadataだけに依存せず、fixture内で同じlocal directoryへ明示`cd`し、独立したpane／sessionの
  Directory authorityを確立する。これにより同一cwdの複数paneという報告条件を実PTY上で固定した。
- native-content起動設定へ`control+r=view.refresh-directory-navigator`を追加した。tab round trip後にforeground pane Aで
  Directory Navigatorを表示し、外部作成fileをControl+Rのnative key eventで一回だけ取得する。refresh commit countは
  exactly one、Navigator ownership維持、foreground PTY write count不変を検証する。その後pane Bへ移り、同じcwdでも
  pane B自身のDirectory projectionと、Aのcontent-free retention authorityが同時に成立することを確認する。
- model fixtureでは非投影pane Bのimmutable snapshotがAのrefreshでは変わらないことを直接確認できる。実AppKit fixtureで
  pane Bへfocusすると、idle paneの通常同期が現時点のfilesystemを再取得し得るため、focus後のfile一覧を古いままとする
  assertionは仕様より強すぎる。native側はtarget pane identityとexactly-once dispatch、model側は非投影snapshot分離を担当する。
- app非active時は投影window state自体を除去するリファクタリング後のcontractに合わせ、native fixtureも
  `unavailable` documentではなくprocess snapshot nullを期待する。Directoryはimmutable frozen snapshot、process側は
  pane／session／PGIDだけを保持し、rich process contentとtimerは0である。

### 2026-09-20 — native fixtureの失敗と修正

- sandbox内の最初のDeveloper JIT buildはMetal compilerが`~/.cache/clang/ModuleCache`へ書けず失敗した。実AppKit起動を含むため、
  sandbox外で同じ正式make targetを再実行した。sourceやfixtureの問題ではない。
- 最初のnative runは旧fixtureがapp非active中に`unavailable` content documentを期待し、新しい非投影contractのnull snapshotと
  不一致だった。非投影中のprocess detailを残さない期待へ更新した。
- 次のrunでは新規splitがmetadata上の元cwdで起動し、初期paneのplain sh内`cd`を暗黙継承しなかった。split自身でfixture cwdへ
  移動してからsnapshotを確立するよう修正した。
- 3 pane（元split tree 2 pane + temporary tab 1 pane）へ変わったため、旧tab fixtureの2 pane countを3へ修正した。
- pane Aのrefresh後にpane Bへfocusして古いfile一覧を要求するassertionは、idle paneの正規再同期まで禁止してしまった。
  非投影中のsnapshot分離はmodel testに残し、native testはpane Bの独立target、同一cwd、Aのretention継続を検証するよう整理した。

### 2026-09-20 — 第三subtask実機検証

- `make RUNTIME_ARCH=arm64 developer-jit-native-content`: 最終再実行は成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS mode=developer-jit`を確認した。
- `make RUNTIME_ARCH=arm64 release-aot-native-content`: 成功。
  `RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS mode=release-aot`を確認した。
- 両runtimeとも`transition_matrix=true configured_refresh=true same_directory_targeted=true`を含むexact markerを要求し、
  実AppKit hierarchy、native key routing、実PTY write count、5 session最終cleanupを既存native-content gate内で検証した。
- `make keybind-action-reference phase7-appkit-acceptance terminal-compatibility-regression-coverage
  ghostty-p0-p1-gap-inventory release-candidate-daily-use-matrix`: 成功。設定keybindのNavigator routing仕様と変更後source hashを
  versioned evidenceへ反映した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。351 Dart fileのformat差分0、`dart analyze`の`No issues found!`、
  Context Dock unit／configuration／key routing、全native capability、security stress、reference freshness、release-candidate gateを含み、
  最終行`dart_terminal tests passed`を確認した。
- `git diff --check`: 成功。

## 完了時の設計状態

- process controllerはrichなwindow projectionと、pane ID別のcontent-free retention authorityを分離した。presentationの
  理由や順序に依存するcallback／pending markerはなく、全非投影遷移が同じsuspend pathを通る。
- Directory controllerはpane IDをidentityとし、同じpathの複数paneでもsnapshot、selection、expanded state、refresh generationを
  共有しない。非投影中とProcess Inspector表示中はoperation 0を保ち、明示Directory表示中の対象paneだけ再開する。
- keybinding engineはbinding originを保持し、Navigator固有の既定Command-arrow操作と、利用者が明示したapplication action overrideを
  両立する。terminal／Navigatorの両入力経路でapplication actionのdownはexactly once、releaseとunavailable actionはPTYへ流れない。
- model transition matrix、実AppKitのapp focus、Dock hide、同一jobのsplit＋tab複合往復、同一cwd pane、Developer JIT／Release AOTが
  同じcontractを検証する。今後presentation経路を追加する場合も、理由別cacheを増やさず共通suspend／revalidateへ接続する。
