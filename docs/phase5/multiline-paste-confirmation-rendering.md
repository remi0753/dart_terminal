# Multiline paste confirmation rendering

## 目的

複数行Pasteを再操作で承認したとき、貼り付けたコマンドの先頭に以前の文字が重複して
見える表示不整合を解消する。PTYへ送るPaste内容とshellの実行結果は変えず、terminalの
canonical screenとinteractive shellのカーソル状態を一致させる。

## 背景

2026-09-19、通常のzsh promptで複数行のdistribution commandをPasteした際、最初の
Pasteでcontent-free confirmationが表示され、同じ内容を再度Pasteすると、画面上だけ
先頭の`ma`が残って`mamake`のように見える事象が報告された。Return後の実行は正常な
ため、Paste payloadの破損ではなく表示状態の不整合として扱う。

## 範囲

- 通常のclipboard Pasteにおけるconfirmation表示と再操作承認
- shellのcursor／line editor redrawとterminal canonical screenの整合性
- 同じnotice経路を使う外部Pasteやhyperlink noticeへの影響確認
- 再現する回帰テストと既存clipboard受け入れの更新

## 対象外

- Pasteの64 MiB admission、危険文字判定、10秒approval authorityの変更
- bracketed-paste wire encodingやbounded PTY transportの変更
- OSC 52 clipboard policyやnative pasteboard ownershipの変更
- confirmationの文言へPaste内容を含める変更

## 依存関係

- `TerminalSession.showClipboardNotice`とterminal parser／screen set
- `TerminalPasteApprovalGate`と`TerminalPasteCodec`
- Metal rendererへ渡すcanonical screen／overlay model
- runtime clipboard product acceptance

## 完了条件

- confirmation表示がPTYへ書き込まれず、Paste payloadも従来どおりexactである。
- confirmation後にinteractive shellが再描画しても、先頭文字が重複または残留しない。
- confirmationはcontent-freeかつ利用者が再操作方法を認識できる形で表示される。
- noticeのfocus／session／dispose境界が明確で、別paneへ漏れない。
- unit／integration／Developer JIT／Release AOTの関連検証が成功する。

## 検証方針

- canonical screenへnoticeを書き込む前後のcursor／cell不変条件をテストする。
- confirmationを挟む複数行bracketed PasteのPTY bytesがexactであることを維持する。
- product clipboard acceptanceでnoticeの可視性と再操作後の画面整合性を確認する。
- `dart format`、対象テスト、静的解析、関連runtime smokeを実行する。

## 調査記録

### 2026-09-19 初期確認

- 添付画像では、confirmation後のPaste内容が最終的に`mamake ...`のように見える一方、
  コマンド実行は正常だった。
- `TerminalSession.showClipboardNotice`は`TerminalBuffer.appendStatusLine`に加えて、
  `TerminalParser.parse('\r\n$message\r\n')`でcontent-free noticeをcanonical terminal
  screenへ直接注入している。
- この注入はPTYへ送られないため、shell line editorが認識するcursor位置は変わらない。
  その後shellが出力するbracketed Pasteのecho／redrawだけが、terminal側で移動済みのcursor
  を基準に解釈され、表示だけがずれる可能性がある。
- `TerminalPasteCodec`のbracketed Paste payloadは既存テストでexactに検証されており、
  現時点ではtransport破損を示す証拠はない。
- 既存runtime clipboard acceptanceはconfirmation文字列がcanonical screenに存在することを
  前提にしている。この前提を保つか、screenを変更しないpresentationへ移すかを、既存の
  overlay／native surface境界を確認して判断する。

### 選択肢と判断

- terminal escapeのcursor save／restoreでnoticeを挟む案は採用しなかった。viewport最下段で
  noticeがscrollを起こすと、shellが認識するcursor行と保存座標の対応を保証できず、shell
  非関与のscreen mutationという根本原因を残すためである。
- Metal gridへnotice文字列を合成する案も検討したが、既存grid overlayはcontent-freeな
  geometry用であり、任意textのaccessibility projectionを新設する範囲が大きい。
- 既存のgeneric AppKit `ViewBadge`をpane presentationとして使用する案を採用した。この
  surfaceはcanonical cells／cursorを変更せず、bounded safe display textとaccessibility
  label／helpを備えている。
- `ViewBadge`はpaneあたり1つなので、Secure Keyboard Entry indicatorを上書きせず、両方が
  activeな場合はsecure stateとterminal noticeを1つのbounded badgeへ合成する。

## 実装

- `TerminalSession.showClipboardNotice`と`showHyperlinkNotice`から、PTY由来でない文字列を
  `VtParser`へ渡す処理を削除した。
- sessionはcontent-freeな`TerminalSessionPresentationNotice`だけを最大10秒保持する。
  次のterminal input／Paste開始時、timeout、session shutdownで破棄する。
- 通常のinteractive hierarchyと単一pane runtimeの双方でnoticeをnative pane badgeへ
  投影する。paneごとのsession stateだけを参照するため別paneへ漏れない。
- `terminalViewBadge`がnotice-only、secure-only、両状態の合成を担い、native 256-byte boundを
  投影前に検査する。
- runtime clipboard acceptanceへ実zshのbracketed multiline Pasteを追加した。notice表示前後で
  canonical generation／cursorが不変で、Paste後の`PS1 + 先頭文字列`がexactであることを確認し、
  実行せずSIGINTでfixtureを終了する。
- 既存10 MiB acceptanceは、confirmationがbadgeで可視、canonical screenには不在、確認前の
  PTY writeが0、再操作後のpayloadがexactという契約へ更新した。

## 検証結果

### 静的・単体・統合

- `dart analyze`: issue 0。sandbox内ではanalytics session fileのmtime警告だけが出たが、
  analyzer自体は`No issues found!`で終了した。
- `dart run test/terminal_view_badge_projection_test.dart`: 成功。
- `dart run test/run_tests.dart`: 成功、`dart_terminal tests passed`。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。native dependency、生成物freshness、
  analyzer、全Dart testを含む。
- `git diff --check`: 成功。

### 実AppKit／PTY／zsh

- `make RUNTIME_ARCH=arm64 developer-jit-clipboard`: 成功。
  `RUNTIME_CLIPBOARD_INTEGRATION_PASS mode=developer-jit`を確認した。
- `make RUNTIME_ARCH=arm64 release-aot-clipboard`: 2回目に成功。
  `RUNTIME_CLIPBOARD_INTEGRATION_PASS mode=release-aot`を確認した。
- 両modeで`TERMINAL_MULTILINE_PASTE_VISUAL_TEST canonical_unchanged=true
  zle_prefix_exact=true`が成立した。
- Release AOT初回は新規zsh visual testと全641 paste chunk完了後、既存
  `__DT_CLIPBOARD_EXACT__` markerの5秒待機だけがtimeoutした。同一source／buildの再実行は
  3.1秒で全体が成功したため、再現しない既存fixture timing failureとして記録する。

### 生成証跡

`FEATURE_MATRIX.md`のIN-08を更新したため、次を正規generatorで再生成し、freshness checkを
`make test`で受け入れた。

- `compatibility/regression_coverage_report.json`
- `compatibility/ghostty_p0_p1_gap_inventory.json`
- `test/corpus/appkit/phase7_acceptance_v1.json`
- `compatibility/release_candidate_daily_use_matrix.json`

## 残課題

この修正に属する残作業はない。Release AOT初回のmarker timeoutは再現せず、既存の
10 MiB acceptance自体も再実行で成功した。繰り返し再現する場合はfixture完了markerの
待機時間／process schedulingを独立した信頼性タスクとして追跡する。
