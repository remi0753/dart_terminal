# Developer ID evidence transition

## 目的

実Developer ID署名、公証、staple、Gatekeeperのlocal正受け入れ完了後、distributionの
external follow-up証跡を旧Apple-service acceptanceから、実際に残るclean-machine
no-rebuild handoffへ更新する。

## 背景

2026-09-19の実`release-distribution-verify`はDeveloper ID署名、公証Accepted／issue 0、
staple／validate、Gatekeeper、最終9-image監査まで成功した。一方、Ghostty P0/P1 gap inventoryと
release-candidate matrixは、Phase 11当初のcredential未準備状態を表す
`apple-service-acceptance`を引き続きexternal follow-upとしていた。

## 範囲

- DIST-02のgap ID、説明、aggregate allowlistをclean-machine no-rebuildへ更新する。
- external follow-up件数とDIST-02の`accepted-external-follow-up`分類は維持する。
- compatibility coverage、gap inventory、daily-use matrixを依存順に再生成する。
- README、Feature Matrix、Developer ID task memo、ROADMAPと生成証跡を同じ現在地へ揃える。

## 対象外

- clean machine上での実起動、インストール、update適用。
- Intel-native handoffや実時間soakのfollow-up変更。
- 実配布成果物、credential、Apple ticketのrepository追加。

## 依存関係

- 実公証まで成功した`release-distribution-verify`証跡。
- `tool/ghostty_p0_p1_gap_inventory.dart`のDIST-02 gap owner。
- `tool/release_candidate_daily_use.dart`のexternal follow-up allowlist。

## 完了条件

- checked-in生成証跡に`apple-service-acceptance`が残らない。
- DIST-02はclean-machine no-rebuildだけをapproved external follow-upとして示す。
- gap件数、release blocker数、他の分類は変わらない。
- 全generator checkと`make test`が成功する。

## 検証方針

- generator sourceとself-test expectationを同時に更新する。
- compatibility coverage、gap inventory、daily-use matrixを依存順に再生成する。
- `rg`で旧gap IDの残存を確認し、全repository gateを実行する。

## 判明事項・判断記録

- DIST-02はまだclean-machine受け入れが残るため、完全な`accepted`へは変更しない。
- external follow-up総数3（duration、Intel-native、distribution clean-machine）は維持する。
- local Apple-service正受け入れはdocsとmanifestで記録し、生成inventoryには未完了の外部境界だけを置く。

## 検証記録

- 2026-09-19: DIST-02のgap IDを`clean-machine-distribution-acceptance`へ変更し、理由を
  local署名／公証／staple／Gatekeeper成功とno-rebuild clean-machine残件へ更新した。
- release-candidate aggregateのknown limitation allowlistも同じIDへ更新した。旧IDは本メモの
  移行履歴以外のtool／checked-in生成証跡には残っていない。
- compatibility coverage、Ghostty P0/P1 gap inventory、release-candidate daily-use matrixを
  依存順に再生成した。分類はaccepted 97、documented difference 2、external follow-up 3、
  actionable 0、release blocker 0のままである。
- `CI=true DART_SUPPRESS_ANALYTICS=true make test`はformat、analyze、全生成証跡check、
  package／native／security／update／distribution policy／Dart統合testを含めて成功した。
