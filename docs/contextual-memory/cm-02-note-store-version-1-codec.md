# CM-02 Note store version 1 codec

## 目的

CM-01のimmutable Note snapshotを、strictで決定的なversion 1 UTF-8 JSONへ変換するPure Dart codecを
実装する。後続のstore workerがfile I/Oだけを所有し、schema、checksum、quota、migration判断をcodecへ
委譲できる境界を作る。

## 背景

Gate 3/7で、`dart-terminal-notes` version 1 envelope、canonical payload SHA-256、16 MiB file cap、
restoration binding v1、deletion journal、strict unknown/newer rejectionが凍結済みである。`ROADMAP.md`の
先頭未完了はCM-02で、CM-01はcommit `8ffb003`で完了している。

## 範囲

- canonical UTF-8 JSON store envelope/payload encode/decode
- duplicate keyを上書きしないbounded strict JSON parser
- fixed field order、deterministic array order、canonical integer/string、trailing LF exactly one
- payload SHA-256検証
- `restorationBinding` format 1と最大64件のordered context ID
- content-free deletion tombstone journal version 1と最大8,192件
- current/no-opと将来version stepを分離したpure migration entrypoint
- codec schema、record invariant、file/body/counter limitのfail-closed validation

## 対象外

- file open、permission、symlink/hard-link、lock、backup、rename/fsync、worker isolate
- restoration JSON自体のencode/decodeやpane reconciliation
- product startup、application authority、native UI、AppKit、PTY、shell event
- import/export、migration stepのない架空のlegacy schema、unknown fieldのdrop

## 依存関係

- CM-01 `lib/src/terminal_note_model.dart`
- `docs/proposals/contextual-terminal-memory-data-persistence-privacy.md`
- `docs/proposals/contextual-terminal-memory-architecture-verification-rollout.md`
- 既存Pure Dart `lib/src/terminal_sha256.dart`

## 完了条件

- Storeとjournalが同一入力からbyte-identical canonical出力を生成する
- strict decoderがduplicate/unknown/out-of-order/noncanonical/trailing/invalid UTF-8/checksum/invariantを拒否する
- file 16 MiB、body 8 MiB、全record/counter、binding 64、journal 8,192の境界を守る
- newer versionを`upgradeRequired`としてdecode/migrateせず、sourceを書き換えるAPIを持たない
- waiting S3 triggerのruntime bindingを保存せず、load時に`suspended(sessionEnded)`へ変換する
- codec exception/stringへbody、ID、timestamp、color、trigger detailを含めない

## 検証方針

- canonical round-tripとbyte determinism、全field/array orderingをexact testで固定する
- limit `-1 / exact / +1`、checksum、counter、binding、journal faultをfocused testへ入れる
- fixed-seed 10,000 model mutationで各accepted snapshotをencode/decode/re-encodeする
- 任意byteを合計1 MiB以上decodeし、例外分類がfixedかつprocess crash/secret echo 0であることを確認する
- format、analyze、focused test、`make test`を実行し、結果を本記録へ追記する

## 調査・判断記録

### 2026-09-20: 着手

- branch `codex/contextual-memory-design`、worktree clean、先頭未完了CM-02を確認した。
- SHA-256は既存のnative/process非依存`terminalSha256`を再利用し、新しいpackage dependencyを追加しない。
- Dart標準`jsonDecode`はduplicate keyを上書きするため、codec入口には使わない。最大16 MiB、depth、node数を
  先にboundするsmall JSON parserでduplicateを検出し、parse treeのcanonical再encode一致も要求する。
- Store array orderはcontexts/notes/triggersをpersistent ID昇順、deliveriesをsequence→Note ID順に固定する。
  Restoration pane IDsはpane traversalの意味を持つため入力順を保持する。
- Deletion journalは`dart-terminal-note-deletions` version 1 envelopeとし、payloadに
  `(noteId, deletionRevision)` tombstoneをrevision→Note ID順で保持する。Storeと同じpayload checksum、strict
  JSON、one trailing LFを使い、CM-03 crash recoveryがcurrent/backup revisionと比較できるようにする。
- Migration入口はversion 1→1のvalidated no-opだけをinitial実装とし、older/unknown/newerを変換しない。
  将来stepはstrict decode済みのdocument間pure transformとして追加し、unknown field dropを許さない。

### 2026-09-20: focused test初回

- formatとcodec/testの静的解析は成功した。
- focused test初回はdeletion revision 0のreject自体は成功したが、数値型は正しく範囲だけが不正なcounterを
  `schemaViolation`へ分類していたため期待と不一致になった。counterの0未満／正数必須違反／unsigned 64-bit超過を
  一貫して`limitExceeded`へ変更した。値やIDを例外へ含めない方針は維持する。

### 2026-09-20: 実装結果

- `lib/src/terminal_note_store_codec.dart`へfilesystem非依存のcodecを追加した。storeとdeletion journalは
  ordered objectを直接canonical encodeし、payloadだけのSHA-256、exact one trailing LF、16 MiBの入力／出力上限を
  共通適用する。
- bounded strict parserはUTF-8 decode前にfile sizeとbyte範囲を検査し、JSON parse中にduplicate key、depth、node数を
  boundする。parse後のcanonical再encode一致とschemaごとのfield順・全field一致を要求するため、whitespace、別escape、
  trailing data、unknown/out-of-order fieldをfail closedにする。
- 全recordをCM-01 modelへ再構築してcross-record invariantとquotaを再検証する。本文はeditor admission時と異なり、
  CR/CRLFをload時に黙ってLFへ変換せず、保存値が既にnormalizedでなければ`nonCanonical`としてrejectする。
- waiting中のS3 triggerはruntime bindingを永続化せず、load時に`suspended(sessionEnded)`へ変換する。Due S3とS2、
  delivery FIFOは保持する。
- Restoration bindingはlowercase SHA-256、ordered unique known standard context最大64件だけを受理する。
  Quick Terminal、unknown context、duplicate、65件をrejectする。
- Deletion journalは本文を持たない`(noteId, deletionRevision)`だけをrevision→Note ID順でcanonical化し、最大8,192件、
  unique ID、positive unsigned 64-bit revisionを検証する。
- Migration APIは現versionのstrict decode/no-opだけを提供し、older step未登録、future target、newer sourceを変換・
  downgradeしない。
- 実装とtestはいずれも`dart_terminal`内だけで、`dart_appkit`、PTY、AppKit、file I/Oをcodecへ持ち込んでいない。

### 境界条件の扱い

- Aggregate body 8 MiBは`2,048 Notes × 4,096 bytes`と等しいため、他の上限を越えずにaggregateだけを`+1`へする
  schema上の入力は存在しない。exact 8 MiBを2,048件の実snapshotでencode/decodeし、`+1`側は4,097-byte bodyと
  2,049-note arrayの両入口を個別にrejectして、silent truncationやevictionがないことを確認した。
- Canonical file 16 MiBもrecord/body上限を満たすversion 1 documentでは到達しない。`16 MiB - 1`とexact 16 MiBの
  arbitrary inputがsize gateを通ってbounded parserでrejectされ、`16 MiB + 1`だけがparse前に`fileTooLarge`となる
  ことを固定した。
- focused testのcounter fault fixtureは当初、一般JSON decoderでunsigned 64-bit最大値を読み直して精度を失った。
  検査対象外の値まで変質させないよう、canonical payload tokenを直接置換してchecksumを再計算するfixtureへ修正した。

## 検証結果

2026-09-20に次を実行した。

- `dart format lib/src/terminal_note_store_codec.dart test/terminal_note_store_codec_test.dart test/run_tests.dart`
  - 成功、最終再実行は変更0。
- `dart analyze lib/src/terminal_note_store_codec.dart test/terminal_note_store_codec_test.dart`
  - 成功、issue 0。
- `dart run test/terminal_note_store_codec_test.dart`
  - 成功。canonical/store/journal round-trip、duplicate/unknown/noncanonical/trailing/UTF-8/checksum/version fault、
    restoration 64/65、journal 8,192/8,193、record/counter境界、2,048件/8 MiB fixture、16 MiB input boundary、
    fixed-seed 10,000 mutation、arbitrary byte合計1 MiB、privacy/dependency sentinelを通過した。
- `make release-candidate-daily-use-matrix`
  - 成功。統合runner変更に伴う`test/run_tests.dart` hashを正規生成した。
- `dart analyze`
  - 成功、repository issue 0。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`
  - 成功。355 files format変更0、全体analyze issue 0、native capability/compatibility/generated evidence/
    security stressを含む全testが`dart_terminal tests passed`で終了した。

未検証事項はない。file open、permission、lock、atomic replace、backup/recovery、worker isolateは計画どおりCM-03の範囲である。
