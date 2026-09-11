# Settings editor disabled-line / cursor-line visual clarity

Status: in progress (2026-09-11)

## 目的

Settings editorで、コメントアウトされた設定項目が無効であることを行全体の
グレー表示で即座に判別できるようにする。また、NORMALとINSERTのどちらでも現在の
カーソル行を淡い背景で示し、syntax highlightとテキストの色を切り替えない。

## 背景と確認事項

- 現行の`_TerminalSettingsDocumentAnalyzer`は、`# option = value`を設定項目として解析し続ける
  ことでdetail/search対象を保つ一方、`#`と直後の空白だけを`comment`としている。その後の
  option name、operator、valueにactive行と同じsyntax色が付くため、無効状態が視覚的に弱い。
- 通常の行末コメントは、代入部分は有効である。そのため`option = value # note`は従来どおり
  `# note`だけをグレーにし、行頭の最初のnon-whitespaceが`#`の場合だけ行全体をdisabledにする。
- Settings presenterは同一のnative `TextEditor`をNORMAL/INSERT間で維持し、色付きrunを
  `setStyleRuns`で更新する。NORMALではeditorがread-onlyになるためAppKit caretが見えず、現在地を
  detailパネルから間接的に推測するしかない。
- `dart_appkit` public `TextEditorStyleRun`はforegroundとunderlineだけを表現し、行背景は投影できない。
  text selectionを行全体にする方式はselection/caret意味論、horizontal movement、detailの対象、
  INSERT開始位置を変えるため採用しない。

## 分割と実施順

### 1. `dart_appkit` attributed editor line highlight

generic `TextEditor`に、UTF-16 scalar boundary上の位置と背景色を指定するoptional line-highlight
APIを追加する。native側で対象のlogical line fragmentを求め、`NSTextView`のbackground drawingで
editorの横幅全体へ適用する。syntax foreground/diagnostic underlineとは独立させ、style-only updateの
影響を受けない。document交換時はstale locationを残さないようhighlightをclearする。

完了条件:

- public/fake/FFI/C ABI/native bridgeがnullable highlightを同じ所有権と検証で扱う。
- out-of-range、surrogate分断、invalid colorをnative変更前に拒否する。
- foreground、underline、backgroundが併存し、style-only updateでline backgroundが消えない。
- siblingのworklog/verification、focused test、完全`make test`を成功させ、独立コミットする。

### 2. product disabled/current-line projection

行頭コメントの設定行は、occurrenceを維持しつつindentから行末まで1つのcomment syntax spanに
する。Settings presenterはstate selectionのstart行へ淡いproduct-owned背景を投影し、NORMALの
Dart navigation、SEARCH result移動、INSERTのnative caret/mouse同期のすべてで同じAPIを更新する。

完了条件:

- `# option = value`とcommented nullable/repeatable exampleの全文字がcomment色になり、検索/detail対象は維持する。
- active assignmentのinline commentだけは従来どおりtoken以降だけがcomment色になる。
- cursor line backgroundはNORMAL/SEARCH/INSERTでselectionと同期し、syntax foregroundとdiagnostic underlineを変えない。
- focused fake/native/product test、formatter、analyzer、全test、source/bundle audit、M1両runtimeの
  Settings acceptanceが成功する。

## 範囲

- Settings documentのpresentation-only syntax analysis。
- reusable attributed editorのoptional logical-line background。
- modal editorのcaret/selectionからcurrent lineへの同期。
- 色と状態のfocused/native/runtime回帰検査。

## 対象外

- config parserにおける`#`の意味、値の優先順位、save/reload policyの変更。
- マルチカーソル、列選択、selection direction、テーマごとのSettings palette設定。
- terminal Metal cursor、terminal selection、Settings以外のUIデザイン変更。
- Phase 9以降のprotocol実装。

## 依存関係とリスク

- native text座標は`NSString` compatible UTF-16であり、surrogate pairを分断しない。
- native editorはhighlight stateをattributed styleから独立保持し、background drawingでglyphより先に
  描画する。これによりstyle再投影やeditable切替でforeground/underlineを変えない。
- コメント行を1 spanにしても、schema occurrenceとvalue rangeはsearch/detailのため従来通り解析する。
- INSERT中のmarked textに対してdocument/selectionをDartから再設定せず、line highlightだけを別更新する。

## 検証方針

1. sibling public API/fake testとnative bridge testでline range、色、clear、style併存、異常系を固定する。
2. product editor testでcommented assignmentの全文字spanとoccurrence維持を固定する。
3. fake AppKit presenter testでNORMAL/SEARCH/INSERTのcurrent-line locationとsyntax run不変を固定する。
4. M1 Developer JIT / Release AOTのconfiguration acceptanceで実native editor投影とcleanupを確認する。
5. 両repositoryのfull testとdart_terminalのsource/bundle auditを実行する。

## 調査・実装ログ

- 2026-09-11: Phase 8は直前のRetina typography修正まで全項目完了、Phase 9のKitty
  keyboard protocolが最初の未完了項目だった。本依頼をPhase 8最後の追補としてPhase 9より
  前に登録し、Phase 8を再度開いた。両repositoryは着手時にcleanだった。
- 2026-09-11: commented assignmentでは`isCommented=true`のoccurrenceが正しく保持されるが、
  comment spanは`#`prefixに限定され、name/operator/valueがactive行の色で上書きされることを
  sourceで確認した。
- 2026-09-11: 現行`TextEditorStyleRun`はforegroundとoptional underlineのみで、背景の所有者は
  ない。selectionを見た目の代用にする案はmodal editingの意味論を変えるため不採用とし、
  nullable line-highlightをforeground/underlineと直交する別APIとして追加する。
- 2026-09-11: `NSBackgroundColorAttributeName`だけでは文字glyphの範囲に背景が限定され、editorの
  横幅全体を示すcursor-lineにはならないため、native `NSTextView`のbackground drawing層でlogical
  line fragmentの高さとvisible/document幅を合成する方式へ詳細設計を変更した。最初のnative buildは
  内部subclass型をpublic `NSTextView` getter経由で参照したため`-Werror`で停止し、subclass型の保持ivarを
  直接参照するよう修正した。
- 2026-09-11: 次のfocused runではnative contract testが通過した一方、Dart analyzerが新しい
  public型をpackageの`show` exportに追加していないことを検出した。`TextEditorLineHighlight`を
  明示exportへ追加し、内部実装だけが見えてpublic consumerから利用できない状態を解消した。
- 2026-09-11: sibling APIはlogical line fragmentの高さとeditorのdocument/visible幅を使う
  background drawingとして完成した。foreground/underline属性を変更せず、style-only更新後も
  維持され、nullまたはdocument交換でclearされる。focused `make native-test dart-test ffi-smoke`と
  完全`make test`が成功した。public/fake/FFI/C ABI/native/README/worklog/verificationを更新済み。
- 2026-09-11: siblingを`a24d799ea397cfc8fa2aa3d82668394656a95730`
  (`Add full-width text editor line highlights`)として独立コミットした。ROADMAP再確認時点の現在地は
  本親項目の第2サブタスクで、次はcommented assignmentの全行comment投影とNORMAL/SEARCH/INSERTを
  またぐselection追従line highlightである。
