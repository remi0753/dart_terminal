# Phase 7 — Process Inspectorの入力保護と情報表示の分離

## 目的・背景

利用者本人向けのread-only process情報表示を、秘密入力の保護と独立させる。
現行のECHO-off／manual Secure Keyboard Entryによる一律非表示はNode REPLなどでも
発生する。取得対象はOSのprocess metadataであり、stdinや入力中のpasswordではない。
ECHO状態はargvに秘密が含まれるかの判定には使えない。

## 範囲

- ECHO-offとmanual／automatic Secure Keyboard Entry中もProcess Inspectorを表示する。
- 引数の表示を既定で有効にし、入力保護とは独立した利用者操作で切り替える。
- Secure Keyboard Entry、Navigatorのpath insertion保護、focus／session／PGID／visibility失効、
  bounded sampling、diagnostics／export／restorationへの非記録を維持する。
- native UI、English／Japanese、unit／privacy／両runtime受け入れ、referenceを更新する。

## 対象外

- stdin、password、environment、terminal outputの取得・記録。
- remote SSH観測、process操作、新たなキーボード監視。
- argv中の秘密の自動推測、既存Secure Keyboard Entry policyの変更。

## 依存関係・リスク

`TerminalContextDockPrivacyPolicy`、product bootstrap、process coordinator、native presenter、
action/menu/palette、既存process metadata capabilityを使う。表示と入力保護を共有したまま
緩和するとpath insertionまで許可してしまうため、process専用判定を分離する。
画面共有等ではargvだけでなくpathにも露出リスクがあり、Dock自体の非表示操作は維持する。

## 実施順・個別完了条件

1. process観測の入力保護判定を分離する。ECHO-off／manual secureでもmetadataを表示し、
   Navigator/path insertionとSecure Keyboard Entryの既存保護が維持されることをunit／
   privacy gateと両runtimeの実PTY／native documentで確認してcommitする。
2. 入力保護から独立したargv表示切替を実装する。menu／paletteからkeyboard-onlyで操作でき、
   非表示時にnative visual／accessibility documentへargvを出さず、process名／path／PID／elapsedは
   維持する。focus／runtime regression、localization、reference、全体検証後にcommitする。

## 検証方針

対象unit test、format／analyze、diagnostics privacy audit、arm64 Developer JIT／Release AOT
native-content integrationを実行する。ECHO-off fixtureは既存のbounded sh commandを使い、
利用者のscriptを実行しない。視覚／外部VoiceOverの未実施事項はmanual checklistで区別する。

## 調査・判断記録

### 2026-09-16 — 着手

- branchは`codex/context-file-navigator-roadmap`。tracked差分なし。untracked `cat`は利用者所有として
  参照・変更・stageしない。
- README／FEATURE_MATRIXは未改変runtime、Dart-only product logic、native capability境界と
  local-only process metadata表示を契約としている。ROADMAP上の既存主要機能は完了済みで、
  新規作業をProcess Inspector直下、低優先external follow-upより前へ登録する。
- `lib/src/terminal_context_dock_path_handoff.dart`の`canObserve`がfilesystem観測とprocess観測の両方に
  接続されている。manual secureとECHO-off foregroundを拒否し、idle shellだけ例外にしている。
- `lib/src/terminal_application.dart`のproduct native-content fixtureがECHO-off時の`Protected input`と
  argv破棄をassertする。この期待値を新方針へ置き換え、filesystem停止／terminal input ownerは維持する。
- 既存のSecure Keyboard Entry取得・indicator・balanced release実装は変更しない。
- argv表示切替に新しい既定chordは割り当てず、View menu／command paletteのshared actionと
  任意keybindで提供する。既存shortcutとの競合を避ける。

### 2026-09-16 — process専用観測authority

- `canObserveProcess`をSecure Keyboard Entry状態を受け取らないlive identity判定として追加し、
  productのprocess resolverだけを接続した。filesystemとpath handoffは従来の`canObserve`を維持する。
- coordinator unit fixtureはECHO-offを常用するように変更し、表示、refresh、PGID／focus失効を
  実入力保護状態から独立したexplicit vetoでも検証する。
- native-content fixtureはECHO-off foreground commandを表示し、その途中でmanual secureを取得して
  process情報と`ownedEnabled`の両方を確認する。stdin内容は観測しない。最大待機時間は従来どおり。
- 初回format／analyzeはSDK analyticsがsandbox外のtelemetry logへアクセスして終了code 1になった。
  formatterの変更とanalyzeの`No issues found`は得られたが、成功扱いにはせず通常の権限で再実行する。
  対象unitとprivacy auditは成功。runtime buildはSDK／native buildの通常権限で実行する。
- Developer JITの初回native-contentはmanual取得直後の即時`ownedEnabled` assertionで失敗した。
  native leaseの反映は非同期であり、既存Secure Keyboard Entry suiteもwait条件で確認している。
  fixtureをreconcile付きのbounded waitへ修正する。製品のlease／入力保護policyは変更しない。
- 2回目は旧fixtureの「Search actionがdisabled」という期待値で失敗した。Process Inspectorでは
  shortcutをbeep／PTY writeなしで消費するためactionはenabledだがNavigatorへfocusを移さない。
  新方針でこの経路がECHO-off中にも使われるため、実dispatch後のterminal ownership／write countで
  入力を奪わないことを検証する。directory snapshot停止条件は維持する。
- 通常権限での再検証: `dart format`は4 file／変更0、`dart test/terminal_context_dock_test.dart`、
  `dart test/terminal_secure_keyboard_entry_test.dart`はexit 0、`dart analyze`はissue 0。
  `dart tool/terminal_diagnostics_privacy_audit.dart`はschema 190／owner 11／top-level 11で成功した。
- `make RUNTIME_ARCH=arm64 runtime-native-content-integration`は最終再実行でDeveloper JIT
  11,125 ms／Release AOT 9,845 ms、両方exit 0。ECHO-off表示、manual secure owned、Searchの
  zero-write消費、metadata／fixed details、pipeline、elapsed、終了後Directory復帰と4 session回収を確認した。
  Node自体を必須dependencyにはせず、同じECHO-off状態の実PTY fixtureで再現する。
- サブタスク1は完了。argvの独立切替は次の未完了項目として追跡する。外部VoiceOver／視覚確認は
  manual checklistへ残し、自動native document検証と区別する。
