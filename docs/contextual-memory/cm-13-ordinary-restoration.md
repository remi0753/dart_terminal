# CM-13 通常GUIのexact restorationとrollback安全境界

日付: 2026-09-22
状態: 通常GUI復元の機能検証は完了。AOT idle CPU hard gateの未達を明示して後続作業へ進む（2026-09-22利用者指示）。R1 stageは未判定。

## 目的と背景

通常GUIのDeveloper JIT／Release AOTで、terminal restoration v1のexact bytesとpane traversalをNotesへ渡し、正常終了時にrestoration-first／Note-secondの順でcommitする。現在の通常GUIは毎回fresh windowを作り、Notesへ`restoration: null`を渡し、終了時は`notes.shutdown()`だけを行うため、実GUIで保存済みNoteが常にDetachedとなる。別のacceptance経路のexact復元だけではR1の通常利用を証明できない。

## 範囲

- `dart_terminal`の通常interactive起動・終了経路に、既存のv1 codec／restorer／capture／ordered Note shutdownを接続する。
- multi-window／tab／splitのtraversal、launch cwd、placement、fresh PTY、Note pane bindingを同一snapshotから再構築する。
- Notes offでもterminal restorationを維持し、Note storeには触れない。Capture／I/O失敗はwrong-contextを避け、terminal自体の起動を妨げない。
- 旧`0.1.0`の通常GUIがrestoration v1を読み書きしない事実を踏まえ、既知のpre-Notes binary rollbackではNote storeを保持しつつ旧snapshotを信頼しない運用手順と機械的確認を追加する。
- 前回の手動検証で見つかったshutdown中のlate Note event/menu action競合を同じ通常GUI lifecycleとして検証する。

## 対象外

- `dart_appkit`へのDart Terminal固有code、Native Notes ABIやstore formatの変更。
- R2公開設定、S3、default-on、Note本文を含む証跡。
- 旧binaryそのものへの変更、旧binaryを手順外で実行した事実の検出。旧binaryは現行codeで制御できない。
- GUIのIME／VoiceOver／appearance等のmanual stage判定。次のROADMAP項目で行う。

## 依存と完了条件

- 依存: CM-04のexact binding、CM-10/11のproduct integration、CM-13のinternal profile／runbook／automated aggregate、既存`TerminalApplicationRestorer`と`TerminalNoteApplicationCoordinator.shutdownApplication`。
- 通常GUIの正常終了→再起動でexact restored paneにのみNoteが再接続する。Hash mismatch、restore failure、旧binary rollbackでは推測せずDetachedとなり、store payloadを消さない。
- Restoration v1をNote commitより先に保存し、partial failureは次回wrong attachにならない。Normal quitのnative／worker／lock ownerを回収する。
- Focused test、format/analyze、JIT/AOT実GUIまたは相当するend-to-end、必要なfull gate、content-free記録、差分reviewを完了して独立commitする。Stage判定はまだしない。

## 検証方針

1. v1 load／restore／capture／commitとrollback invalidationを一時的なcanonical state rootでfocused testする。Failure時のfallbackとNotes offによるNote store非接触を確認する。
2. 通常GUIを隔離storeでJIT→AOT→JITと起動し、exact attach、layout mismatch時Detached、clean quit、lock解放を確認する。
3. 正規R1 aggregate、format/analyze、生成物freshnessを再実行する。性能の数msの差は実装の進行を止める理由にしない。

## 調査と選択肢

- `TerminalRestorationLifecycle`はstandalone acceptanceのlogical/native generation ownerであり、通常GUIの既存state／hierarchy／window event ownerと二重所有になる。通常GUIでは既存の`TerminalApplicationRestorer`と`TerminalApplicationRestorationCapture`を使い、native adapterの既存`windowPlacements`注入口へ渡す案を採用する。
- cwdやwindow indexからNote contextを推測する案は、別paneへの誤接続を許すため不採用。GUIで常にDetachedとする案は安全だが、現行R1のexact復元条件を満たさないため不採用。
- Release tag `0.1.0`の通常interactive経路はrestoration v1を使わず、acceptance経路だけが使う。したがって現行版が保存したsnapshotは、その旧binaryがrollback中にlayoutを変えても更新されない。単純なhash一致は旧binary経由を検出できず、Gate 7の「旧binaryがrestoration v1を通常どおり読む」という記述はこのrelease tagに適用できない。旧binaryを変更することも実行履歴の自動検出もできない。既知のrollbackは開始前にsnapshotを退避・無効化し、再upgradeを必ずDetachedにする保守的な手順を採る。旧binaryが実際にv1を維持する場合だけ、既存Gate 7のexact-match経路を利用できる。この差分をrunbook／受け入れ記録へ明記し、無条件の旧binary B-04達成を主張しない。
- この変更は通常GUIの起動・終了と旧版互換という独立した成果物で、manual checklist／stage判定より先に検証とcommitが必要なため、ROADMAPのCM-13内にひとつのsubtaskとして追加した。個別bugごとの項目は作らない。

## 2026-09-22 実装・実GUI観測

- 通常interactive pathだけにv1 file location、exact-byte load、`TerminalApplicationRestorer`、全pane traversal、native placement、fresh PTY start、`TerminalNoteApplicationCoordinator.shutdownApplication`のrestoration-first callbackを接続した。Acceptance専用pathと`dart_appkit`は変更しない。
- 初回JITでsynthetic Noteを作成して通常Quitすると`shutdown=ordered`、exit 0、worker／PTY clean。AOTの同一隔離state rootでは`load=restored`、Currentに1件だけ自動attachした。AOTで編集して2 paneへ分割し通常Quitすると、次のJITは2 pane／2 fresh PTYを復元し、元paneにNote badgeが1件現れた。本文／ID／pathは証跡へ書かない。
- そのJITで他paneをfocusしたまま元paneのbadgeを押すと、native eventのfocus requestがauthorityのfocused-pane条件に拒否され、`_handleSurfaceEvent`が同期失敗をfatal exceptionにした。事後のordered shutdownとowner回収は成立したが、process exit 70だった。Native focus拒否は正当なbusy境界であり、初期実装のようにfatalへ昇格してはならない。明示的なNote操作時だけ対象paneをactivateし、失敗してもpending transferをcancelしてterminal ownershipを維持する方針にした。Coordinatorの2-pane回帰testを追加し、再GUIでは非active側badgeからCurrentの更新済みNoteを開け、JITは通常Quit exit 0／2 pane cleanだった。
- Internal guardで旧版へ戻す前のtrust markerを無効化した隔離fixtureでは、Note store payloadのSHA-256が前後同一。次のJITは`load=missing`、Current空、Detached 1件で、本文と編集が保持された。ここでは旧binaryそのものは実行せず、通常GUIがv1を更新しないtag `0.1.0`に必要なguard／re-upgrade境界を確認した。Fixtureはsyntheticであり、guard操作前のraw backupを取得していなかったため、runbook全工程の本番rehearsal passとは扱わない。
- Focused restoration test、coordinator test、対象analyzerはpass。GUI起動はsandboxの直接`make ...-run`ではexit 250でアプリ表示前に停止したが、通常GUI環境で同一candidateは起動し上記の実操作を完走した。Source hashを参照するfull aggregateは本実装確定後に再生成して実行する。

## 2026-09-22 信頼印の再活性化リスク

- 初版のguardはmarkerだけを削除した。`notes=false`またはNote unavailableのcurrent binaryが同じtopology bytesを再保存すると、markerが再作成され、古いNote storeのhashと偶然一致して自動reattachする余地がある。これは既知rollbackやcrash後のwrong-context禁止と両立しない。
- 信頼印を無条件に再作成する案は不採用。起動時のtrusted markerを原子的にuntrusted sentinelへ移し、Notesのordered restoration＋Note両commitが成功した後だけsentinelを消す。Off／unavailable／crashではsentinelが残り、後のsnapshotのbyteが一致してもNoteへartifactを渡さない。Guardも同じsentinelを作る。これならold binary自体を検出せずに、runbookで始めたrollbackの安全状態を持続できる。Guard直後はmarkerがないためterminal topologyもfresh fallbackだが、その後のoff launchがv1を保存すれば次回はterminalだけを復元できる。Note store payloadは変更しない。
- さらに初回／marker欠損／不正marker／hash mismatchでもsentinelを作る。そうしなければoff launchが同じv1 bytesを再保存するだけで、古いNote bindingを偶然再信頼し得る。Sentinelを永続化できない場合はrestorationをunavailableとし、そのlaunchでは保存も試みない。初回の正常なNote ordered commitだけがsentinelを消して新しいexact bindingを成立させる。
- 正規R1 aggregate再実行はR0 8-gateの途中、Developer JIT S1のGUI processがOS由来の`IMKCFRunLoopWakeUpReliable` stderrを一行出したためexit 2。S1のstatus／summary以前にstderr空条件で止まった。性能閾値やNote仕様には触れず、focused testと実GUIを先に完了してから同一gateを再試行する。Sandbox内のfocused Dart testはMetal module cacheへの書き込み権限で失敗したが、通常ビルド環境では復元testがpassした。

## 2026-09-22 最終candidateの隔離GUI検証

- 最終sourceをJIT／AOTへ再buildした。隔離synthetic storeでJIT起動時の`load=restored`、Detachedの既存Noteを明示ReattachしてCurrent 1件、通常Quitの`shutdown=ordered`、exit 0、worker／PTY cleanを確認。終了後はv1とtrusted markerがありuntrusted sentinelはない。同じrootのAOTは`load=restored`で、同じNoteをCurrentへ一度だけ自動attachし、badgeから本文を表示できた。AOTも通常Quit／ordered commit／owner cleanupが成功した。
- AOT終了後に隔離Note storeのraw backupを取り、rollback guardを実行した。`trust_invalidated=true`、guard前後のstore payload SHA-256一致、v1本体維持、trusted markerからuntrusted sentinelへの変化を確認した。続くJIT `--notes=false`は`load=untrusted`、Note UIなし、通常Quit exit 0で、store payloadはbackupと同一hash。Off終了後はterminal v1とtrusted markerに加えてuntrusted sentinelが残った。
- 同rootのexact on profileで再起動すると`load=untrusted`でterminalは起動する一方、Current空／Detached 1件となり、本文維持とwrong-context自動attach 0を実GUIで確認。通常Quit exit 0／owner cleanup。旧tag `0.1.0` binaryそのものはこの再検証では起動していない。Tagがv1を通常GUIで更新しないというcode調査とguardを組み合わせた境界の検証であり、旧binaryの無制御起動検出は対象外のまま。
- Focused `terminal_restoration_test.dart`と`terminal_note_application_coordinator_test.dart`、対象`dart analyze`、対象`dart format --set-exit-if-changed`、`git diff --check`はpass。実GUI JIT/AOT buildもpass。通常起動の2-paneで非active Note badgeを押した時のfocus拒否は回帰testと先の実GUI再操作の両方で解消済み。
- 2度目の正規aggregateでは先のJIT S1がpassした後、Release AOT reliabilityのresource／idle-power proxy compound gateで一度exit 2。条件にはresource count・resume invariantも含まれるため、数値不明のまま閾値を変えず同じ`release-aot-reliability`を単独再実行したところexit 0でpass。測定閾値の変更は行っていない。正規aggregate全体の再実行はまだ必要。
- 3度目の正規aggregateはRelease AOT window-interaction acceptanceで`Context Dock ownership leaked raw or IME input into the terminal`としてexit 2。同経路は通常GUI restorationを使わない専用acceptance pathであり、同じ`release-aot-window-interaction`を単独再実行するとexit 0／入力隔離pass。OS／スケジューリング由来の一過性と推測するが、原因は確定していない。Gateの入力隔離条件は弱めず、全体完走を再試行する。
- 4度目はR0の8-gateを完走した後、R1 Developer JIT S2で、初回と同一種の`IMKCFRunLoopWakeUpReliable` stderr一行により停止。異なるNotes suiteで2度発生したため、単なる再試行だけに依存しない。AppKit起動processが出すmacOS Input Method Kit形式の単一行だけを`tool/runtime_stderr_filter.dart`で識別し、その他のstderr byte、同じ行の繰り返し、異なるprocess名／suffixは従来どおりfailに残す。`test/runtime_stderr_filter_test.dart`で境界を固定しroot testにも追加。これはproductのIME routingや入力隔離条件を変えず、OS診断1行をapp failureとして誤分類しないためのharness変更。実system IMEのmanual確認はなお未実施であり、このfilterで代用しない。

## 2026-09-22 検証阻害: 別の実行中appによるSecure Input所有

- 最終sourceの5度目の正規aggregateでは、root 404-file format／analyzer／root testsと両runtime S1/S2、fault/sanitizer、AOT reliability等を通過した後、Developer JIT native-contentでexit 2。単独targetの再実行でも`Process Inspector disabled manual Secure Keyboard Entry protection`が再現した。
- Content-free診断は、test app起動前から`system_enabled=true`、manual request後もtest appの`owned=false`だった。読取専用のmacOS console registryとprocess一覧を照合し、OS Secure Inputの現所有者が別途実行中のインストール済みDartTerminal appであることを確認した。Productのmanual ownership条件を弱めたり、他appのSecure Inputを無断で解除したりしない。
- この失敗は数msの性能差ではなく、実OS所有権の競合。現サブタスクは未完了のままとし、ROADMAPを進めず、commitもしない。インストール版がテスト操作で起動・前面化された可能性を調べ、所有者がいない状態で同じ正規aggregateを再実行する。

## 2026-09-22 テスト対象の前面化経路を再調査

- `tool/runtime_integration_smoke.dart`のLaunch Services起動はbuild candidateの`.app`パスを渡すが、window-interaction acceptanceの追加前面化は`open -b dev.dart-terminal`であり、同一bundle IDのインストール版を選び得る。候補とインストール版の`Info.plist`に同一IDがあること、macOSの`open`説明で`-b`がbundle ID選択であることを読取専用で確認した。先のインストール版がこの呼び出しで起動したかどうかは未確定。
- `open -a <candidate path>`はID検索を避けられるが、直接起動した候補が既存instanceとして選ばれる保証とPID再利用時の誤前面化境界が弱い。インストール版を終了・無効化する案はユーザー状態への不要な介入であり不採用。macOS `NSRunningApplication`を既に記録済みのtest PIDで取得し、実行ファイルの絶対パスを検証してから前面化するtest harness専用方式を採用する。候補が終了済み／別実行ファイルならfail closedとし、bundle IDによるfallbackを置かない。
- JXAのAppKit bridgeを読取専用で確認し、`NSRunningApplication`をPIDで取得できた。既に前面にあるChatGPTへの同一activation API呼び出しは成功した。次にtest harnessへ組み込み、build candidateのwindow-interaction acceptanceと回帰testで確認する。既に起動しているインストール版や外部からの新規起動そのものはtest harnessから禁止できず、そのSecure Input所有が残る場合は受け入れを偽装しない。
- `tool/runtime_app_activation.dart`にPIDと絶対実行ファイルパスだけを受けるJXA引数を作り、`runtime_integration_smoke.dart`の`open -b`を除去した。PIDが存在しない／別binaryを指す場合は前面化せず失敗する。`test/runtime_app_activation_test.dart`はbundle ID検索を用いない条件と不正入力を検証し、root testにも接続した。Focused test exit 0、対象`dart analyze`は問題なし、formatは変更0件。最初のformat試行はDart analyticsがsandbox外のsession fileへtouchしようとして終了コード1になり、`CI=true`で解消。最初のfocused test試行はMetal build hookの既存module cache書込がsandboxに拒否され、許可された通常実行環境で再実行してpassした。
- 実GUIの`make RUNTIME_ARCH=arm64 developer-jit-window-interaction`は`RUNTIME_WINDOW_INTERACTION_INTEGRATION_PASS`でexit 0。実行前後のprocess一覧にインストール版`/Users/remi/Applications/DartTerminal.app/Contents/MacOS/dart_terminal`は存在しなかった。これはtest harness自身がインストール版を前面化・起動しないことの実機確認であり、他のprocessによる将来の起動をOS全体で禁止するものではない。
- 以前止まった`make RUNTIME_ARCH=arm64 developer-jit-native-content`を同じcandidateで再実行し、Secure Input ownership条件を弱めず`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`／exit 0。次にR1正規aggregateを再実行する。
- R1正規aggregate再実行はinternal profile／rehearsal、R0 architecture／sanitizer、JIT window-interactionまで通った後、Release AOT window-interactionで停止。`DEC 1004 focus reporting was not enabled by the real PTY fixture`がproduct内で発生し、processが終了したためexact-PID activationも失敗扱いになった。前面化が先に失敗したのか、fixture focus条件が独立に失敗したのかは現時点では未確定。同じtargetを単独実行して切り分ける。入力／focus条件を弱めない。
- 同じ`release-aot-window-interaction`の単独再実行はexit 0／`RUNTIME_WINDOW_INTERACTION_INTEGRATION_PASS`。PID指定前面化自体はAOTでも成功した。失敗箇所のcodeでは、real PTYから`focusReady`とpromptのraw markerを読んだ直後、screen parserに非同期で反映される`focusReportingMode`を即時assertしていた。他の受け入れ条件には既存の最大10秒のbounded `waitFor`が使われる。parser反映待ちの競合と判断し、同じ条件を維持したままこのassertだけ既存`waitFor`へ変更する。性能閾値の緩和ではない。
- その修正後の正規aggregateはAOT window-interaction product自身が`TERMINAL_WINDOW_INTERACTION_TEST ...`を出力して正常終了したにもかかわらず、追加のJXA前面化が既に終了したPIDに失敗し、harnessがexit 2とした。これはAOTの速い完走と前面化タスクとのrace。Product acceptanceは`application.isActive`がfalseのとき内部でbounded AppKit focus eventを注入・検証するため、このsuiteに外部前面化は必須ではない。JXA PID方式を残して失敗を無視する案は不要なOS side effectが残る。追加前面化を全廃し、候補の直接実行／Launch Servicesの絶対候補パス指定だけを残す案へ変更する。先のJXA helper／単体testは使用せず削除し、候補起動を実GUIとprocess一覧で再検証する。
- 追加前面化を削除し、Launch Services起動時の対象も`_loadInvocation`で存在／manifest／実行ファイルを検証したbundleの絶対パスへ固定した。対象Dart formatは変更0件、Dart analyzeは問題なし。`release-aot-window-interaction`と`developer-jit-window-interaction`は両方exit 0／PASS。AOT実行前後のprocess一覧にインストール版はない。全体gateはこの最終harnessで再実行が必要。
- 最終harnessでのR1正規aggregateは、JIT/AOT window-interaction、S1/S2両runtime、native sanitizer、互換性とdifferential acceptanceまで通った後、`GHOSTTY_P0_P1_GAP_INVENTORY_FAIL ... inventory is stale`で停止した。Product sourceを更新した後に一度生成したが、その後さらにharness sourceを変更したためsource fingerprintが旧版だった。機能失敗ではなく生成順の誤り。最終sourceで3つのgenerated acceptance／inventory／daily-use matrixを再生成し、同じgateをやり直す。
- 最終sourceで3生成物を更新し、個別freshness checkは全pass。次のaggregateは早期のR0 native budgetで`main_thread_stall`、apply p95 5,136 us／first-visible p95 14,247 us／21 sample中stall 1で停止。p95は8,000／100,000 usの予算内で、単発16,670 us閾値だけが超過した。既にユーザーが性能を低優先度とし「現設定値の2倍まで許容」を明示しているため、stall閾値のみ33,340 usへ変更する。測定サンプル数、stall count=0、p95予算、owner=0は維持する。これは従来の1 frame基準を2 frame基準へ変える契約変更であり、提案書の現行基準も更新する。CM-12文書の過去の測定・判断は履歴として変更しない。
- `terminal-note-r0-evidence`を新しい33,340 us閾値で再実行し、`TERMINAL_NOTE_R0_EVIDENCE_PASS`、owner／timer等の元の条件もpass。Evidence JSONも現ソースから再生成した。変更済みsource hashを含む残りのgenerated fileは再生成・freshness確認してからaggregateへ戻る。
- 3生成物のfreshnessとR0 evidence testはpass。再実行した正規aggregateはroot 404-file format／analyze／Dart tests、JIT/AOT hierarchy、reliability、S1/S2、JIT native-contentまで通過。Release AOT native-contentで`Context Dock toggle did not project the real plain-sh cwd tree`が既存10秒waitを超えてexit 70。Secure Inputは候補processが`owned=true`であり、前の外部所有問題ではない。`_exerciseNativeContentProduct`ではreal PTYのplain sh cwdを先に確認してからdockをhide/showし、directory snapshotにcwd／3 fixture entryが揃うのを待つ。どの条件が残ったか現failureには含まれない。単独targetで再現性を確認し、必要ならcontent-free failure detailsを追加する。
- 同じAOT native-content単独再実行では前のDirectory条件を越え、後段の`Process Inspector disabled manual Secure Keyboard Entry protection`でexit 70。テスト終了後の読取専用調査ではインストール版processなし、OS Secure Input所有PIDなし。先の`open -b`経路は除去済みで、今回の失敗をインストール版の誤起動とは扱わない。Secure Input所有の失敗は候補実行中の一過性状態か外部干渉か未特定であり、manual ownership条件は維持する。
- 追加の単独再実行でもSecure Input manual ownershipが再現して失敗。content-free statusは`manual_requested=true application_active=true desired=true owned=false system_enabled=false os_status=0`。Dartのsynthetic focusはactiveをtrueにできるが、native `SecureEventInput`はOS実前面でないと所有しない。外部前面化を全廃する案は短いwindow-interactionには成立する一方、実OS Secure Inputを測るnative-contentには不足する。`open -b`へ戻す案はインストール版誤選択の危険があるため不採用。長時間実行するnative-contentだけ、診断に記録した候補PIDと候補実行ファイル絶対パスを照合した`NSRunningApplication`前面化を使い、短いwindow-interactionは外部前面化なしのままとする。候補が先に異常終了した場合はactivation失敗でproduct errorを覆わない。
- ただしその候補PID前面化を追加したAOT native-content単独実行でも、同じ`manual_requested=true ... owned=false system_enabled=false os_status=0`で失敗した。前面化の成功自体はproduct error優先のためその結果に記録されなかったが、少なくともmanual ownershipは回復しない。追加のOS前面化はユーザーが求めた誤起動防止には必須でなく、focusへの副作用だけが増えるため採用を取り消す。`open -b`をなくし、検証済み候補bundle絶対パスだけで起動する最小修正を残す。Secure InputのAOT所有失敗は残存し、全体gateを完了扱いにはしない。
- 最終的な`tool/runtime_candidate_launch.dart`は`/usr/bin/open`へ絶対`.app`パスを位置引数で渡し、相対名／bundle IDを拒否する。`_loadInvocation`で存在とmanifest／実行ファイルを検証した`bundle.path`だけを使用する。`test/runtime_candidate_launch_test.dart`をroot testに接続し、`-a`／`-b`不在、候補パス、引数／環境維持を検証。対象format／analyze／focused testはpass。
- この最終harnessの実GUIでは`developer-jit-note-s1`がPASS。実行前後のprocess一覧にインストール版なし。同じharnessの`developer-jit-native-content`はmanual Secure Input ownershipでexit 70だったが、終了後にインストール版は存在しない。よって「ハーネスがインストール版を起動しない」境界は確認できたが、OS Secure Input所有を含む正規R1 gateは未完了であり、ROADMAPを進めずcommitもしない。外部のユーザー操作でインストール版が起動することまでOS全体で禁止する機能ではない。
- 最終harness sourceに合わせてPhase 7 acceptance、Ghostty gap inventory、release daily-use matrixを再生成し、3つのfreshness checkは全pass。`git diff --check`もpass。現サブタスクを閉じるには、Secure Inputが候補processに確実に帰属する条件でAOT native-contentを含む正規aggregateを完走し、差分review後にコミットする必要がある。ユーザーのインストール版やOS設定を無断で変更しない。
- 絶対`.app`パスだけの検証では、呼出し側がインストール版の絶対パスを直接渡した場合の誤起動はまだ拒否できない。実際のMakefile targetはすべてrepoの`build/runtime`下の候補を渡すため、`_loadInvocation`でbundleとbuild rootのsymlink解決後パスを比較し、配下以外をfail closedとする。これでInstalled appへの直接path指定やbuild内symlink経由も起動前に拒否する。その他の外部からのインストール版起動はなお制御対象外。
- `requireRuntimeBuildCandidatePath`を追加し、`_loadInvocation`でcanonical `build/runtime`配下かを起動前に検査する。単体testは正規候補、インストール版、prefixが似た兄弟directoryを検証しPASS。対象Dart format／analyzeはPASS。実機でインストール版のパスを直接`runtime_integration_smoke`に指定すると、起動前にexit 1／`an app inside the runtime build root`となり、process一覧もインストール版なし。正規の`developer-jit-note-s1`はexit 0／PASSし、その後もインストール版なし。目的の「テストハーネスがインストール版を起動しない」境界は直接・曖昧指定の両方で確認できた。
- その最終sourceに対してPhase 7 acceptance、Ghostty gap inventory、release daily-use matrixを更新し、3つのfreshness checkと`git diff --check`はPASS。`dart_appkit`には変更なし。R1正規aggregateは最終sourceで未完走。直前の長い試行ではJIT native-contentまで通過後にAOT native-contentのDirectory投影で失敗し、その後のAOT単独試行はmanual Secure Input所有で再現失敗した。機能条件を偽装せず、現在のROADMAP項目は未完了・未コミットとする。

## 2026-09-22 Secure Input再調査

- `dart_appkit`の既存native ownerは`desired && NSApp.isActive`の場合だけ`EnableSecureEventInput()`を呼び、非active時は`desired=true, owned=false, os_status=0`を返す。Dart側の`application.isActive`はtest event注入でtrueになり得るが、実際の`NSApp.isActive`は変わらない。native-content fixtureは起動直後とprotected-process focus round tripでDartのactive/focus eventを注入し、後者の直後にmanual ownershipを検査する。従って現在の失敗statusはOS前面状態との乖離で説明できるが、失敗時の`NSApp.isActive`実測はまだない。
- 選択肢: (1) manual ownership条件を緩めるのは実OS所有を確認できず不採用。(2) product controllerで`setDesired(true)`を反復しても`NSApp.isActive=false`ならnative ownerは取得しないため不採用。(3) launch時だけのPID前面化はfixture後段のfocus round trip前に行われ、以前の試行でも未解決。(4) native-content acceptanceがmanual ownershipを検査する直前に、存命のcandidate自身のPIDだけをmacOSで前面化し、実OS activeを確認してから検査する方法を採用候補とする。`dart_appkit`変更、bundle ID検索、インストール版起動は行わない。
- 候補PIDと実行ファイル絶対パスを照合するnative-content test専用JXA activationを、manual ownership検査直前に追加した。単体test、対象format/analyzeはpass。単体testをsandbox内で実行した初回は既存Metal module cacheの書込拒否でtest前に止まり、通常cache環境ではpassした。Release AOT native-contentの実GUIではmanual `owned=true, system_enabled=true, os_status=0`となり元の阻害は解消した。ただし同じsuite後段のsplit pane Directory検査が`status=privacyUnavailable`で止まった。これは同じ10秒待機中に新paneのDirectory観測権限が成立しなかったという別のproduct/fixture状態であり、条件を緩めずcontent-freeのfocus、process、Secure Input、Context Dock modeを追加観測して切り分ける。
- 追加診断を含むAOT native-content単独再実行は`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`。同じsplit pane条件もpassし、前回のprivacyUnavailableはこの試行では再現しなかった。観測失敗時だけ詳細を出すため、今回のOS focus/projection中間状態は未特定。詳細なしに条件や時間上限は緩めない。次はJIT単独とfresh aggregateで同じ境界を確認する。
- 同じsourceのDeveloper JIT native-contentも`RUNTIME_NATIVE_CONTENT_INTEGRATION_PASS`。両runtimeでcandidate-only起動、manual Secure Input実所有、後段のDirectory/split観測を通した。新しいsourceに合わせてPhase 7 acceptance、Ghostty P0/P1 gap inventory、release daily-use matrixを正規generatorで再生成した。次にR1 aggregateを同じsourceで完走する。
- 正規R1 aggregateはprofile、復旧rehearsal、R0 resource evidence、4 bundle architecture、native sanitizer、window interaction、S1/S2両runtime、root 408 file format/analyze/test、互換性、JIT/AOT hierarchyまで通過し、Developer JIT reliability内のidle CPU proxyで停止。実測は可視idle 212 basis points、occluded 35、合計123 basis pointsで、旧hard boundの合計50 basis pointsを超えた。RSS、scrollback、owner count、idle/occluded frame 0、resume frameはすべて満たした。このrunは性能以外の失敗ではなく、また2倍にした100 basis pointsも超えるので成功とは記録しない。
- ユーザーが「数msの性能は最低優先、現在の設定値の2倍までは許容」と指定済みのため、idle CPU proxy hard boundを従来の`<0.5%`から`<=1.0%`へ変更した。Productの判定と独立した結果parserの再計算を同時に更新し、100 basis points許容・101 basis points拒否の境界testを追加した。RSS／frame停止／owner count／latency条件は変えていない。Phase 11の旧評価文書は当時の履歴として残し、このR1での現行契約変更は本メモに記録する。対象format/analyzeと境界testはpass。前回実測123 basis pointsは新boundでも不合格なので、次に単独reliabilityを再実行して現sourceの合計CPUを確認する。
- 単独Developer JIT reliabilityでは合計232 basis pointsかつresource idle window中にaccepted frameが1件あり失敗。重要な訂正として、このsuiteのJITではCPUは`cpu_bound=false`と記録するだけでhard gateではない。実際の停止条件は`resourceIdleFrameDelta == 0`であり、CPU閾値変更だけでは解消しない。Resource sample直前の既存quiescence waitは10ms間隔の安定3回（約30ms）だけで、2秒のidle window中に遅れて1 frameが受理された。受け入れのzero-frame条件は維持し、resource sample前だけ最低500ms連続安定を要求する。これによりstartup後の遅延frameを測定開始前へ収めるが、500msを超える周期描画があれば従来どおりfailする。実測原因はまだ特定しておらず、このfixture修正を実GUIで再検証する。
- 500ms安定待ちでも単独JIT reliabilityの2秒idle window内でaccepted frame 1件が再現。したがって単純な直後のsettling不足という仮説は棄却する。CPU合計167 basis pointsはやはりJITの記録値で、failureの直接条件はzero-frame。次の一回の診断では、同じaccepted-frame増加時のdamage generation、model revision、build countの増分だけをcontent-freeで出し、PTY画面変化かrenderer側の重複描画かを切り分ける。描画・ownershipの条件は変更しない。
- Content-free idle-frame診断を追加した次のJIT reliability単独実行は、zero-frame、resource、ownerをすべて満たして`RUNTIME_BOUNDED_RELIABILITY_INTEGRATION_PASS`。その試行ではframe増加がなかったため、増加時のdamage/model counterは観測できず、原因は未確定のまま。条件を緩める根拠は得ていない。
- 同じsourceのRelease AOT reliability単独実行はresource idle/occluded frame 0、RSS、scrollback、owner、resume frameすべてpassしたが、合計CPU 251 basis points（visible 205、occluded 297）で、ユーザー許容の2倍上限100 basis pointsも超え`cpu_bound=false`で停止。AOTではCPUがhard gateなので、この失敗は現実の阻害要因である。これ以上の閾値緩和やR1からの性能gate除外は現行指示の範囲外であり、正規R1 aggregate、現subtaskの完了commit、次のmanual/stage subtaskへは進めない。詳細なCPU追跡はユーザー指定の優先順位が最低であることを踏まえ、この時点では行わない。
- 500ms安定待ちとidle-frame追加診断は、根因を確定できず改善も再現しなかった一時試行なので最終差分から除去した。履歴の測定値と不採用理由だけ本メモに保持する。上限2倍の契約と境界test、candidate-only activation、通常GUI復元の実装は残す。
- 最終未コミットcandidateでは対象Dart format変更0、analyze issue 0、`git diff --check` pass。CPU境界とcandidate activationのfocused testはpass済み。Phase 7 acceptance／Ghostty gap／release daily-useの3生成物を最終sourceで再生成し、個別freshness checkすべてpass。Sibling `dart_appkit`の着手前から存在する3件の作業ツリー変更には触れていない。AOT idle CPU 2.51%のhard gate失敗が残るため、ROADMAPの状態は未完了、commitなし。後続manual/stage判定には進まない。

## 2026-09-22 AOT idle CPU上昇の切り分けと進行判断

- Release AOT reliabilityの失敗値はvisible 205 basis points、occluded 297 basis points、合計251 basis points（2.51%）。過去の`build/benchmarks/product-performance-runtime-result.log`には18/14/16 basis points（合計0.16%）が残る。ただし過去のbuildと今回の候補は同一source・同一時点のA/B測定ではなく、この差だけから回帰原因を決められない。
- `TerminalCurrentProcessResourceSampler`は`MacosCurrentProcessResourceSampler`による現在の候補processの`getrusage(RUSAGE_SELF)`を使い、各2秒のvisible/occluded windowでCPU時間を差分取得する。インストール済みアプリや別processのCPU時間は加算しない。失敗したAOT測定では両windowのaccepted frame増分が0、RSS・owner・resume条件は満たしたため、少なくとも継続的な画面描画が高い値を直接説明するわけではない。
- `useOrdinaryRestoration`は`_usesInteractiveProductHierarchy(options)`で通常GUIにだけ渡し、`runtimePerformanceTest`時はfalse。今回の通常GUI復元のload/capture/commitはperformance/reliability fixtureで実行されない。現差分には既存のApp Intents/AppleScript 250 ms pollを短縮する変更や新たな周期処理の追加もない。したがってこの復元機能やインストール版誤起動をCPU上昇の原因と断定する根拠はない。
- 現在のcontent-free集計にはthread/call stack別のCPU内訳がなく、既存poll・native event・OS状態・他の長期変更のどれが支配的だったかは不明。根因が判明したと偽らない。単発の2秒測定が再現するかもこのsourceで繰り返し確認していない。ユーザーは性能の優先順位を最低とし、既存閾値の2倍までの変更後も2.51%だったことを知った上で「次に進んで良い」と明示した。今回の例外は通常GUI復元subtaskの実装・commitを進めることだけに適用し、AOT hard gateをpass扱いせず、1.0%閾値を追加で緩めない。R1 stage昇格は後続の判定で別途決める。
- 最終候補で`git diff --check`、変更Dart 19 fileの`dart format --output=none --set-exit-if-changed`（変更0）、対象18 fileの`dart analyze`（issue 0）、root `CI=true dart run test/run_tests.dart`（`dart_terminal tests passed`）を確認した。最初の`dart test ...`試行はsandbox外のMetal module cache書込拒否でtest実行前に失敗。`CLANG_MODULE_CACHE_PATH`指定でも同じ場所への書込を試み失敗した。通常build権限で同コマンドを試すと、このrepoには`package:test`がなくCLIがexit 65となるため、正規の`test/run_tests.dart`を使った。AOT idle CPU hard gateの失敗は残したまま、機能検証とこの利用者例外を根拠に現在のsubtaskだけを閉じる。
