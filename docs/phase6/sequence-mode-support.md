# Terminal sequence and mode support baseline

Generated from `compatibility/sequence_mode_inventory.json` revision 4. Do not edit this summary by hand.

## Reviewed boundary

This is a host-to-terminal compatibility baseline, not a claim to implement every function ever assigned by ECMA or every hardware option in a VT510. It includes:

- every selector and mode in the product-code implementation surface;
- terminal-display ECMA-48 controls for cursor movement, editing, erasure, scrolling, rendition, modes, tabulation, and status;
- DEC VT100–VT510 controls relevant to screen/cursor/margin/mode, character-set, rectangle, locator, and status behavior;
- every DEC-private mode number listed by xterm Patch #411, plus its high-use CSI, DCS, OSC, mouse, title, palette, and clipboard families;
- iTerm2 OSC 7 current-directory and OSC 8 hyperlink extensions because they are part of the current/later product contract.
- Kitty keyboard flag controls, xterm modifyOtherKeys controls, and mintty application-Escape mode required by captured applications; and Contour synchronized-output mode 2026.

Excluded from this bounded baseline are ECMA transmission controls and paged-media/typesetting functions without modern terminal application meaning; exhaustive ISO-2022 national replacement-set final-byte variants beyond ASCII and DEC line drawing; physical printer/modem parameter variants; Tektronix command details; terminal-to-host keyboard output beyond the declared keyboard modes; Kitty graphics; and other Ghostty-only protocols assigned to later roadmap tasks. An exclusion is not silently supported.

## Pinned sources

| Source | Family | Edition | Exact artifact |
| --- | --- | --- | --- |
| `contour-vt-extensions-05050a1-synchronized-output` | `contour` | commit 05050a11e793c8f4362bf4e34a59ed3f7e5105fe | 5967 bytes, `7cb1e9bc9fad9b56d81ebd7d0e8dad423c1b865ce1089d99f2f175239b9dde89` |
| `dec-vt510-rm-b01` | `dec` | B01, August 1995, EK-VT510-RM | 3378497 bytes, `440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514` |
| `ecma-48-5e` | `ecma48` | ECMA-48, fifth edition, June 1991 | 1607865 bytes, `9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450` |
| `ghostty-d4d8f62-semantic-prompt` | `ghostty` | commit d4d8f62262cb1a974a7d2470d5f79f811fab15e4 | 42962 bytes, `04935466b4fd8b9e0e41e7d69bb72fc6ff6141111d9274d8bda927dcb41488ff` |
| `iterm2-escape-codes-2026-09-07` | `iterm2` | retrieved 2026-09-07 | 31258 bytes, `b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98` |
| `kitty-0-48-2-keyboard-protocol` | `kitty` | kitty v0.48.2 | 36641 bytes, `cd452d4f1b5070752499233f8d76455c854d0ec5f2318e38309f835baf2410ce` |
| `mintty-ctrlseqs-25c73c7` | `mintty` | wiki revision 25c73c77961243934d790e632f1f9decaae82ee8 | 264856 bytes, `4144a9212fdc412088d5a094a09d827d729082239c8fbb7ef7b163d13d5d9d0e` |
| `xterm-411` | `xterm` | xterm Patch #411, 2026-08-24 | 1633400 bytes, `969be283670deadd66934865c4de6c5ab045e3a3facc2b228decf91a20d8c36c` |

Full URLs, inner-document hashes, and citation rules are in [`specification-source-pins.md`](specification-source-pins.md).

## Coverage totals

| Support classification | Records |
| --- | ---: |
| `implemented` | 93 |
| `partial` | 20 |
| `safe-ignore` | 9 |
| `unsupported` | 145 |
| **Total** | **267** |

| Selector kind | Records |
| --- | ---: |
| `c0` | 10 |
| `c1` | 9 |
| `esc` | 35 |
| `csi` | 105 |
| `osc` | 15 |
| `dcs` | 8 |
| `sos` | 1 |
| `pm` | 1 |
| `apc` | 1 |
| `mode` | 82 |
| **Total** | **267** |

The 93 implemented plus 20 partial records reconcile exactly to all 113 product declarations (89 sequence selectors and 24 modes). The 9 safe-ignore records cover 6 concrete DCS forms and SOS/PM/APC; all 145 remaining records are explicitly unsupported/rejected.

## Partial implementation limits

| ID | Syntax | Reviewed limit |
| --- | --- | --- |
| `dec:csi:dec-dsr` | `CSI ? n` | DEC cursor-position reporting is implemented; printer, UDK, locator, and integrity reports are not. |
| `dec:csi:decrst` | `CSI ? l` | The selector is implemented for the explicitly inventoried DEC private modes only. |
| `dec:csi:decscusr` | `CSI SP q` | Cursor styles 0–6 are implemented; xterm resource-reset value 7 is rejected. |
| `dec:csi:decset` | `CSI ? h` | The selector is implemented for the explicitly inventoried DEC private modes only. |
| `dec:dcs:decrqss` | `DCS $ q Pt ST` | The complete SGR request payload m receives the current rendition in a bounded pinned-xterm form. Other status-string selectors remain explicit bounded unsupported. |
| `ecma48:c0:ff` | `FF (0x0C)` | Handled as line feed, matching xterm rather than paged-media form feed. |
| `ecma48:c0:vt` | `VT (0x0B)` | Handled as line feed, matching xterm rather than ECMA line-tab semantics. |
| `ecma48:csi:dsr` | `CSI n` | Status and cursor-position requests are implemented; other DSR parameters are rejected. |
| `ecma48:csi:rm` | `CSI l` | The selector is implemented for the explicitly inventoried ANSI modes only. |
| `ecma48:csi:sgr` | `CSI m` | Text attributes and ANSI/256/direct colors are implemented; the full ECMA/xterm rendition repertoire is not. |
| `ecma48:csi:sm` | `CSI h` | The selector is implemented for the explicitly inventoried ANSI modes only. |
| `ghostty:osc:osc-133` | `OSC 133 ; Ps [; Pt] ST` | The bounded A/B/C/D/P lifecycle subset projects privacy-safe shell state and row flags; options are validated but never decoded or retained, and I/L/N extensions remain rejected. |
| `xterm:csi:ed` | `CSI J` | ECMA/VT modes 0–2 are implemented; xterm saved-lines mode 3 is not. |
| `xterm:csi:xtwinops` | `CSI t` | Text-area reports 14/18 and bounded title save/restore operations 22/23 with selectors 0–2 and stack access 0 are implemented; other window operations and direct stack slots remain explicit unsupported. |
| `xterm:dcs:xtgettcap` | `DCS + q Pt ST` | Bounded requests receive an explicit unavailable reply. The audited database intentionally omits security-sensitive Ms/OSC 52 and no dynamic keyboard-capability service is advertised. |
| `xterm:osc:osc-10` | `OSC 10 ; Pt ST` | Single bounded foreground mutation/query is implemented; chained dynamic-color parameters are not. |
| `xterm:osc:osc-11` | `OSC 11 ; Pt ST` | Single bounded background mutation/query is implemented; chained dynamic-color parameters are not. |
| `xterm:osc:osc-12` | `OSC 12 ; Pt ST` | Single bounded cursor-color mutation/query is implemented independently of text foreground; chained dynamic-color parameters are not. |
| `xterm:osc:osc-4` | `OSC 4 ; Pt ST` | Bounded indexed RGB mutation/query is implemented; xterm color names and every XParseColor form are not. |
| `xterm:osc:osc-52` | `OSC 52 ; Pc ; Pd ST` | Bounded selector/data parsing is implemented with a deny-by-default policy: queries return empty data and writes/clears have no clipboard authority. Opt-in access remains deferred. |

## Bounded safe-ignore controls

| ID | Syntax |
| --- | --- |
| `dec:dcs:decaupss` | `DCS Ps ! u Pt ST` |
| `dec:dcs:decrsps` | `DCS Ps $ t Pt ST` |
| `dec:dcs:decudk` | `DCS Ps ; Ps \| Pt ST` |
| `ecma48:apc:apc` | `APC Pt ST` |
| `ecma48:pm:pm` | `PM Pt ST` |
| `ecma48:sos:sos` | `SOS Pt ST` |
| `xterm:dcs:sixel` | `DCS Ps q Pt ST` |
| `xterm:dcs:xtgetxres` | `DCS + Q Pt ST` |
| `xterm:dcs:xtsettcap` | `DCS + p Pt ST` |

## Gap ownership

- The next black-box differential and real-application matrix tasks decide which generic ECMA/DEC/xterm gaps become implementation work.
- The focus/mouse/query task has implemented focus mode 1004, SGR pixel mouse 1016, bounded DECRQSS SGR, XTVERSION, and text-area size reports 14/18. Other report operations remain evidence-driven.
- The OSC policy task has implemented title commands 0/1/2, cwd command 7, cursor color 12/112, and the security-sensitive OSC 52 deny-by-default boundary. Opt-in clipboard access remains deferred.
- The terminfo task owns remaining XTSETTCAP decisions; the existing `v1 保留` feature-matrix decision continues to own Sixel.
- Unsupported extended character-set, rectangular-editing, locator, printer, and terminal-local xterm resource controls stay rejected until differential/application evidence justifies a new ordered task.

## Review acceptance

- Inventory IDs/selectors are sorted and unique, source references are pinned, and implemented/partial records have code and test evidence.
- Product declarations and inventory support records reconcile byte-for-byte by canonical selector key.
- Every in-scope non-implementation is either bounded safe-ignore or explicit unsupported/reject with a disposition note.
- The JSON inventory is the review authority; this generated summary and `FEATURE_MATRIX.md` are navigation views.
