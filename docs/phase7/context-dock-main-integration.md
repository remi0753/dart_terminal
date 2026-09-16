# Context Dock branch integration

- Status: in progress
- Date: 2026-09-16

## 目的、背景、範囲

利用者の依頼に従いcodex/context-file-navigator-roadmapをローカルmainへ統合し、
統合済みのローカル作業ブランチを削除する。機能の追加や履歴の書き換えは行わない。
remoteへのpush／branch削除、隣接dart_appkitへの変更、低優先follow-upは対象外。

## 依存関係、完了条件、検証方針

- mainが作業ブランチのancestorならfast-forward-onlyで統合する。競合／分岐があれば停止して記録する。
- cleanな作業treeと他worktreeのcheckoutを確認し、統合済みbranchだけをgit branch -dで削除する。
- mainに元の実装commit0b3261fが到達可能で、元branch refがなく、最終treeがcleanである。
- この統合記録とROADMAP以外のtreeが検証済み0b3261fと一致し、generated freshnessがpassする。
- 直前taskのmake test／両runtime検証はdocs/phase7/context-dock-background-compositing.mdを参照する。
  source変更のないfast-forwardなのでcode testsの再実行ではなく同一性とfreshnessで検証する。
- 主要リスクは未commit変更の上書き、誤branch削除、未統合commitの喪失。強制削除やresetは使わない。

## 調査記録

- 開始時はclean、current branchはcodex/context-file-navigator-roadmap、HEAD0b3261f。
- local mainは31d6634でorigin/mainを追跡する。左右差分はmain側0／作業branch側28 commitでfast-forward可能。
- worktreeはこのrepository一つだけで、mainを別worktreeがcheckoutしていない。作業branchのupstreamはない。
- README、ROADMAP、FEATURE_MATRIX、AGENTS、ADR-005と直前の検証メモを確認した。
- repository規約に従って統合taskとこのメモを先に登録し、計画commit後にmerge／削除を実施する。
  完了の記録commitはmainに作り、未実施のmerge／削除を先に完了扱いにしない。
