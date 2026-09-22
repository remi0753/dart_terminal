# R1 internal Notes preview runbook

日付: 2026-09-22<br>
対象: Dart Terminal開発者／internal testerのみ<br>
公開状態: internal-only。一般利用者向けconfiguration reference、Settings、release noteへ転載しない。

## 安全境界

- R1はS1 Basic memoryとS2 On Returnだけを有効にする。S3 At Next Promptは必ずoffにする。
- Note本文はlocal storeへ平文で保存される。同期、暗号化、telemetry、background uploadはない。
- Store操作、raw backup、portable export、復旧を行う前に、Dart Terminalの全windowを閉じてprocessが終了したことを確認する。
- 診断結果へ本文、Note／context identity、path、時刻を貼らない。管理toolの固定machine lineだけを共有する。
- Storeを手動編集、削除、version downgrade、自動resetしない。未知のnewer storeは対応binaryへ戻す。

## Candidateを構築して起動する

まず通常bundleとtyped internal profileを検査する。

```shell
make RUNTIME_ARCH=arm64 contextual-memory-r1-internal-candidate-build
make contextual-memory-r1-rehearsal
```

Developer JITまたはRelease AOTを、次のexact profileで起動する。引数の順序と値を変更しない。

```shell
make RUNTIME_ARCH=arm64 \
  RUNTIME_ARGUMENTS='--notes=true --notes-on-return=true --notes-next-prompt=false' \
  developer-jit-run

make RUNTIME_ARCH=arm64 \
  RUNTIME_ARGUMENTS='--notes=true --notes-on-return=true --notes-next-prompt=false' \
  release-aot-run
```

このprofileは通常のtyped resolverへ最高優先度のCLI値を渡す。同じbundleのdefaultはoffであり、別schema、環境変数feature flag、
compile-time variantは使用しない。

## Store locationを特定する

Store directoryは次の優先順位で一意に決まる。

1. `XDG_STATE_HOME`が安全なabsolute pathなら
   `$XDG_STATE_HOME/dart-terminal/notes`
2. それ以外は
   `$HOME/Library/Application Support/Dart Terminal/Notes`

以下の例にある `/absolute/path/to/Notes` は、上記で特定したdirectoryへ置き換える。推測したpathや相対pathを使わない。

## Payload-preserving statusとlock

アプリを完全終了してから実行する。

```shell
dart run tool/terminal_note_internal_store_admin.dart \
  --store='/absolute/path/to/Notes' \
  --status
```

- `source_state=loaded`／`empty`: 通常状態。
- `source_state=recovery-preview`: current copyは不正だがbackupは読める。Durable payloadは変更されていない。
- `source_state=recovery-required`: current／backupの双方を自動復旧できない。raw fileを保全し、操作を止める。
- `source_state=upgrade-required`: newer format。書き戻し、古いbackupへのfallback、downgradeをせず、対応binaryへ戻す。
- `source_state=locked`: 別processがstoreを所有している。強制上書きせず、Dart Terminalを完全終了して再確認する。

Statusもengineのexclusive lockを一時的に取得し、crashで残ったengine-owned pending fileをcleanupし得る。`store.json`、
`store.backup.json`、`deletions.json`のdurable payloadは変更しないが、directoryを完全にbyte-for-byte read-onlyで開く操作ではない。

## Raw fileを先に保全する

復旧操作の前に、Notes directory全体を別のabsolute directoryへcopyする。アプリと管理toolが動いていない状態で実行し、
`store.json`、`store.backup.json`、存在する場合は`deletions.json`を一緒に保存する。Copy先を元directory内に置かない。

```shell
cp -pR '/absolute/path/to/Notes' '/absolute/path/to/offline-backup/Notes'
```

Copy完了を確認するまでrestore、削除、再起動を行わない。権限や容量の問題でcopyできない場合はその時点で停止する。

## Consented portable export

Portable exportは本文を含む。保存先directoryを先に作成し、内容がsensitiveであることを理解したinternal testerだけが
acknowledgementを付ける。Exportはreadyまたはrecovery-previewから行え、store自体は変更しない。

```shell
dart run tool/terminal_note_internal_store_admin.dart \
  --store='/absolute/path/to/Notes' \
  --export='/absolute/path/to/export/dart-terminal-notes.json' \
  --acknowledge-sensitive-export
```

Export fileにはportableな`body`、`color`、`status`、`order`、`trigger`だけが含まれる。内部ID、timestamp、revision、
restoration bindingは含まれない。Import機能はない。Export fileをissue、chat、telemetryへ添付しない。

## Backupから明示的に復旧する

`source_state=recovery-preview`の場合だけ使用する。先にraw backupを取得し、backup copyへ戻ることでcurrentの新しい変更が失われ得ることを
理解したうえでacknowledgementを付ける。

```shell
dart run tool/terminal_note_internal_store_admin.dart \
  --store='/absolute/path/to/Notes' \
  --restore-backup \
  --acknowledge-data-change
```

成功後に`--status`を再実行し、`source_state=loaded`を確認してからcandidateを起動する。`recovery-required`、
`upgrade-required`、`locked`ではrestoreを試さない。

## Soft kill switchと再有効化

異常があれば、全windowを閉じてprocessを終了し、次回launchのmaster flagをoffにする。Off launchはstore read、write、lock、delete、
native Notes surface、context bindingを開始しない。Store directoryは削除しない。

```shell
make RUNTIME_ARCH=arm64 \
  RUNTIME_ARGUMENTS='--notes=false --notes-on-return=true --notes-next-prompt=false' \
  developer-jit-run
```

再有効化は、アプリを再度完全終了した後、candidateのexact three-argument profileで新しく起動する。Live reloadでmaster flagを切り替えない。

## Pre-Notes binary rollbackとre-upgrade

1. R1 candidateを終了し、Store directoryのraw backupを取得する。
2. 既存release tag `0.1.0`など、通常GUIがrestoration v1を更新しない旧binaryへ戻す前に、
   R1 candidateと同じ`XDG_STATE_HOME`／`HOME`で次を実行し、`trust_invalidated=true`を確認する。

   ```shell
   dart run tool/terminal_restoration_rollback_guard.dart \
     --prepare-pre-notes-rollback \
     --acknowledge-app-closed-and-store-backed-up
   ```

3. Pre-Notes binaryを通常どおり起動する。Note storeは削除、移動、編集しない。
4. 必要なterminal作業を行い、pre-Notes binaryを通常終了する。
5. R1 candidateをexact profileで再起動する。

`0.1.0`は通常GUIでrestoration v1を読み書きしないため、layoutを変更しても旧snapshotのhashは変わらない。
Guardはrestoration v1 fileとNote storeを保持し、exact復元の信頼印だけを無効化する。したがってこの旧binaryからの再upgradeでは、
layoutが同じに見えてもNoteを自動reattachせずDetachedに置く。内容を確認して明示的にreattachする。Guardを通さずに旧binaryを
起動した場合は安全なexact判定を保証できないため、R1 candidateを起動する前にguardを実行する。旧binary自体が通常GUIで
restoration v1を維持することを確認できる版では、restoration bytesとbindingのexact matchだけreattachを許す。
Re-upgradeだけを理由にstoreをdowngrade、reset、または古いbackupへ戻さない。

Guardが作るuntrusted sentinelはNotes off／native unavailableの起動後も残る。Terminalのv1 topologyは次の正常終了から
引き続き保存・復元できるが、古いNote bindingは自動reattachされない。Notesを再有効化して正常なrestoration-first／
Note-second commitが完了した後だけ、新しいexact bindingへ信頼を戻す。途中で異常終了した場合はDetachedを維持する。

## 停止条件

次の場合はpreviewを停止し、soft kill switchを適用し、raw backupとcontent-free machine lineだけを保全する。

- `recovery-required`または`upgrade-required`
- Restore後も`loaded`にならない
- Wrong-context attachment、Note消失、重複delivery、PTYへの意図しないbyte、terminal geometry変化
- App終了後もlockが残る、または所有resourceが回収されない
- 本文、identity、path、timestampがdiagnostic／evidenceへ現れる

R1では自動resetやpublic workaroundを追加しない。原因修正と再qualificationが完了するまでR2へ進めない。
