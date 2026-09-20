# CM-03 Durable Note store worker

## 目的

CM-02のstrict codecをapplication-wideな専用isolateから安全に実行し、Note storeのsingle-writer lock、
permission、atomic durable commit、backup、deletion journal、recovery、explicit exportを提供する。UI/application
ownerはfile I/O、encode、flushを実行せず、bounded protocolで一件ずつ依頼できる境界を作る。

## 背景

`ROADMAP.md`の先頭未完了はCM-03で、CM-02はcommit `598bae9`で完了している。Gate 3/7は固定location、
directory 0700、file 0600、regular/no-hard-link、kernel advisory lock、current/backup/journal、same-directory
temp→file fsync→rename→directory fsync、明示recovery/exportを要求する。Dart標準`dart:io`だけではhard-link count、
advisory lock、directory fsyncをrace-freeに保持できない。

## 範囲

- productからpath、leaf name、modeを注入する汎用macOS durable-file capability
- Note store protocol version 1と固定・content-free failure/result/metric
- `load`、`commitCandidate`、`exportToApprovedPath`、`retryRecovery`、`stop`
- current、backup、deletion journalのstrict load、logical deletion、explicit recovery
- application-wide専用isolate、one in-flight、bounded pending admission、timeout/crash/stop
- filesystem全step fault、permission/link、two-process contention、known-good保持、performance fixture

## 対象外

- Note mutation semantics、application authority、pane/restoration reconciliation
- config enablement、product startup composition、native card/editor、user-facing success/failure UI
- AppKit、PTY、shell integration、`dart_appkit`への製品固有実装
- import、automatic empty reset、automatic recovery overwrite、record単位salvage

## 依存関係

- CM-02 `TerminalNoteStoreCodec`、CM-01 immutable snapshot
- Gate 3のstore/delete/export/recovery contract
- Gate 7のstore worker protocol、queue、latency、memory budget
- macOS POSIX `openat`/`fstat`/`flock`/`fsync`/`renameat` primitives

## 完了条件

- fixed safe locationを解決し、directory 0700、全owned file 0600、regular file、link count 1、same ownerを
  read/write前に検証する。
- second processはkernel lock contentionとして拒否し、stale lock pathnameだけでは拒否しない。
- current/backup/journalのどのfault/crash pointでもknown-goodを破壊せず、invalid storeをemptyへ自動resetしない。
- delete成功後はjournalを先にdurable化し、current/backup/recovery preview/exportからNoteを復活させない。
- request/responseはversion 1、authority generation/request sequence bound、一件in-flight、pending 32 intents/
  128 KiB body、load 3秒、stop 1秒を守る。
- status/log/exceptionへbody、Note/context ID、timestamp、color、trigger detail、pathを含めない。
- 1 MiB commit p95 250 ms以下、16 MiB primitive fixture p95 1.5 s以下をisolated local fixtureで20回以上測る。

## 検証方針

- generic native capabilityを実directoryでpermission、symlink、hard-link、lock、fsync、rename、cleanupまで検証する。
- injectable filesystem fakeでread/write/flush/file-fsync/rename/directory-fsync/journal/backupの各stepをfault injectionする。
- isolate protocol property、queue overflow、timeout、crash、late response、stop、restart、transfer boundを検証する。
- helper processでtwo-process contentionを実測し、deletion crash matrix、explicit export cancel/success、orphan tempを検証する。
- format、全package analyze/focused test、`make test`を実行し、結果を本書へ逐次記録する。

## サブタスクと順序

1. **汎用macOS durable-file capability**
   - `dart_terminal` repository内に、absolute directoryとbounded leaf名をcallerが注入する独立packageを作る。
   - directory/file permission、owner/type/link inspection、exclusive advisory lock、bounded read、exclusive temp write、
     file/directory fsync、rename/unlinkを固定failure classで提供する。
   - Note schema、Dart Terminal path、AppKit/PTYをpackageへ入れない。
   - 完了条件: native/Dart contract、fake不要のsecurity-focused unit、source boundary、format/analyzeが通る。
2. **Note transaction/recovery engine**
   - protocol value、safe location resolver、portable export codec、injectable filesystem interface、local engineを実装する。
   - current/backup/journal load、commit、delete、explicit recovery、export、orphan cleanupを一件ずつ処理する。
   - 完了条件: 全filesystem step faultとdeletion crash matrixでknown-good/revival 0、empty auto-reset 0、content-free error。
3. **専用isolate clientとbounded admission**
   - version 1 message codec、worker entrypoint/client lifecycle、一件in-flight、pending 32/128 KiB、3秒load、1秒stop、
     crash/late response/sequence/generation処理を実装する。
   - 完了条件: real isolate round-trip、overflow、timeout、crash、restart、idempotent stopでhandle/pending 0。
4. **実filesystem受け入れと性能gate**
   - two-process contention、permission/symlink/hard-link、current/backup/journal recovery、export cancel/success、
     1/16 MiBをisolated local fixtureで統合検証する。
   - 完了条件: 20回以上のp95 budget、worker log sentinel 0、full repository gate成功後に親CM-03を完了する。

## 調査・判断記録

### 2026-09-20: 着手と分割

- branch `codex/contextual-memory-design`、worktree clean、ROADMAP先頭未完了CM-03を確認した。
- Existing restoration/settings writerはsame-directory temp/flush/renameのprecedentを持つが、Note contractに必要な
  link count、kernel lock、directory fsync、backup/journal recoveryは提供しない。
- root application `bin/`/`lib/`へ直接FFIを置かない既存source boundaryを維持する。汎用POSIX capabilityは
  repository内の独立packageへ隔離し、Note/Dart Terminal固有pathやschemaを持たせない。Product側がsafe location、
  fixed leaf名、bytesを注入する。`dart_appkit`は変更しない。
- 一括実装ではnative security primitive、transaction semantics、isolate lifecycle、実filesystem acceptanceを独立に
  review/rollbackできないため、上記4サブタスクへ分割した。後続を先行せず各サブタスクを検証・記録・commitする。

### 2026-09-20: 汎用capability native build初回

- Package analyzeはissue 0で成功した。Native asset初回buildはDarwin SDKの`renameat`宣言が見えず
  `-Werror=implicit-function-declaration`で停止した。`renameat`を宣言する`stdio.h`を明示includeする修正を行い、
  warningを無効化したり別process commandへ迂回したりせず再buildする。
- 2回目buildは成功したが、実fixtureの`Directory.systemTemp`が返す`/var/...`にmacOS標準の
  `/var -> /private/var` symlinkが含まれ、全path componentを`O_NOFOLLOW`で開くcontractどおり`unsafeType`になった。
  Capability側でsymlinkを暗黙追跡せず、testだけがtrusted system tempを事前にreal pathへ解決し、その配下で攻撃用linkを
  明示作成する形へ修正した。

### 2026-09-20: 汎用macOS durable-file capability完了

- `packages/dart_durable_file_macos`を追加した。Callerがabsolute directory、bounded safe UTF-8 leaf、bounded bytesを
  注入し、packageはアプリ名、保存location、Note schema、recovery policyを持たない。`dart_appkit`は変更していない。
- Native C17 shimはabsolute pathをrootからcomponentごとに`openat(O_DIRECTORY|O_NOFOLLOW)`し、create指定時だけ
  `mkdirat(0700)`とparent fsyncを行う。Final directoryはsame ownerを要求して0700へ狭める。
- Owned fileは`openat(O_NOFOLLOW)`後の同じdescriptorでregular、same owner、link count 1を検証し、read/write前に
  0600へ狭める。Bounded readは前後のdevice/inode/size/link countも照合する。
- `flock(LOCK_EX|LOCK_NB)`をsession lifetime中保持し、別open descriptionのcontentionを`busy`へ分類する。
  Lock pathnameの存在だけでは拒否せず、holder close後は同じfileで再取得できる。
- Exclusive temp writeはO_EXCL、bounded write loop、file fsync、closeを一operationで行う。Rename/unlinkはsource/
  destinationを同じ安全条件で検査し、directory fsyncは明示APIに分離したため上位transactionが順序を所有できる。
- 全native/Dart errorはpath/contentを含まない19種のfixed failure classへ縮約し、public infoもexists/bytes/mode/link count
  だけを返す。Finalizerとidempotent closeを持ち、debug counterでsession leak 0を検証する。
- Makefileの通常`test`へpackage format/analyze/native filesystem testを追加し、root path dependencyとlockfileを更新した。

#### 検証

- `make durable-file-dart-test`: 成功。4 files format変更0、package analyze issue 0、native build成功、
  `DART_DURABLE_FILE_MACOS_PASS permissions=true links=true lock=true fsync=true`。
- 実filesystem test: existing broad directory→0700、file/lock 0600、exclusive write/read/rename/unlink/fsync、broad fileの
  read前permission narrowing、missing/empty区別、symlink/hard-link/directory reject、held/stale lock、leaf/path/payload bound、
  source boundary、session handle回収を通過した。
- `make release-candidate-daily-use-matrix`: 成功。Makefile hashを正規再生成した。
- `dart analyze`: 成功、root issue 0。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。新package gate、355 files format変更0、root analyze issue 0、
  全native/compatibility/security/integration testが`dart_terminal tests passed`で終了した。

このサブタスクではNote transaction、recovery、isolate protocolを実装していない。次のサブタスクでこの汎用APIを
adapterへ注入する。

### 2026-09-20: transaction engine着手時のleaf contract補正

- Explicit exportのuser-selected filenameは日本語等のsafe UTF-8を取り得るため、汎用packageのASCII-only leafは
  store固定leafには十分でもexport contractを満たさないと判明した。Packageを255 UTF-8 bytes以下、`/`、NUL、
  ASCII control、`.`/`..`を拒否するpath-agnostic leafへ一般化し、UTF-8実file round-tripを追加する。
- Directory boundary、O_NOFOLLOW、owner/type/link、permission、sizeの条件は変更しない。製品path/schemaをpackageへ
  追加せず、export destinationのparent/leafは`dart_terminal`側のapproved-path valueから注入する。
- Storeの0700既定をuser-selected export parentへ適用するとDesktop等のmodeを変えるため、directory create modeと
  existing directory permission narrowingの有無もcaller注入に一般化する。Storeは0700+narrow、export parentは
  createなし+narrowなしとし、後者のmode不変を実directoryで検証する。Fileはどちらも0600を維持する。Native関数の
  signature変更を明示するため、汎用capabilityのABI versionは1から2へ更新する。

### 2026-09-20: Note transaction/recovery engine完了

- `TerminalNoteStoreTransactionEngine`を同期worker-side engineとして追加した。専用isolateとadmissionは次のサブタスクに
  残し、この層は一件ずつのload/commit/recovery/export/stop、固定leaf、transaction順序だけを所有する。
- Safe locationはabsoluteかつ`.`/`..`/control/NULなしに限定し、safeな`XDG_STATE_HOME`を優先、利用できない場合だけ
  `HOME/Library/Application Support/Dart Terminal/Notes`へfallbackする。Valueの文字列表現、結果、例外はpath、本文、
  ID、timestamp、color、trigger detailを出さない。
- Loadはowned pending 4種をbest effort cleanupした後、journal/current/backupをstrict codecで読む。Valid currentを優先し、
  currentがない／invalidでbackupがvalidの場合はread-only recovery previewだけを返す。両copyがない場合だけfresh emptyとし、
  invalid、journal-only、newer versionをemptyや旧backupへ自動fallbackしない。
- 通常commitはexclusive pending write+file fsync、current→backup+directory fsync、pending→current+directory fsyncとした。
  Injectable fakeでwrite、file fsync、inspect、rename、directory fsyncの成功trace 8地点すべてに一回ずつfaultを入れ、再起動後は
  old/newいずれかのcanonical complete documentだけがloadまたはrecovery previewになることを確認した。
- Deleteはpreviousから消えたNote ID集合とcaller tombstone集合の完全一致を先に要求し、journalを最初にdurable化する。
  Candidate current、deletion-safe backupを順にcommitし、両copyのrevisionと対象ID不在を再読検証してからだけjournalをcompactする。
  Success trace 24地点すべてのfault後に再起動し、journalのdirectory syncが一度でも開始されたcaseでresurrection 0を確認した。
- Recoveryはbackup previewに対する明示retryだけがcurrent/backupを書き直す。Journalが残る場合は両copyを再検証してからcompactする。
  Corrupt current+valid backupのload中write 0、両copy corruptのempty reset 0、newer currentから旧backup fallback 0を確認した。
- Portable export v1はsave-panel承認済みabsolute parent/UTF-8 leafを注入し、cancel時I/O 0とする。出力は
  `body/color/status/order/trigger intent`だけで、identity、context、timestamp、revision、restoration/runtime/deliveryを含めない。
  User-owned parentはcreate/chmodせず、same-directory pendingからrenameし、失敗時はdestinationを保持してpendingをcleanupする。
- `dart_appkit`は変更していない。Generic packageのlib/native source auditはDart Terminal、Note、AppKit、PTY依存0であり、
  製品path、fixed leaf、codec、transaction policyはroot側のadapterへだけ置いた。

#### 検証

- `dart test/terminal_note_store_worker_test.dart`: 成功。Location/lock、empty/ordinary/recovery/upgrade、全step fault、
  deletion crash matrix、explicit export cancel/success/rename failure、privacy/source boundaryを通過した。
- `make durable-file-dart-test`: 成功。4 files format変更0、package analyze issue 0、native build成功、
  safe UTF-8 leaf、caller-owned directory mode不変を含め
  `DART_DURABLE_FILE_MACOS_PASS permissions=true links=true lock=true fsync=true`。
- Native function ABIを2へ更新した直後の初回実filesystem testは、file-info struct versionまで同じ定数で2へ変わり、Dartが送る
  struct version 1を`invalidArgument`にした。Function ABIと既存`ddf_file_info_v1` schema versionを別定数へ分け、後者を1に固定して
  再実行した。Signature changeはABI 2、file-info wire layoutはversion 1として独立に検証する。
- `make release-candidate-daily-use-matrix`: 成功。Root runner変更後のhashを正規再生成した。
- `CI=true DART_SUPPRESS_ANALYTICS=true dart analyze`: 成功、root issue 0。`CI=true`なしではsandbox外の
  `~/.dart-tool/dart-flutter-telemetry-session.json` timestamp更新だけがpermission errorになったため、解析結果と分離して再実行した。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`: 成功。357 files format変更0、全package/root analyze issue 0、
  native/security/compatibility/integrationを含むaggregateが`dart_terminal tests passed`で終了した。
- 最終format確認の一回でDart sourceとMarkdownを同じ`dart format`引数へ誤って渡し、Markdown parse errorで終了した。
  Dart 2 filesは変更0で、Markdownは変更されていない。対象をDart sourceへ限定してfocused test、root analyze、aggregateを
  再実行し、上記の最終結果を得た。

このサブタスクではisolate、queue、timeout、cross-isolate protocolを実装していない。次のサブタスクで本engineを専用isolateへ
閉じ込め、application側へbounded clientだけを公開する。
