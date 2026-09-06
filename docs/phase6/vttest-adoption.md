# Phase 6 — vttest adoption decisions

## Task identity

- Date started: 2026-09-07
- Scope: third Phase 6 compatibility-hardening roadmap item
- Status: complete

## Purpose and background

Use a pinned upstream `vttest` release as a coverage reference, then state which
test areas Dart Terminal adopts, replaces with stronger automated evidence,
defers to an ordered roadmap owner, or intentionally does not adopt. The result
must make omissions visible without treating an interactive visual test as a
normative terminal specification or as proof that an unobserved feature works.

## Scope

- Pin the exact upstream source artifact and identify its test-menu surface.
- Map each relevant vttest area to the versioned sequence/mode inventory and
  existing parser, terminal-core, differential, or product evidence.
- Give every area one explicit disposition, rationale, current evidence, and
  follow-up owner where work remains.
- Define how future vttest runs can be recorded without weakening deterministic
  byte-level gates.

## Out of scope

- Implementing terminal behavior owned by later ordered Phase 6 tasks.
- Claiming interactive visual confirmation when no run was performed.
- Treating legacy printer, 8-bit host environment, or hardware-terminal tests
  as product requirements solely because vttest exposes them.
- Running duration-only soak tests; the ROADMAP classifies those as lower
  priority and nonblocking.

## Dependencies and initial facts

- The sequence/mode inventory contains 260 externally traceable records and
  explicitly classifies supported, partial, safe-ignore, and unsupported paths.
- The completed differential harness supplies byte-observable reply evidence
  and an owned DECRQSS SGR gap, but deliberately does not claim screen/style/
  mode observations.
- Product parser cases already replay shell, less, top, and vim recordings over
  whole-input, every split, and bytewise delivery plans.
- The exact vttest upstream release, source hash, menu taxonomy, and license
  still need to be verified from primary sources.

## Completion conditions

- A pinned, hash-addressed upstream source and reproducible inspection method
  are documented.
- Every in-scope top-level and nested vttest test family has exactly one
  disposition with a reason and evidence or future owner.
- Deferred areas remain in ROADMAP order; no later feature is implemented here.
- ROADMAP and FEATURE_MATRIX are synchronized, documentation checks pass, and
  the full repository gate passes before commit.

## Verification plan

- Compare the documented taxonomy against the pinned upstream menu definitions
  and reject missing or duplicate dispositions by review or a bounded checker.
- Cross-check cited inventory IDs and repository evidence paths.
- Run formatting/static analysis and `CI=true make test`; record all results and
  any unavailable interactive execution explicitly.

## Investigation log

- 2026-09-07: after commit `05c3477`, ROADMAP was reread with a clean worktree.
  This item is the first unchecked task. README, FEATURE_MATRIX, the completed
  inventory and differential records, and the Phase 6 exit conditions were
  reviewed before changes.
- 2026-09-07: the upstream archive dated 2025-12-05 was downloaded from the
  maintainer's archive, hashed, configured, and built on the M1/arm64 baseline.
  `./vttest -V` reported `VT100 test program, version 2.7 (20251205)`. The
  top-level and VT220/320/420/520/xterm menu tables were inspected from source;
  this avoids deriving the taxonomy from a package maintainer's older binary.

## Pinned non-normative reference

`vttest` is a test/demonstration program, not a protocol specification. The
normative interpretation remains the pinned ECMA-48, DEC, xterm, and iTerm2
sources in [`specification-source-pins.md`](specification-source-pins.md).

| Property | Pin |
| --- | --- |
| Upstream | [VTTEST project](https://invisible-island.net/vttest/) |
| Archive | [`vttest-20251205.tgz`](https://invisible-island.net/archives/vttest/vttest-20251205.tgz) |
| Bytes | 243,249 |
| SHA-256 | `cd6886f9aefe6a3f6c566fa61271a55710901a71849c630bf5376aa984bf77cc` |
| Reported version | `2.7 (20251205)` |
| Menu authorities | `main.c`, `nonvt100.c`, `vt220.c`, `vt320.c`, `vt420.c`, `vt520.c`, `xterm.c` |
| License inspected | upstream `COPYING`, SHA-256 `cc6c4b5fc68b6c26c954596e962687f51ded5860a86c88b392d924358afaebc3` |

The [upstream manual](https://invisible-island.net/vttest/manpage/vttest.html)
describes a menu-driven display and keyboard test. Its `-c` option can replay
recorded menu commands, but keyboard and mouse input can still be required.
Therefore a successful vttest session is supplemental visual evidence, never a
replacement for byte-exact parser/snapshot/reply assertions.

Reproduction used an unpacked temporary directory and these steps:

```sh
shasum -a 256 vttest-20251205.tgz
tar -xzf vttest-20251205.tgz
cd vttest-20251205
./configure
make
./vttest -V
```

No vttest source or binary is shipped with Dart Terminal.

## Disposition vocabulary

- `AUTO`: adopt the intent as a deterministic normal-gate check. Existing Dart
  evidence is authoritative; vttest may still be used for human diagnosis.
- `MANUAL`: adopt as a later interactive supplement after its named ROADMAP
  owner is reached. A screenshot/log cannot by itself close that owner.
- `CONDITIONAL`: do not adopt into the current plan. The real-app or terminfo
  tasks may promote it only with concrete application evidence, at which point
  a new ordered ROADMAP item and byte regression are required.
- `EXCLUDE`: intentionally do not adopt as a Dart Terminal product requirement.
  Any received sequence must still follow the inventory's bounded ignore or
  explicit reject disposition.

These decisions are about test adoption, not a claim that every sequence in a
menu is implemented. Current support remains defined record-by-record by
`compatibility/sequence_mode_inventory.json`.

## Reviewed adoption matrix

The 34 units below cover every top-level menu and each distinct nested feature
family exposed by the pinned VT220/320/420/520 and xterm branches. Inherited
menus are listed once rather than repeated at every terminal level.

| ID | Pinned vttest family | Decision | Evidence, rationale, and owner |
| --- | --- | --- | --- |
| VT-01 | VT100 cursor movements | `AUTO` | CUP/HVP/CUU/CUD/CUF/CUB, CR/LF/BS, margins, origin, tabs, and cursor clamp are covered by `terminal_screen_test.dart`, `terminal_core_test.dart`, and parser corpus snapshots. |
| VT-02 | VT100 screen features | `AUTO` | Erase, scrolling, autowrap, insert/origin/reverse-video modes, SGR, save/restore, and tab stops have terminal-core and snapshot assertions, including all-split replay. |
| VT-03 | ASCII and DEC Special Graphics character display | `MANUAL` | ASCII/Unicode shaping is automated. DEC Special Graphics designation is currently explicit unsupported; the real-app and terminfo tasks decide whether ncurses evidence promotes it, then the final regression task owns bytes and snapshots. |
| VT-04 | ISO-2022 NRCS, locking/single shifts, and UPSS | `CONDITIONAL` | The UTF-8 macOS product does not claim hardware-terminal national replacement sets. Promote only if a P0 real app or chosen terminfo entry emits them. |
| VT-05 | VT100 double-width/double-height lines | `EXCLUDE` | DECDWL/DECDHL are legacy presentation features outside the daily-driver and Unicode grid contract. They remain explicit unsupported. |
| VT-06 | Printable/control/cursor/function/keypad keyboard | `AUTO` | Phase 5 US/JIS/IME input matrix plus `terminal_key_encoder_test.dart` is stronger than interactive key recognition and includes DECCKM/DECPAM and F1–F20. |
| VT-07 | Answerback, terminal autorepeat control, and keyboard LEDs | `EXCLUDE` | ENQ answerback, DECARM host control, and DECLL hardware LED semantics are not macOS input requirements. AppKit owns key repeat. |
| VT-08 | DA, DSR, and mode/status reports | `MANUAL` | Current DA/DA2, DSR/CPR, DECRQM, palette, and default-color replies are byte-tested. The later query-report task owns expansion and a supplemental vttest report pass. |
| VT-09 | VT52 mode | `EXCLUDE` | The product is an ANSI/UTF-8 xterm-class terminal; DECANM/VT52 emulation is explicit unsupported. |
| VT-10 | VT102 insert/delete character and line | `AUTO` | ICH/DCH/IL/DL are covered by core tests, product corpus, and reviewed differential reply cases. |
| VT-11 | Known-bug patterns and parser recovery | `AUTO` | Wrap-pending, origin/margin transitions, controls inside sequences, leading zeros, CAN/SUB/ESC recovery, malformed limits, and chunk invariance are automated. |
| VT-12 | RIS hard reset | `AUTO` | RIS reset of primary/alternate screens, modes, keyboard, mouse, palette/hyperlink state, and resources is asserted across focused tests. |
| VT-13 | DECSTR soft reset | `MANUAL` | DECSTR is currently explicit unsupported. The final compatibility-regression task owns a byte-level decision after the real-app/terminfo matrix establishes required reset semantics. |
| VT-14 | DECTST terminal hardware self-test | `EXCLUDE` | A software emulator must not pretend to test VT hardware. Runtime fault/recovery gates replace this intent. |
| VT-15 | ECMA-48 cursor movement extensions | `AUTO` | CBT/CHA/CHT/CNL/CPL/HPA/VPA and supported relatives are inventoried and tested; unsupported HPR/VPR remain explicit rather than inferred from a picture. |
| VT-16 | ISO-6429 color and graphic rendition | `AUTO` | SGR attributes, ANSI/256/direct colors, default colors, palette mutation, style tables, renderer goldens, and product display integration are automated. |
| VT-17 | Other ECMA-48 scrolling, repeat, and protected-area operations | `CONDITIONAL` | SU is supported; REP, SD/SL/SR, SPA/EPA and protected erase are not planned without real-application evidence. |
| VT-18 | S7C1T/S8C1T 7-bit/8-bit output selection | `EXCLUDE` | The parser accepts bounded C1 input forms, but the UTF-8 product emits stable 7-bit replies and will not expose a host-switchable reply encoding. |
| VT-19 | Media-copy/printer control | `EXCLUDE` | MC, DEC printer extent/form-feed, controller, and printer-status behavior are physical-terminal functions and can create unsafe host-side effects. |
| VT-20 | DECDLD soft fonts and Sixel display | `EXCLUDE` | DRCS and Sixel are outside the current graphics contract; bounded DCS safe-ignore remains required. The existing feature-matrix Sixel hold is unchanged. |
| VT-21 | DECUDK user-defined keys | `EXCLUDE` | Host-defined key programming conflicts with the product's explicit keybinding/input ownership and stays bounded safe-ignore. |
| VT-22 | VT320 page memories, page movement, and status line | `EXCLUDE` | The product owns one primary/alternate grid plus scrollback, not DEC hardware page memories or a host-programmed status display. |
| VT-23 | VT320 serialized presentation/terminal state and UPSS | `EXCLUDE` | DECRQPSR/DECRSPS/DECRQTSR and preferred supplemental sets expose hardware state outside the product contract; DCS inputs remain bounded. |
| VT-24 | VT420 cursor/margin/editing extensions | `MANUAL` | Left/right margins and common editing are implemented. A later real-app run may use these screens to diagnose DECBI/DECFI/DECIC/DECDC gaps before byte regressions are added. |
| VT-25 | VT420 rectangular operations and screen checksums | `CONDITIONAL` | DECCRA/DECERA/DECFRA/attribute rectangles and DECRQCRA are sizable optional surfaces. Promote only for concrete P0 application evidence. |
| VT-26 | VT420 keyboard-local functions and macros | `EXCLUDE` | DECELF/DECLFKC/DECSMKR/DECDMAC describe terminal-local hardware or programmable macro behavior, not the AppKit input contract. |
| VT-27 | VT510/VT520 DECRQSS, DSR, and screen-mode additions | `MANUAL` | The query-report owner must close or retain the seven-byte DECRQSS SGR gap. DECNCSM/DECATC and advanced reports remain evidence-driven. |
| VT-28 | xterm version, mode, and status-string reports | `MANUAL` | Use after the query-report owner defines exact policy. The black-box harness already prevents product-specific DECRQSS serialization from being normalized away. |
| VT-29 | xterm alternate-screen modes 47/1047/1049 | `AUTO` | Primary/alternate ownership, clear/save/restore semantics, resize, selection isolation, and product rendering are automated. |
| VT-30 | xterm mouse and DEC locator reports | `MANUAL` | X10/1000/1002/1003 with UTF-8/SGR/URXVT routing is automated. The later focus/mouse task owns remaining focus, pixel mouse, and any locator decision. |
| VT-31 | xterm window title | `MANUAL` | The later OSC policy task owns OSC 0/1/2 title behavior and sanitization; only then is the visual title test meaningful. |
| VT-32 | xterm font and window modify/report operations | `CONDITIONAL` | Protocol-driven font/window mutation is not the same as native settings or resize. Adopt only if real-app evidence justifies a narrowly permissioned policy. |
| VT-33 | Tektronix 4014 mode | `EXCLUDE` | Vector-terminal emulation is outside the terminal grid and renderer architecture. DETEK stays explicit unsupported. |
| VT-34 | vttest logging and command replay | `MANUAL` | `-c`/`-l` may make a later supplemental run reproducible, but interactive keyboard/mouse prompts and visual judgments must be recorded explicitly. |

Accounting: `AUTO` 9, `MANUAL` 9, `CONDITIONAL` 4, `EXCLUDE` 12; total
34. There are no unclassified units.

## Execution and evidence policy

This task built vttest only to verify the source pin and version; it did **not**
run interactive menus against Dart Terminal and therefore records no pass/fail
claim for the emulator.

A future supplemental run must record:

1. the archive hash above and built executable SHA-256;
2. Dart Terminal commit, Developer JIT or Release AOT mode, macOS/architecture,
   rows/columns, locale, and TERM/terminfo identity;
3. a checked command-replay file when `-c` is used, plus which prompts still
   required manual keyboard or mouse input;
4. one result per adopted unit: pass, fail, unavailable, or not executed;
5. screenshot/log references for visual observations, without replacing the
   minimized byte regression required for every fixed bug.

`AUTO` regressions block normal changes. A `MANUAL` item blocks only its named
future feature owner when that owner claims completion. `CONDITIONAL` and
`EXCLUDE` items do not block Phase 6 unless new P0 application evidence first
promotes them through an ordered ROADMAP change. Duration-only repetition is
lower-priority/nonblocking under the global ROADMAP policy; deterministic
crashes, corruption, or unbounded resources remain blockers.

## Verification results

- The downloaded 243,249-byte archive reproduced SHA-256
  `cd6886f9aefe6a3f6c566fa61271a55710901a71849c630bf5376aa984bf77cc`.
- Native arm64 configure/build completed, and the binary reported exact version
  `2.7 (20251205)`.
- Menu review covered `main.c`, `nonvt100.c`, and the VT220/320/420/520/xterm
  branches. A bounded accounting check found every ID from VT-01 through VT-34
  exactly once and the declared 9/9/4/12 disposition totals.
- `git diff --check` passed.
- `CI=true make test` passed every compatibility freshness gate, formatted 161
  Dart files without changes, reported no analyzer issues, and completed the
  full Dart Terminal test runner.
- No interactive Dart Terminal vttest result was claimed; that work remains
  supplemental and explicitly owned by the mapped future tasks.
