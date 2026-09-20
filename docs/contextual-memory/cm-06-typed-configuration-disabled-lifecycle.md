# CM-06 typed configuration and disabled lifecycle

日付: 2026-09-21
状態: 実装中

## 目的

S1〜S3のlocal kill switchとNote表示fontを既存typed configurationへ統合し、Notesが無効な起動では
Note worker、store access/directory、context binding、surface、timerを一切生成しないcomposition-root境界を作る。
Reloadではrestart境界とlive変更を混同せず、invalid candidateを従来どおり全体rejectする。

## 背景

- Gate 7のD-44は`notes`、`notes-on-return`、`notes-next-prompt`を`nextLaunch`、`notes-font-size`を
  `live`と確定している。初期defaultは順にfalse、true、false、15である。
- 既存schema/reloadは`live`と`newSession`だけを持ち、reference、`--show-config`、Settingsは同じschemaから生成される。
- CM-05でNote authority/store/surface lifecycle contractは完成したが、product applicationへはまだ生成経路を接続していない。
  User-facing action/pane wiringはCM-10以降であり、本タスクはadmissionと設定projectionまでを対象にする。

## 範囲

- `nextLaunch` application policy、4 typed options、12〜24 finite font validation。
- internal-preview/public exposure metadataと、public reference/Settings filter、typed resolution、provenance、`--show-config`。
- Reload後のpending-restart projection、launch-effective kill switch不変、live Note font projection。
- Injected factoryを持つproduct-owned Note composition root、disabled/enabled/re-enabledの完全teardown。
- C-01〜C-03、disabled key→PTY baseline差+5%以下、既存configuration freshness/quality gate。

## 対象外

- R2 public documentation/default-on promotion、S3 version 3 protocol event、Note action/card/editor/native surface。
- `dart_appkit`へのTerminal固有option、Note authority、store path、pane lifecycleの追加。
- Reload中にcurrent authorityをcreate/disposeすること。Feature enablement変更は次回起動だけで反映する。

## 依存関係

- CM-05 Note authority lifecycle。
- `TerminalProductConfigSchema`、`TerminalConfigReloadController`、`TerminalProductConfigurationAuthority`、
  schema-generated reference/effective config/Settings editor。
- Gate 7 D-44、C-01〜C-03と通常のconfiguration/Developer JIT/Release AOT gate。

## サブタスクと順序

1. Typed optionと露出制御を実装する。
   - `nextLaunch`とinternal-preview/public metadataをschema型へ追加する。
   - 4 optionsを既存priority/diagnostic/provenanceへ統合し、公開前のreference/Settings filterを固定する。
   - 完了条件: default/valid/invalid/include/CLI/`--show-config`/reference freshness/filter testsがpassする。
2. `nextLaunch` reloadとlive Note projectionを実装する。
   - Startup snapshotとの差からpending restartを算出し、current launch flagsは不変にする。
   - `notes-font-size`だけをlive projectionし、invalid mixed reloadは全体rejectする。
   - 完了条件: C-02、C-03のpure/fake integrationと既存reload behaviorがpassする。
3. Composition-root disabled lifecycleと受け入れを完了する。
   - Notesがfalseならfactory/location/store/surface/timerへ到達しないownerを実装する。
   - Enabled shutdown、disabled→enabled restart、enabled→disabled restartでhandle/data ownershipを検証する。
   - 完了条件: C-01〜C-03、disabled key→PTY AOT baseline差+5%以下、aggregate/full gatesがpassする。

## 設計判断

- Config optionはproduct-owned `dart_terminal` schemaに置く。汎用`dart_appkit`は設定名やNote lifecycleを知らない。
- `internalPreview` optionはfile/CLI/typed resolution/`--show-config`では有効にする。公開前はschema metadataでgenerated
  `--help`、public Markdown、Settings option catalogから除外し、R2ではmetadataだけをpublicへpromote可能にする。
- Pending restartは「直前reloadとの差」ではなく「process startup snapshotとの差」で算出する。値を起動値へ戻したreloadでは
  pendingが消える。Current authorityをreload結果から生成/破棄しない。
- Composition rootはauthority/storeの具体生成をfactory injectionにし、false branchではfactory引数やstore locationさえ評価しない。

## 完了条件

- Implementation planのCM-06成果物、default、C-01〜C-03、privacy/performance条件を満たす。
- 全検証結果、失敗した試行、残る制約を本書へ追記し、ROADMAPの各subtaskを個別commit後にだけ完了する。

## 検証方針

- Focused config/reference/effective/Settings/reload/product configuration/Note composition tests。
- Reference generator freshness、format、analyze、aggregate tests、`make test`。
- Disabled fast pathは同じAOT processでdirect key→PTY baselineと交互測定し、p95または十分な反復の中央値で+5%以内を固定する。
- Source/privacy auditと隣接`dart_appkit`差分audit。

## 2026-09-21: 第1サブタスク着手

- ROADMAPを再確認し、先頭未完了がCM-06親の第1サブタスクになるよう分割した。
- 既存schema optionは全件public扱いで、application policyは`live`/`newSession`だけである。
  Reference/Settings/effective formatterがschemaを直接列挙するため、露出制御はoptionの型付きmetadataとして一元化する。
- `--show-config`はconfigured internal optionの値/provenance/diagnosticを確認する保守経路であり、boolean/fontだけを出すため
  Note本文/ID/path/timeを追加しない。公開filterは適用せず、privacy-safeなtyped effective outputを維持する。

## 2026-09-21: 第1サブタスク完了

### 実装結果

- `TerminalConfigApplicationPolicy.nextLaunch`と`TerminalConfigExposure.public/internalPreview`を追加し、全optionが
  application policyとexposureを型として保持するようにした。Change planもlive/new-session/next-launchを相互排他的に分類する。
- `notes=false`、`notes-on-return=true`、`notes-next-prompt=false`、`notes-font-size=15`をproduct schemaへ追加した。
  Boolean grammarは既存のexact `true|false`を共有し、Note fontはfinite 12〜24 inclusiveだけを受理する。
- `TerminalProductConfiguration`へ4値をimmutable projectionした。Include→root→CLI priority、winning sourceのpath/line/column、
  invalid file valueのdefault recovery、invalid CLIのusage failureは既存resolverをそのまま通る。
- 現stageの4 optionは`internalPreview`である。File/CLI resolverとprivacy-safeな`--show-config`は全59 typed optionsを扱う一方、
  public help/reference、Settings generated catalog、Settings effective inspectorは55 public optionsだけを列挙する。既存root fileに利用者が
  明示したinternal optionはunknown扱いにせず、full-document editorで保持する。
- Diagnosticsへcontent-freeな`next_launch_options`件数を追加し、59 schema optionsをlive 14、new-session 42、next-launch 3へ
  完全分類した。Japanese metadataとprivacy allowlistも同じtyped inventoryへ同期した。
- Source fingerprintを持つPhase 7 AppKit acceptance、Ghostty P0/P1 gap inventory、release-candidate daily-use matrixを再生成した。
  行動/evidence内容は不変で、変更は対象source hashだけである。

### 失敗した試行と修正

- 最初のformat commandへ誤ってMarkdown 2ファイルを含め、Dart parser errorになった。またChange plan initializerの閉じ括弧漏れも
  同時に検出された。Markdownには書き込みは起きず、括弧を修正してDart sourceだけを再formatした。
- Aggregate testはsource変更に応じ、gap inventory、daily-use matrix、Phase 7 acceptanceの順でstaleを正しく検出した。
  Dependency順にPhase 7→gap inventory→daily-use matrixを再生成してfreshnessを回復した。
- その後、全schema optionに日本語descriptionを要求するlocalization testと、diagnostics privacy schema key countが新option/policyを
  検出した。4つのbounded Japanese descriptionと`next_launch_options` allowlist/countを追加し、focused test後にaggregateを再実行した。

### 検証結果

- `dart format`（変更Dart source/test/tool）: format済み。
- `dart analyze`: repository全体 issue 0。
- config、product configuration、configuration reference、Settings document/editor/inspector、effective config、diagnostics、localization、
  diagnostics privacyのfocused tests: pass。
- Configuration reference freshness: pass。Internal preview optionはpublic generated Markdownへ未掲載で、既存public文書差分0。
- `dart test/run_tests.dart`: pass。Note store acceptanceはcommit p95 134,365 us、primitive p95 13,437 us、
  contention/recovery/privacyすべてpass。Phase 9 security stressと全aggregate regressionもpass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。364 filesのformat変更0、全analyze/test/privacy/security/
  compatibility/release gate pass。Note store 20 runsはcommit p95 136,928 us、primitive p95 13,828 us、
  contention/recovery/privacyすべてpass。
- `git diff --check`: pass。隣接`dart_appkit`は着手前からの3ファイル以外に差分0。

### 第2サブタスクへの引き継ぎ

- `TerminalConfigChangePlan.nextLaunchChanges`は分類まで実装済みだが、startup snapshotとの差に基づくpending restart projectionと
  machine/UI表示は未実装である。
- `TerminalProductConfigurationAuthority`はまだaccepted snapshot全体を`newSessionConfiguration`へ置換する。第2サブタスクでは
  current launch Notes flagsを固定し、`notes-font-size`だけをlive Note projectionへ通知する。

## 2026-09-21: 第2サブタスク完了

### 現在地と設計確認

- 着手前にROADMAPを再確認し、先頭未完了がCM-06第2サブタスクであること、C-02/C-03だけを実装してcomposition rootは
  第3サブタスクへ残すことを確認した。
- Pending restartはaccepted candidateとprocess startup snapshotのsemantic差から毎回再計算する。直前candidateとの差だけを蓄積せず、
  startup値へ戻せば空になる方式を採用した。
- Product configurationはaccepted configとcurrent launch runtimeを分離する。`TerminalProductConfiguration.fromSnapshot`へ
  launch-fixed値の注入点を設け、generic AppKitやglobal mutable flagを増やさない。

### 実装結果

- Reload controllerがimmutable `pendingRestartChanges`と`hasPendingRestart`を所有し、applied/unchanged/rejected/busy/disposed/failureの
  固定結果へ現在値を投影するようにした。Machine lineはcurrent changeの`next_launch`件数とstartup差の`pending_restart`件数だけを出す。
- C-02として、`notes`等のreloadはlast-known-good effective snapshotへacceptされる一方、current
  `TerminalProductConfigurationAuthority`のlaunch flagsと新規terminalから参照される同値は起動時のまま維持する。
  Current authority create/disposeやshell token注入は行わない。
- `TerminalNoteFeatureConfiguration`をproduct-owned immutable projectionとして追加し、effective flagsを
  `notes`、`notes && notesOnReturn`、`notes && notesNextPrompt`のexact conjunctionにした。
- C-03として、`notes-font-size` changeだけが専用generation/observerを更新する。Note fontだけのreloadでは既存key binding engineと
  key encoderを再生成せず、terminal input/grid/drawable/winsize/SIGWINCH経路へ接続しない。
- Settings inspectorはpublic option filterを維持したままpending restart件数を表示する。Root fileへ明示されたinternal optionの
  editor detailはopen/new terminalがcurrent値を維持し、app restart後だけsaved値を使うと英日両方で示す。

### 検証結果

- `dart format`（reload/product configuration/Settings/localizationとfocused tests）: format済み。
- `dart analyze`: repository全体 issue 0。
- `terminal_config_reload_test.dart`: C-02 accept、startup差、起動値へ戻したpending clear、immutable projection、invalid mixed
  reloadのall-or-nothingをpass。
- `terminal_product_configuration_test.dart`: launch flags不変、Note font 15→24の一回通知、key binding/encoder identity不変、
  next-launch-only通知0、effective conjunctionをpass。
- Settings editor/inspector/localization focused tests: pending restart表示、internal option非列挙、next-launch detailをpass。
- `dart test/run_tests.dart`: pass。Note store acceptanceはcommit p95 135,698 us、primitive p95 16,024 us、
  contention/recovery/privacyすべてpass。全aggregate regressionもpass。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: pass。364 filesのformat変更0、全analyze/test/privacy/security/
  compatibility/release gate pass。Note store 20 runsはcommit p95 132,633 us、primitive p95 14,118 us、
  contention/recovery/privacyすべてpass。
- Ghostty gap inventoryとrelease-candidate daily-use matrixは変更source hashだけを再生成し、freshness checkをpass。

### 第3サブタスクへの引き継ぎ

- 次はこのlaunch-fixed `TerminalNoteFeatureConfiguration`を唯一のadmission入力にするcomposition rootを追加する。
  `notes=false` branchではfactory/location/store/context/surface/timerを評価せず、font observerも登録しない。
- Enabled rootはCM-05 authorityをinjected factoryで所有し、shutdown/stopを一回だけ完了してから参照を破棄する。
