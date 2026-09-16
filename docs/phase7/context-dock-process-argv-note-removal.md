# Process Inspector argv note removal

- Status: complete
- Date: 2026-09-16
- Scope: Phase 7 Context Dock process presentation

## 目的、背景、範囲

統合したProcess Inspectorを簡潔にするため、「Each quoted token is one argument, not the original shell source.」
および日本語の同等説明を削除する。argv自体の引用符、control／bidi escape、省略・truncation表示、引数表示切替は維持する。

## 対象外と依存関係

- レイアウト、refresh、入力所有権、privacy、process観測、native／FFI、SSHの変更はしない。
- TerminalContextDockDirectoryPresenterのbuildProcess、typed localization、native hierarchy fake／native-content受け入れを使う。
- READMEとFEATURE_MATRIXの製品仕様（processから観測したargv、read-only単一表示）は変更不要。

## 完了条件、リスク、検証方針

- English／Japaneseの説明がvisual／accessibility文書に出ず、quoted argvとmetadataはそのまま表示される。
- 不要なlocalization getterを削除し、元の表示必須assertionを非表示assertionへ置き換える。
- focused hierarchy／localization tests、format／analysis、privacy、generated freshness、full make testを通す。
- 両runtime native-contentのpipeline文書でもEnglish説明の非表示を検証し、buildと実AppKit＋PTY検証を行う。
- quote／escapeやargv非表示契約を誤って変えないことが主要リスクである。VoiceOver読み上げ品質は既存manual checklistの外部確認範囲とする。

## 調査記録

### 2026-09-16 着手

- branchはcodex/context-file-navigator-roadmap、working treeはclean。
- README、ROADMAP、FEATURE_MATRIX、既存の単一表示メモ、ADR-005、repo構成／path dependencies、Makefile、関連code／testを確認した。
- 説明はbuildProcessのargv非empty分岐でprocessInspectorArgvNoteを1回出力する。getterにEnglish／Japaneseの2 copyがある。
- native hierarchy testは日本語説明を必須にしており、同じassertionでquoted raw argvとescapeも検証している。
- 最小変更として出力行とgetterだけを削除し、JP fake／English実native fixtureで非表示を固定する。

### 2026-09-16 実装

- 説明の出力1行とlocalization getterを削除した。JP fakeでは説明の両文の非表示、English native fixtureではprefixの非表示をassertする。
- 同じfixtureのquoted argv／control・bidi escape／executable／PID／PGID／省略・truncation検証を維持した。
- manual checklistも両localeの説明非表示と引用符維持へ同期した。その他のUI仕様に変更はない。

### 2026-09-16 検証途中結果

- 対象4 Dart filesのformatは変更0・成功。native hierarchy／localizationのfocused testsは成功した。
- diagnostics privacy auditは成功（190 schema keys、11 owners、11 top-level keys）、privacy contractは不変。
- Phase 7 acceptance → compatibility coverage → gap inventory → daily-use matrixの既存generatorはすべて成功した。
  生成物差分は変更source／testのhashのみ。README／FEATURE_MATRIXが不変のためcoverage report自体には差分がない。
- git diff --check: 指摘0。getterと表示側の参照はなく、説明prefixは非表示assertionと記録にのみ残る。
- generator終了後に両runtime native-contentのbuild／実AppKit＋PTY検証を開始した。既存の正確なbundle pathによるLaunch Services経路を使う。
- Developer JIT native-contentは成功（11,120 ms）。English説明prefixの非表示、argv／executable／PID／PGID、
  pipeline／入力所有権／引数表示切替／directory復元と4 sessions／native handle cleanupを通過した。Release AOTのbuildを継続する。
- Release AOT native-contentも成功（9,884 ms）。make RUNTIME_ARCH=arm64 runtime-native-content-integrationはexit 0で両modeのbuild／suiteを完了した。
- runtime／generatorの終了後、full make testを単独開始した。新たな失敗試行や製品境界の変更はない。
- full gate途中のnative capability、localization／privacy、Phase 7／compatibility／distributionとgenerated freshnessは成功した。
  gap inventoryの102 rows／accepted 97／documented differences 2／external follow-ups 3／actionable P0・P1とも0は不変。
- full gateのformatは347 files／変更0、analyzeは指摘0。残りのDart test suite完了を待つ。

### 2026-09-16 完了

- full make testはexit 0、dart_terminal tests passed。全Dart test、security stress、native capability、全generated freshnessを通過した。
- 最終diffを確認し、説明の出力／getter削除、JP／Englishの非表示assertion、manual checklist、task記録、source hash更新だけを含む。
  引数引用符・escape、レイアウト、refresh、入力保護／ownership、観測・保持上限を変更していない。git diff --checkは指摘0。
- 本修正に実装残課題・blockerはない。VoiceOverの実機読み上げ品質のみ既存manual checklistの未確認項目として維持する。
