# Terminal sequence and mode support baseline

Generated from `compatibility/sequence_mode_inventory.json` revision 2. Do not edit this summary by hand.

## Reviewed boundary

This is a host-to-terminal compatibility baseline, not a claim to implement every function ever assigned by ECMA or every hardware option in a VT510. It includes:

- every selector and mode in the product-code implementation surface;
- terminal-display ECMA-48 controls for cursor movement, editing, erasure, scrolling, rendition, modes, tabulation, and status;
- DEC VT100–VT510 controls relevant to screen/cursor/margin/mode, character-set, rectangle, locator, and status behavior;
- every DEC-private mode number listed by xterm Patch #411, plus its high-use CSI, DCS, OSC, mouse, title, palette, and clipboard families;
- iTerm2 OSC 7 current-directory and OSC 8 hyperlink extensions because they are part of the current/later product contract.

Excluded from this bounded baseline are ECMA transmission controls and paged-media/typesetting functions without modern terminal application meaning; exhaustive ISO-2022 national replacement-set final-byte variants beyond ASCII and DEC line drawing; physical printer/modem parameter variants; Tektronix command details; terminal-to-host keyboard output; and Kitty/Ghostty-only protocols assigned to later roadmap tasks. An exclusion is not silently supported.

## Pinned sources

| Source | Family | Edition | Exact artifact |
| --- | --- | --- | --- |
| `dec-vt510-rm-b01` | `dec` | B01, August 1995, EK-VT510-RM | 3378497 bytes, `440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514` |
| `ecma-48-5e` | `ecma48` | ECMA-48, fifth edition, June 1991 | 1607865 bytes, `9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450` |
| `iterm2-escape-codes-2026-09-07` | `iterm2` | retrieved 2026-09-07 | 31258 bytes, `b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98` |
| `xterm-411` | `xterm` | xterm Patch #411, 2026-08-24 | 1633400 bytes, `969be283670deadd66934865c4de6c5ab045e3a3facc2b228decf91a20d8c36c` |

Full URLs, inner-document hashes, and citation rules are in [`specification-source-pins.md`](specification-source-pins.md).

## Coverage totals

| Support classification | Records |
| --- | ---: |
| `implemented` | 77 |
| `partial` | 15 |
| `safe-ignore` | 10 |
| `unsupported` | 158 |
| **Total** | **260** |

| Selector kind | Records |
| --- | ---: |
| `c0` | 10 |
| `c1` | 9 |
| `esc` | 35 |
| `csi` | 101 |
| `osc` | 14 |
| `dcs` | 8 |
| `sos` | 1 |
| `pm` | 1 |
| `apc` | 1 |
| `mode` | 80 |
| **Total** | **260** |

The 77 implemented plus 15 partial records reconcile exactly to all 92 product declarations (72 sequence selectors and 20 modes). The 10 safe-ignore records cover 7 concrete DCS forms and SOS/PM/APC; all 158 remaining records are explicitly unsupported/rejected.

## Partial implementation limits

| ID | Syntax | Reviewed limit |
| --- | --- | --- |
| `dec:csi:dec-dsr` | `CSI ? n` | DEC cursor-position reporting is implemented; printer, UDK, locator, and integrity reports are not. |
| `dec:csi:decrst` | `CSI ? l` | The selector is implemented for the explicitly inventoried DEC private modes only. |
| `dec:csi:decscusr` | `CSI SP q` | Cursor styles 0–6 are implemented; xterm resource-reset value 7 is rejected. |
| `dec:csi:decset` | `CSI ? h` | The selector is implemented for the explicitly inventoried DEC private modes only. |
| `ecma48:c0:ff` | `FF (0x0C)` | Handled as line feed, matching xterm rather than paged-media form feed. |
| `ecma48:c0:vt` | `VT (0x0B)` | Handled as line feed, matching xterm rather than ECMA line-tab semantics. |
| `ecma48:csi:dsr` | `CSI n` | Status and cursor-position requests are implemented; other DSR parameters are rejected. |
| `ecma48:csi:rm` | `CSI l` | The selector is implemented for the explicitly inventoried ANSI modes only. |
| `ecma48:csi:sgr` | `CSI m` | Text attributes and ANSI/256/direct colors are implemented; the full ECMA/xterm rendition repertoire is not. |
| `ecma48:csi:sm` | `CSI h` | The selector is implemented for the explicitly inventoried ANSI modes only. |
| `xterm:csi:ed` | `CSI J` | ECMA/VT modes 0–2 are implemented; xterm saved-lines mode 3 is not. |
| `xterm:dcs:xtgettcap` | `DCS + q Pt ST` | Bounded requests receive an explicit unavailable reply. The audited database intentionally omits security-sensitive Ms/OSC 52 and no dynamic keyboard-capability service is advertised. |
| `xterm:osc:osc-10` | `OSC 10 ; Pt ST` | Single bounded foreground mutation/query is implemented; chained dynamic-color parameters are not. |
| `xterm:osc:osc-11` | `OSC 11 ; Pt ST` | Single bounded background mutation/query is implemented; chained dynamic-color parameters are not. |
| `xterm:osc:osc-4` | `OSC 4 ; Pt ST` | Bounded indexed RGB mutation/query is implemented; xterm color names and every XParseColor form are not. |

## Bounded safe-ignore controls

| ID | Syntax |
| --- | --- |
| `dec:dcs:decaupss` | `DCS Ps ! u Pt ST` |
| `dec:dcs:decrqss` | `DCS $ q Pt ST` |
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
- The later focus/mouse/query task owns focus mode 1004, SGR pixel mouse 1016, and remaining report behavior.
- The OSC policy task owns title commands 0/1/2, cwd command 7, cursor color 12/112, and security-sensitive clipboard command 52.
- The terminfo task owns remaining XTSETTCAP decisions; the existing `v1 保留` feature-matrix decision continues to own Sixel.
- Unsupported extended character-set, rectangular-editing, locator, printer, and terminal-local xterm resource controls stay rejected until differential/application evidence justifies a new ordered task.

## Review acceptance

- Inventory IDs/selectors are sorted and unique, source references are pinned, and implemented/partial records have code and test evidence.
- Product declarations and inventory support records reconcile byte-for-byte by canonical selector key.
- Every in-scope non-implementation is either bounded safe-ignore or explicit unsupported/reject with a disposition note.
- The JSON inventory is the review authority; this generated summary and `FEATURE_MATRIX.md` are navigation views.
