# Terminal compatibility specification source pins

These are the primary, immutable baselines for the Phase 6 sequence/mode
inventory. The repository stores metadata and hashes, not copies of the
copyrighted standards. Retrieval dates are recorded per source.

| Source ID | Baseline | Exact artifact | Bytes | SHA-256 |
| --- | --- | --- | ---: | --- |
| `contour-vt-extensions-05050a1-synchronized-output` | Synchronized Output, commit `05050a11e793c8f4362bf4e34a59ed3f7e5105fe` | [pinned upstream source](https://raw.githubusercontent.com/contour-terminal/vt-extensions/05050a11e793c8f4362bf4e34a59ed3f7e5105fe/synchronized-output.md) | 5,967 | `7cb1e9bc9fad9b56d81ebd7d0e8dad423c1b865ce1089d99f2f175239b9dde89` |
| `ecma-48-5e` | ECMA-48, fifth edition, June 1991 | [ECMA official PDF](https://ecma-international.org/wp-content/uploads/ECMA-48_5th_edition_june_1991.pdf) | 1,607,865 | `9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450` |
| `dec-vt510-rm-b01` | VT510 Video Terminal Programmer Information, B01, `EK-VT510-RM` | [archived DEC manual PDF](https://vt100.net/mirror/mds-199909/cd3/term/vt510rmb.pdf) | 3,378,497 | `440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514` |
| `ghostty-d4d8f62-semantic-prompt` | Ghostty OSC semantic prompt parser, commit `d4d8f62262cb1a974a7d2470d5f79f811fab15e4` | [pinned upstream source](https://raw.githubusercontent.com/ghostty-org/ghostty/d4d8f62262cb1a974a7d2470d5f79f811fab15e4/src/terminal/osc/parsers/semantic_prompt.zig) | 42,962 | `04935466b4fd8b9e0e41e7d69bb72fc6ff6141111d9274d8bda927dcb41488ff` |
| `iterm2-escape-codes-2026-09-07` | iTerm2 Proprietary Escape Codes, retrieved 2026-09-07 | [official iTerm2 documentation](https://iterm2.com/documentation-escape-codes.html) | 31,258 | `b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98` |
| `kitty-0-48-2-keyboard-protocol` | Comprehensive keyboard handling in terminals, kitty v0.48.2 | [pinned upstream source](https://raw.githubusercontent.com/kovidgoyal/kitty/v0.48.2/docs/keyboard-protocol.rst) | 36,641 | `cd452d4f1b5070752499233f8d76455c854d0ec5f2318e38309f835baf2410ce` |
| `mintty-ctrlseqs-25c73c7` | mintty Control Sequences, wiki revision `25c73c77961243934d790e632f1f9decaae82ee8` | [pinned wiki revision](https://github.com/mintty/mintty/wiki/CtrlSeqs/25c73c77961243934d790e632f1f9decaae82ee8) | 264,856 | `4144a9212fdc412088d5a094a09d827d729082239c8fbb7ef7b163d13d5d9d0e` |
| `xterm-411` | xterm Patch #411, 2026-08-24 | [upstream source archive](https://invisible-island.net/archives/xterm/xterm-411.tgz) | 1,633,400 | `969be283670deadd66934865c4de6c5ab045e3a3facc2b228decf91a20d8c36c` |

The xterm reference is `xterm-411/ctlseqs.ms` inside the archive: 167,851
bytes, SHA-256
`69773380309da4c8b5d4ec9646eec703c47bc41db29a8efa5b94c30798c72349`.
The generated web page is useful for navigation but is not the pin because it
can change when a later patch is published.

## Citation rules

- ECMA records cite a clause number and mnemonic from the fifth edition.
- DEC records cite the manual part/chapter and mnemonic. Part II chapters 4–8
  are the ANSI-mode programming baseline; hardware setup, printer transport,
  PCTerm, and ASCII personality details are not automatically terminal-emulator
  requirements.
- xterm records cite the section or literal control form in the pinned
  `ctlseqs.ms` file. Later xterm releases require an explicit source-pin update,
  inventory diff, and review rather than silently changing this baseline.
- iTerm2 records cite the literal OSC 7 current-directory or OSC 8 hyperlink
  form in the pinned official documentation. xterm Patch #411 does not document
  OSC 8, so the hyperlink record does not misattribute that extension to xterm.
- Kitty records cite the progressive-enhancement control forms in the pinned
  v0.48.2 `keyboard-protocol.rst`. mintty mode 7727 cites its pinned historical
  control-sequence page rather than treating the mode as a DEC assignment.
- Contour records cite the fixed synchronized-output extension proposal for
  mode 2026. Its protocol leaves timeout policy to implementations; the
  product's 1,000 ms recovery deadline is therefore implementation policy.
- Ghostty records cite the exact semantic-prompt parser commit used to establish
  the accepted OSC 133 subset.
- When more than one source specifies a control, the record has one stable ID
  under its defining/primary family and may cite additional source pins.

## Identifier taxonomy

Record IDs are ASCII and deterministic:

```text
<primary-family>:<selector-kind>:<lowercase-name>
```

Families are `contour`, `dec`, `ecma48`, `ghostty`, `iterm2`, `kitty`,
`mintty`, and `xterm`. Selector kinds are `c0`, `c1`, `esc`, `csi`, `osc`,
`dcs`, `sos`,
`pm`, `apc`, and `mode`. Mode names
include `private-` when their selector uses the DEC private marker. The typed
selector, not the human-readable syntax, is the uniqueness key.

The manifest validator rejects unknown fields, invalid selector byte ranges,
duplicate IDs/selectors, unsorted records, missing source pins, unsafe evidence
paths, absent evidence files, and inconsistent support/disposition records.
