# Process Inspector unified layout

- Status: complete
- Date: 2026-09-16
- Scope: Phase 7 Context Dock process presentation
- Related: UI-02、UI-04、AX-01

## 目的と背景

Process Inspectorの一覧とProcess Detailsに分散した少量の情報を一つの表示へ統合する。
「Directory Navigator is available when the shell is idle」と日本語の同等案内は表示しない。
Directory Navigatorでは、多件数の一覧と選択項目を同時に確認する既存の固定詳細欄を維持する。

## 範囲と対象外

- process状態では右Dock全高を一つのread-only文書に使い、名前、経過時間、実行ファイル、argv、PID／PGIDをまとめる。
- shell-owned、loading、unavailable、明示的なprotected状態も同じ単一表示にする。
- 下段文書を空にし、非表示にする。process終了時はDirectory Navigatorの二段表示を復元する。
- 入力所有権、refresh頻度、snapshot上限、argv表示切替、privacy／cleanupを変更しない。
- 新action／shortcut、process操作、SSH対応、Directory Navigatorのレイアウト変更は対象外。

## 依存関係、リスク、完了条件

- presenter-ownedなTextEditor二つとvertical TwoPaneSplitView、既存process content snapshotを使う。
- native APIやFFI追加なし。単一表示時の空白・divider残存、旧argvの下段保持、定期更新によるfocus／selection／scroll移動を防ぐ。
- process情報が一つの可視文書だけにあり、Process Details見出しと待機案内がない。
- directoryへ戻ると同じnative resource identityで固定詳細高、query／mode、terminal input ownershipを復元する。
- focused tests、format／analysis、privacy audit、両runtime native-content、generated freshness、full make testを通す。

## 検証方針

- fake AppKitで全process状態の文書統合、下段消去と非表示、directory復元、elapsed refresh時のselection／scroll／focus、argv非表示を固定する。
- 実AppKit＋PTYのpipelineとECHO-off／Secure Keyboard Entry fixtureを統合表示へ更新し、Developer JIT／Release AOTで実行する。
- README、FEATURE_MATRIX、manual checklistとgenerated evidenceを同期する。VoiceOverの読み上げ品質は手動確認票で追跡する。

## 調査記録

### 2026-09-16 着手

- branchはcodex/context-file-navigator-roadmap。tracked treeはclean、既存untracked catは本作業の対象外として保持する。
- README、ROADMAP、FEATURE_MATRIX、関連Phase 7 layout／process／privacyメモ、ADR-001／002／005、Makefile、presenterとfake／native acceptanceを確認した。
- 現状はbuildProcessが一覧文書と詳細文書を別々に構築し、directoryと同じ210 ptの下段を常に確保する。
  待機案内はforeground本文、shell-owned本文、shell-owned詳細の三箇所にある。
- dart_appkitは隣接repoのpath dependencyであり、本repoのpackages配下ではない。
  TwoPaneSplitViewはsetPositionのfraction=1を許さないが、既存のbinary zoomedChild APIを持つ。
  reparentや新view生成よりも、同じinner splitでfirst childのzoomを切り替える方がownershipと復元を最小変更で維持できる。

### 2026-09-16 実装と確認事項

- 隣接dependencyのTextView.mmでdaApplyLayoutを確認した。first childのzoom中はsecond childをhiddenにし、
  first childのframeをsplit全boundsへ設定する。setPositionを再適用してもzoomは維持され、解除時は保存した二段geometryへ戻る。
- この既存APIでprocess文書中だけfirst childをzoomする。下段textも空文字で更新し、隠すだけで古いdirectory pathやargvを残さない。
- process名／elapsedとprimary executable／argv／PID／PGIDを上段の一つの文書に連結した。
  Process Details見出し、重複したInput／protected／unavailable、待機案内三箇所を除去し、不要なlocalization getter二つも削除した。
- fake acceptanceはloading／ready／shell-owned／protected／unavailableの全高表示と下段消去、argv非表示／再取得、elapsed更新時の
  executable位置のselectionとreveal回数維持、directory復帰時の固定210 pt geometryを検証するよう更新した。
- native product acceptanceもpipeline／argv表示切替／ECHO-off／manual secureのmetadataを単一文書で検証し、下段空と全高zoom、
  終了後のDirectory Navigatorの固定詳細復元をassertする。
- native fixture更新用patchの最初の試行は読み取り範囲がinsertText行の途中からだったため、guardでhelper未検出として停止した。
  file変更は行われず、範囲を前へ広げて同じ編集を適用した。初回dependency native検索のglobも存在しないpathで失敗し、rgで実pathを解決した。

### 2026-09-16 検証途中結果

- 対象4ファイルのdart format: 成功、2ファイル整形。dart analyze: 指摘0。
- terminal_native_hierarchy、terminal_context_dock、terminal_localization、terminal_secure_keyboard_entryの各Dart test: すべて成功。
- terminal_diagnostics_privacy_audit: 成功、schema 190 keys／11 owners／11 top-level keysを維持し、process textやargvのexport追加はない。
- git diff --check: 指摘0。両runtime native-contentのbuild／実AppKit＋PTY検証を開始した。
- 初回Developer JIT native-contentはmanual Secure Keyboard EntryのownedEnabled待機で失敗した（status 70）。
  それより前の単一process文書、不要案内除去、全高zoom、argv切替、pipeline終了時のdirectory固定詳細復元は通過した。
  本変更はSecure Input policy／native leaseに触れていないため、既存のapp activation依存と表示変更の影響を区別して調査・再検証する。
  failureを完了扱いにせず、Release AOTは初回JIT失敗によりまだ未実行である。
- 四つの既存generatorを依存順に実行して成功。生成物差分は変更source／test／README／FEATURE_MATRIXのhashのみで、acceptance分類を変更していない。
- native leaseのAppKitBridge.mm:daApplyForCurrentApplicationActivityはdesired && application-activeのときだけOS入力保護を取得する。
  native-contentのlaunchはactivateAfterLaunchがfalseだった一方、既存のSecure Keyboard Entry suiteはtrueを指定していた。
  今回のmanual secureを含む受け入れにも同じ既存Launch Services activationを追加して、非active状態でownedを要求する前提矛盾を除いた。
  製品のlease／入力保護を変更したり、assertionを弱めたりしていない。
- 再実行のJITは11,283 msで成功したが、AOTはpipeline表示待機で失敗し、同じAOT bundleの直接再実行でも再現した。
  両bundleのCFBundleIdentifierは同じdev.dart-terminalで、open -bの追加activationは別build／既存appを選び得る。
  これは本機能のcanPresentWindowが実AppKit active／focusedを必須とする条件と両立しない。
  native-contentだけ、既存のthroughLaunchServices=true経路で指定したbundle絶対pathをopen -n -Fする方針へ修正した。
  この経路は既存suiteで使うbounded launch／環境注入／stdout capture／diagnostics／cleanupを再利用し、共有activation helper自体は変更しない。
- default sandboxでのpsによるhost inventoryはOSに拒否された。既存user appを終了するなどの操作はせず、正確なbundleを起動する検証経路で対処する。
- 最終launch経路で、build済みRelease AOT bundleをdart run tool/runtime_integration_smoke.dart --mode=release-aot
  --suite=native-contentで実行し成功（9,438 ms）。全高process表示、pipeline、argv切替、ECHO-off／manual secure、
  directory復元、exact PTY、4 sessions／worker／native handle回収を通過した。
- 最終launch経路のJIT初回はprocess／secure／directory復元の全assertを通過した後、既存context Quick Lookのaction resultが
  unavailableとなり失敗した（status 70、terminal_application.dartのcontext Quick Look assertion）。
  同時にgeneratorが動いていたが因果は未確定。Quick Lookの製品実装や受け入れ条件を変更せず、generator終了後に同じbundleを単独再実行する。
- JITの単独再実行は成功（10,544 ms）。同じcontext Quick Lookも通過し、製品や既存assertを変更せず両runtimeの全native-content suite成功を確認した。
  今回は両runtime bundleをbuildした後、最終版toolで各--mode／--suite=native-contentを直接実行した。
  throughLaunchServices採用後のgenerator再実行も成功。runtime／generatorの終了後、full make testを単独開始した。
- full gate途中のnative capability、汎用PTY（以前raceのあったlive Dart childのcompletion testを含む）、renderer／AppleScript／App Intents、
  localization、privacy、Phase 7 acceptance、compatibility regressionは成功した。
- 最終tree確認では当初のuntracked catがstatusに表示されなくなった。本作業の編集／削除／stage対象には含めていない。
  ソース検索でもその固定ファイルを削除する処理は確認できず、原因は未確定。本taskの差分・commitには含めない。

### 2026-09-16 最終検証と完了

- 単独make test: exit 0、dart_terminal tests passed。347 Dart filesのformat変更0、analyze指摘0、全Dart test、
  native capability、security stress、localization／privacy／Phase 7／compatibility／distribution policyとgenerated freshnessが成功した。
- gap inventoryは102 rows／accepted 97／documented differences 2／external follow-ups 3、actionable P0／P1とも0を維持した。
  generator差分はsource／dependency hashのみで、既存acceptanceやclassificationの緩和はない。
- 最終git diff --checkは指摘0。native／FFI／process sampler／入力保護policyの変更、debug出力、不要生成物、秘密情報、無関係なstageはない。
- 単一Process Inspector、不要案内除去、非表示下段の消去、elapsed／argv更新時のinput ownership、directory固定詳細復元、両runtime cleanupを確認した。
- 本taskに追加の実装課題・blockerはない。VoiceOverの実機読み上げ品質と主観的な視覚評価は更新したmanual checklistで未確認として追跡する。
  初回activation前提矛盾と単発Quick Look失敗の試行記録は上記に保存した。
