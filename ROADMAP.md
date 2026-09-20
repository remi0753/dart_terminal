# Dart Terminal — contextual memory 設計ロードマップ

最終更新: 2026-09-20<br>
状態: 設計検討中。製品実装は未承認。

主要な terminal emulator 機能と配布版リリースまでの計画は達成済みであり、
[`docs/archive/terminal-emulator-release-roadmap.md`](docs/archive/terminal-emulator-release-roadmap.md)
へアーカイブした。そこに残る5件の低優先 follow-up は履歴として保持するが、
この roadmap の作業順序には含めない。再開する場合は本書の適切な位置へ明示的に追加する。

新機能の原案は
[`docs/proposals/contextual-terminal-memory-and-input-checkpoints.md`](docs/proposals/contextual-terminal-memory-and-input-checkpoints.md)、
既存実装との照合結果と判断項目は
[`docs/proposals/contextual-terminal-memory-design-decisions.md`](docs/proposals/contextual-terminal-memory-design-decisions.md)
を参照する。Gate 1の製品判断は
[`docs/proposals/contextual-terminal-memory-product-slices.md`](docs/proposals/contextual-terminal-memory-product-slices.md)
を正本とする。原案内の一括 MVP と実装順は superseded されており、以下の判断が完了するまで
採用 slice も実装 backlog とみなさない。

## 作業順序

- [x] 旧 roadmap を履歴と未完了 follow-up を保ったままアーカイブし、新機能の設計論点を洗い出す
  （実施記録は
  [`contextual-terminal-memory-design-decisions.md`](docs/proposals/contextual-terminal-memory-design-decisions.md)
  を参照する）
- [x] 製品 slice と成功条件を決め、memory、prompt連動、exact-command checkpointを個別に採用・延期・不採用へ分類する
  （判断結果は
  [`contextual-terminal-memory-product-slices.md`](docs/proposals/contextual-terminal-memory-product-slices.md)
  を参照する）
- [x] scope、identity、lifecycle と trigger delivery semantics を確定する
  （判断結果は
  [`contextual-terminal-memory-scope-trigger-semantics.md`](docs/proposals/contextual-terminal-memory-scope-trigger-semantics.md)
  を参照する）
- [x] data model、永続化、privacy、security、migration 方針を確定する
  （判断結果は
  [`contextual-terminal-memory-data-persistence-privacy.md`](docs/proposals/contextual-terminal-memory-data-persistence-privacy.md)
  を参照する）
- [ ] overlay、編集体験、input authority、accessibility の仕様を確定する
  （実施時に同文書の Gate 5 を参照する）
- [ ] exact-command shell adapter の feasibility と trust boundary を検証し、checkpoint slice の採否を決める
  （実施時に同文書の Gate 6 を参照する）
- [ ] 採用した slice の仕様、互換性 matrix、検証条件、段階的 rollout を確定する
  （実施時に同文書の Gate 7 を参照する）
- [ ] 採用した slice だけを実装可能な subtask へ分割し、依存順と個別の完了条件を本書へ追加する

最後の項目が完了するまで、提案にある schema、overlay、input mode、shell adapter を
製品コードへ先行実装しない。
