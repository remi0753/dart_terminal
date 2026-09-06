import 'dart:convert';
import 'dart:io';

import '../lib/src/terminal_core/terminal_compatibility_surface.dart';

const String defaultGeneratedTerminalCompatibilityInventoryPath =
    'compatibility/sequence_mode_inventory.json';

const String _implementationEvidence =
    'lib/src/terminal_core/terminal_screen_parser_sink.dart#semantic-dispatch';
const String _implementationTestEvidence =
    'test/terminal_compatibility_surface_test.dart#declared-selector-reconciliation';
const String _unsupportedNotes =
    'Not implemented; explicitly rejected by the semantic sink and retained '
    'for later compatibility prioritization from differential/application evidence.';
const String _boundedIgnoreNotes =
    'The bounded parser consumes this complete control string through its '
    'terminator; the semantic sink deliberately ignores it and records one '
    'unsupported sequence without mutating terminal state.';

final class _Metadata {
  const _Metadata(
    this.family,
    this.name,
    this.mnemonic,
    this.locator, {
    this.support = 'implemented',
    this.notes = '',
    this.reply = false,
  });

  final String family;
  final String name;
  final String mnemonic;
  final String locator;
  final String support;
  final String notes;
  final bool reply;
}

final class _Gap {
  const _Gap({
    required this.family,
    required this.kind,
    required this.name,
    required this.mnemonic,
    required this.syntax,
    required this.selector,
    required this.locator,
    this.notes = _unsupportedNotes,
  });

  final String family;
  final String kind;
  final String name;
  final String mnemonic;
  final String syntax;
  final Map<String, Object?> selector;
  final String locator;
  final String notes;
}

const Map<int, _Metadata> _controlMetadata = <int, _Metadata>{
  0x07: _Metadata('ecma48', 'bel', 'BEL', 'clause 8.3.3, BEL—Bell'),
  0x08: _Metadata('ecma48', 'bs', 'BS', 'clause 8.3.5, BS—Backspace'),
  0x09: _Metadata(
    'ecma48',
    'ht',
    'HT',
    'clause 8.3.60, HT—Character Tabulation',
  ),
  0x0a: _Metadata('ecma48', 'lf', 'LF', 'clause 8.3.74, LF—Line Feed'),
  0x0b: _Metadata(
    'ecma48',
    'vt',
    'VT',
    'clause 8.3.161, VT—Line Tabulation',
    support: 'partial',
    notes: 'Handled as line feed, matching xterm rather than ECMA line-tab semantics.',
  ),
  0x0c: _Metadata(
    'ecma48',
    'ff',
    'FF',
    'clause 8.3.51, FF—Form Feed',
    support: 'partial',
    notes: 'Handled as line feed, matching xterm rather than paged-media form feed.',
  ),
  0x0d: _Metadata('ecma48', 'cr', 'CR', 'clause 8.3.15, CR—Carriage Return'),
  0x0e: _Metadata(
    'ecma48',
    'so',
    'SO',
    'clause 8.3.126, SO—Shift Out',
    notes: 'Invokes designated G1 into GL.',
  ),
  0x0f: _Metadata(
    'ecma48',
    'si',
    'SI',
    'clause 8.3.119, SI—Shift In',
    notes: 'Invokes designated G0 into GL.',
  ),
  0x84: _Metadata('dec', 'ind', 'IND', 'Part II chapter 5, IND—Index'),
  0x85: _Metadata('ecma48', 'nel', 'NEL', 'clause 8.3.86, NEL—Next Line'),
  0x88: _Metadata(
    'ecma48',
    'hts',
    'HTS',
    'clause 8.3.62, HTS—Character Tabulation Set',
  ),
  0x8d: _Metadata('ecma48', 'ri', 'RI', 'clause 8.3.104, RI—Reverse Line Feed'),
};

const Map<int, _Metadata> _escapeMetadata = <int, _Metadata>{
  0x37: _Metadata(
    'dec',
    'decsc',
    'DECSC',
    'Part II chapter 5, DECSC—Save Cursor',
  ),
  0x38: _Metadata(
    'dec',
    'decrc',
    'DECRC',
    'Part II chapter 5, DECRC—Restore Cursor',
  ),
  0x3d: _Metadata(
    'dec',
    'deckpam',
    'DECKPAM',
    'Part II chapter 5, DECKPAM—Keypad Application Mode',
  ),
  0x3e: _Metadata(
    'dec',
    'deckpnm',
    'DECKPNM',
    'Part II chapter 5, DECKPNM—Keypad Numeric Mode',
  ),
  0x44: _Metadata(
    'dec',
    'ind-7bit',
    'IND-7BIT',
    'Part II chapter 5, IND—Index',
  ),
  0x45: _Metadata(
    'dec',
    'nel-7bit',
    'NEL-7BIT',
    'Part II chapter 5, NEL—Next Line',
  ),
  0x48: _Metadata(
    'dec',
    'hts-7bit',
    'HTS-7BIT',
    'Part II chapter 5, HTS—Tab Set',
  ),
  0x4d: _Metadata(
    'dec',
    'ri-7bit',
    'RI-7BIT',
    'Part II chapter 5, RI—Reverse Index',
  ),
  0x63: _Metadata('dec', 'ris', 'RIS', 'Part II chapter 5, RIS—Full Reset'),
  0x012830: _Metadata(
    'dec',
    'designate-g0-dec-special',
    'DESIGNATE-G0-DEC-SPECIAL',
    'Part II chapter 5, SCS—Select Character Set',
  ),
  0x012842: _Metadata(
    'dec',
    'designate-g0-ascii',
    'DESIGNATE-G0-ASCII',
    'Part II chapter 5, SCS—Select Character Set',
  ),
  0x012930: _Metadata(
    'dec',
    'designate-g1-dec-special',
    'DESIGNATE-G1-DEC-SPECIAL',
    'Part II chapter 5, SCS—Select Character Set',
  ),
  0x012942: _Metadata(
    'dec',
    'designate-g1-ascii',
    'DESIGNATE-G1-ASCII',
    'Part II chapter 5, SCS—Select Character Set',
  ),
};

const Map<int, _Metadata> _dcsMetadata = <int, _Metadata>{
  0x012b71: _Metadata(
    'xterm',
    'xtgettcap',
    'XTGETTCAP',
    'ctlseqs.ms, XTGETTCAP',
    support: 'partial',
    notes:
        'Bounded requests receive an explicit unavailable reply. The audited '
        'database intentionally omits security-sensitive Ms/OSC 52 and no '
        'dynamic keyboard-capability service is advertised.',
    reply: true,
  ),
};

const Map<int, _Metadata> _csiMetadata = <int, _Metadata>{
  0x40: _Metadata(
    'ecma48',
    'ich',
    'ICH',
    'clause 8.3.64, ICH—Insert Character',
  ),
  0x41: _Metadata('ecma48', 'cuu', 'CUU', 'clause 8.3.22, CUU—Cursor Up'),
  0x42: _Metadata('ecma48', 'cud', 'CUD', 'clause 8.3.19, CUD—Cursor Down'),
  0x43: _Metadata('ecma48', 'cuf', 'CUF', 'clause 8.3.20, CUF—Cursor Right'),
  0x44: _Metadata('ecma48', 'cub', 'CUB', 'clause 8.3.18, CUB—Cursor Left'),
  0x45: _Metadata(
    'ecma48',
    'cnl',
    'CNL',
    'clause 8.3.12, CNL—Cursor Next Line',
  ),
  0x46: _Metadata(
    'ecma48',
    'cpl',
    'CPL',
    'clause 8.3.13, CPL—Cursor Preceding Line',
  ),
  0x47: _Metadata(
    'ecma48',
    'cha',
    'CHA',
    'clause 8.3.9, CHA—Cursor Character Absolute',
  ),
  0x48: _Metadata('ecma48', 'cup', 'CUP', 'clause 8.3.21, CUP—Cursor Position'),
  0x49: _Metadata(
    'ecma48',
    'cht',
    'CHT',
    'clause 8.3.10, CHT—Cursor Forward Tabulation',
  ),
  0x4a: _Metadata(
    'xterm',
    'ed',
    'ED',
    'ctlseqs.ms, CSI Ps J—Erase in Display',
    support: 'partial',
    notes:
        'ECMA/VT modes 0–2 are implemented; xterm saved-lines mode 3 is not.',
  ),
  0x4b: _Metadata('ecma48', 'el', 'EL', 'clause 8.3.41, EL—Erase in Line'),
  0x4c: _Metadata('ecma48', 'il', 'IL', 'clause 8.3.67, IL—Insert Line'),
  0x4d: _Metadata('ecma48', 'dl', 'DL', 'clause 8.3.32, DL—Delete Line'),
  0x50: _Metadata(
    'ecma48',
    'dch',
    'DCH',
    'clause 8.3.26, DCH—Delete Character',
  ),
  0x53: _Metadata('ecma48', 'su', 'SU', 'clause 8.3.147, SU—Scroll Up'),
  0x54: _Metadata('dec', 'sd-vt', 'SD-VT', 'Part II chapter 5, SD—Pan Up'),
  0x58: _Metadata('ecma48', 'ech', 'ECH', 'clause 8.3.38, ECH—Erase Character'),
  0x5a: _Metadata(
    'ecma48',
    'cbt',
    'CBT',
    'clause 8.3.7, CBT—Cursor Backward Tabulation',
  ),
  0x60: _Metadata(
    'ecma48',
    'hpa',
    'HPA',
    'clause 8.3.57, HPA—Character Position Absolute',
  ),
  0x63: _Metadata(
    'dec',
    'primary-da',
    'PRIMARY-DA',
    'Part II chapter 5, DA—Primary Device Attributes',
    reply: true,
  ),
  0x64: _Metadata(
    'ecma48',
    'vpa',
    'VPA',
    'clause 8.3.158, VPA—Line Position Absolute',
  ),
  0x66: _Metadata(
    'ecma48',
    'hvp',
    'HVP',
    'clause 8.3.63, HVP—Character and Line Position',
  ),
  0x67: _Metadata('xterm', 'tbc', 'TBC', 'ctlseqs.ms, CSI Ps g—Tab Clear'),
  0x68: _Metadata(
    'ecma48',
    'sm',
    'SM',
    'clause 8.3.125, SM—Set Mode',
    support: 'partial',
    notes: 'The selector is implemented for the explicitly inventoried ANSI modes only.',
  ),
  0x6c: _Metadata(
    'ecma48',
    'rm',
    'RM',
    'clause 8.3.106, RM—Reset Mode',
    support: 'partial',
    notes: 'The selector is implemented for the explicitly inventoried ANSI modes only.',
  ),
  0x6d: _Metadata(
    'ecma48',
    'sgr',
    'SGR',
    'clause 8.3.117, SGR—Select Graphic Rendition',
    support: 'partial',
    notes: 'Text attributes and ANSI/256/direct colors are implemented; the full ECMA/xterm rendition repertoire is not.',
  ),
  0x6e: _Metadata(
    'ecma48',
    'dsr',
    'DSR',
    'clause 8.3.35, DSR—Device Status Report',
    support: 'partial',
    notes: 'Status and cursor-position requests are implemented; other DSR parameters are rejected.',
    reply: true,
  ),
  0x72: _Metadata(
    'dec',
    'decstbm',
    'DECSTBM',
    'Part II chapter 5, DECSTBM—Set Top and Bottom Margins',
  ),
  0x73: _Metadata(
    'xterm',
    'scosc-decslrm',
    'SCOSC-DECSLRM',
    'ctlseqs.ms, CSI s / CSI Pl ; Pr s',
  ),
  0x74: _Metadata(
    'xterm',
    'xtwinops',
    'XTWINOPS',
    'ctlseqs.ms, XTWINOPS',
    support: 'partial',
    notes: 'Bounded title save/restore operations 22/23 with selectors 0–2 and stack access 0 are implemented; other window operations and direct stack slots remain explicit unsupported.',
  ),
  0x75: _Metadata(
    'xterm',
    'scorc',
    'SCORC',
    'ctlseqs.ms, CSI u—Restore cursor',
  ),
  0x012071: _Metadata(
    'dec',
    'decscusr',
    'DECSCUSR',
    'Part II chapter 5, DECSCUSR—Set Cursor Style',
    support: 'partial',
    notes: 'Cursor styles 0–6 are implemented; xterm resource-reset value 7 is rejected.',
  ),
  0x012470: _Metadata(
    'dec',
    'decrqm',
    'DECRQM',
    'Part II chapter 5, DECRQM—Request Mode',
    reply: true,
  ),
  0x3e000063: _Metadata(
    'xterm',
    'secondary-da',
    'SECONDARY-DA',
    'ctlseqs.ms, CSI > Ps c—Secondary Device Attributes',
    reply: true,
  ),
  0x3f000068: _Metadata(
    'dec',
    'decset',
    'DECSET',
    'Part II chapter 5, DECSET—Set DEC Private Mode',
    support: 'partial',
    notes: 'The selector is implemented for the explicitly inventoried DEC private modes only.',
  ),
  0x3f00006c: _Metadata(
    'dec',
    'decrst',
    'DECRST',
    'Part II chapter 5, DECRST—Reset DEC Private Mode',
    support: 'partial',
    notes: 'The selector is implemented for the explicitly inventoried DEC private modes only.',
  ),
  0x3f00006e: _Metadata(
    'dec',
    'dec-dsr',
    'DEC-DSR',
    'Part II chapter 5, DEC DSR—Device Status Report',
    support: 'partial',
    notes: 'DEC cursor-position reporting is implemented; printer, UDK, locator, and integrity reports are not.',
    reply: true,
  ),
  0x3f012470: _Metadata(
    'dec',
    'dec-decrqm',
    'DEC-DECRQM',
    'Part II chapter 5, DEC private DECRQM—Request Mode',
    reply: true,
  ),
};

const Map<int, _Metadata> _oscMetadata = <int, _Metadata>{
  0: _Metadata(
    'xterm',
    'osc-0',
    'OSC-0',
    'ctlseqs.ms, OSC 0—Icon and window title',
  ),
  1: _Metadata('xterm', 'osc-1', 'OSC-1', 'ctlseqs.ms, OSC 1—Icon title'),
  2: _Metadata('xterm', 'osc-2', 'OSC-2', 'ctlseqs.ms, OSC 2—Window title'),
  4: _Metadata(
    'xterm',
    'osc-4',
    'OSC-4',
    'ctlseqs.ms, OSC 4—Change/query ANSI color',
    support: 'partial',
    notes: 'Bounded indexed RGB mutation/query is implemented; xterm color names and every XParseColor form are not.',
  ),
  7: _Metadata(
    'iterm2',
    'osc-7',
    'OSC-7',
    'CurrentDir / OSC 7',
    notes: 'Strict bounded file-URI session metadata is implemented without process cwd or filesystem mutation.',
  ),
  8: _Metadata('iterm2', 'osc-8', 'OSC-8', 'Anchor (OSC 8)'),
  10: _Metadata(
    'xterm',
    'osc-10',
    'OSC-10',
    'ctlseqs.ms, OSC 10—Dynamic foreground color',
    support: 'partial',
    notes: 'Single bounded foreground mutation/query is implemented; chained dynamic-color parameters are not.',
  ),
  11: _Metadata(
    'xterm',
    'osc-11',
    'OSC-11',
    'ctlseqs.ms, OSC 11—Dynamic background color',
    support: 'partial',
    notes: 'Single bounded background mutation/query is implemented; chained dynamic-color parameters are not.',
  ),
  12: _Metadata(
    'xterm',
    'osc-12',
    'OSC-12',
    'ctlseqs.ms, OSC 12—Cursor color',
    support: 'partial',
    notes: 'Single bounded cursor-color mutation/query is implemented independently of text foreground; chained dynamic-color parameters are not.',
    reply: true,
  ),
  52: _Metadata(
    'xterm',
    'osc-52',
    'OSC-52',
    'ctlseqs.ms, OSC 52—Manipulate Selection Data',
    support: 'partial',
    notes: 'Bounded selector/data parsing is implemented with a deny-by-default policy: queries return empty data and writes/clears have no clipboard authority. Opt-in access remains deferred.',
    reply: true,
  ),
  104: _Metadata(
    'xterm',
    'osc-104',
    'OSC-104',
    'ctlseqs.ms, OSC 104—Reset ANSI color',
  ),
  110: _Metadata(
    'xterm',
    'osc-110',
    'OSC-110',
    'ctlseqs.ms, OSC 110—Reset foreground color',
  ),
  111: _Metadata(
    'xterm',
    'osc-111',
    'OSC-111',
    'ctlseqs.ms, OSC 111—Reset background color',
  ),
  112: _Metadata(
    'xterm',
    'osc-112',
    'OSC-112',
    'ctlseqs.ms, OSC 112—Reset cursor color',
  ),
};

const Map<int, _Metadata> _ansiModeMetadata = <int, _Metadata>{
  4: _Metadata(
    'ecma48',
    'irm',
    'IRM',
    'clause 7.2.10, IRM—Insertion Replacement Mode',
  ),
};

const Map<int, _Metadata> _decModeMetadata = <int, _Metadata>{
  1: _Metadata(
    'dec',
    'decckm',
    'DECCKM',
    'Part II chapter 5, DECCKM—Cursor Keys Mode',
  ),
  5: _Metadata(
    'dec',
    'decscnm',
    'DECSCNM',
    'Part II chapter 5, DECSCNM—Screen Mode',
  ),
  6: _Metadata('dec', 'decom', 'DECOM', 'Part II chapter 5, DECOM—Origin Mode'),
  7: _Metadata(
    'dec',
    'decawm',
    'DECAWM',
    'Part II chapter 5, DECAWM—Autowrap Mode',
  ),
  9: _Metadata(
    'xterm',
    'x10-mouse',
    'X10-MOUSE',
    'ctlseqs.ms, DEC private mode 9',
  ),
  12: _Metadata(
    'xterm',
    'cursor-blink',
    'CURSOR-BLINK',
    'ctlseqs.ms, DEC private mode 12',
  ),
  25: _Metadata(
    'dec',
    'dectcem',
    'DECTCEM',
    'Part II chapter 5, DECTCEM—Text Cursor Enable Mode',
  ),
  47: _Metadata(
    'xterm',
    'alternate-screen',
    'ALTERNATE-SCREEN',
    'ctlseqs.ms, DEC private mode 47',
  ),
  69: _Metadata(
    'dec',
    'declrmm',
    'DECLRMM',
    'Part II chapter 5, DECLRMM—Left Right Margin Mode',
  ),
  1000: _Metadata(
    'xterm',
    'x11-mouse',
    'X11-MOUSE',
    'ctlseqs.ms, DEC private mode 1000',
  ),
  1002: _Metadata(
    'xterm',
    'button-event-mouse',
    'BUTTON-EVENT-MOUSE',
    'ctlseqs.ms, DEC private mode 1002',
  ),
  1003: _Metadata(
    'xterm',
    'any-event-mouse',
    'ANY-EVENT-MOUSE',
    'ctlseqs.ms, DEC private mode 1003',
  ),
  1004: _Metadata(
    'xterm',
    'xterm-focus-reporting',
    'XTERM-FOCUS-REPORTING',
    'ctlseqs.ms, DEC private mode 1004—xterm focus reporting',
  ),
  1005: _Metadata(
    'xterm',
    'utf8-mouse',
    'UTF8-MOUSE',
    'ctlseqs.ms, DEC private mode 1005',
  ),
  1006: _Metadata(
    'xterm',
    'sgr-mouse',
    'SGR-MOUSE',
    'ctlseqs.ms, DEC private mode 1006',
  ),
  1015: _Metadata(
    'xterm',
    'urxvt-mouse',
    'URXVT-MOUSE',
    'ctlseqs.ms, DEC private mode 1015',
  ),
  1047: _Metadata(
    'xterm',
    'alternate-screen-clear',
    'ALTERNATE-SCREEN-CLEAR',
    'ctlseqs.ms, DEC private mode 1047',
  ),
  1048: _Metadata(
    'xterm',
    'cursor-save-mode',
    'CURSOR-SAVE-MODE',
    'ctlseqs.ms, DEC private mode 1048',
  ),
  1049: _Metadata(
    'xterm',
    'alternate-screen-save',
    'ALTERNATE-SCREEN-SAVE',
    'ctlseqs.ms, DEC private mode 1049',
  ),
  2004: _Metadata(
    'xterm',
    'bracketed-paste',
    'BRACKETED-PASTE',
    'ctlseqs.ms, DEC private mode 2004',
  ),
};

const List<_Gap> _gaps = <_Gap>[
  _Gap(
    family: 'xterm',
    kind: 'c0',
    name: 'enq',
    mnemonic: 'ENQ',
    syntax: 'ENQ (0x05)',
    selector: <String, Object?>{'kind': 'c0', 'code': 5},
    locator: 'ctlseqs.ms, ENQ—Return Terminal Status',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'c1',
    name: 'ss2',
    mnemonic: 'SS2',
    syntax: 'SS2 (0x8E)',
    selector: <String, Object?>{'kind': 'c1', 'code': 142},
    locator: 'clause 8.3.141, SS2—Single Shift Two',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'c1',
    name: 'ss3',
    mnemonic: 'SS3',
    syntax: 'SS3 (0x8F)',
    selector: <String, Object?>{'kind': 'c1', 'code': 143},
    locator: 'clause 8.3.142, SS3—Single Shift Three',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'c1',
    name: 'spa',
    mnemonic: 'SPA',
    syntax: 'SPA (0x96)',
    selector: <String, Object?>{'kind': 'c1', 'code': 150},
    locator: 'clause 8.3.129, SPA—Start of Guarded Area',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'c1',
    name: 'epa',
    mnemonic: 'EPA',
    syntax: 'EPA (0x97)',
    selector: <String, Object?>{'kind': 'c1', 'code': 151},
    locator: 'clause 8.3.46, EPA—End of Guarded Area',
  ),
  _Gap(
    family: 'xterm',
    kind: 'c1',
    name: 'decid',
    mnemonic: 'DECID',
    syntax: 'DECID (0x9A or ESC Z)',
    selector: <String, Object?>{'kind': 'c1', 'code': 154},
    locator: 'ctlseqs.ms, DECID—Return Terminal ID',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 's7c1t',
    mnemonic: 'S7C1T',
    syntax: 'ESC SP F',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[32],
      'finalByte': 70,
    },
    locator: 'Part II chapter 5, S7C1T—Send 7-Bit C1 Controls',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 's8c1t',
    mnemonic: 'S8C1T',
    syntax: 'ESC SP G',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[32],
      'finalByte': 71,
    },
    locator: 'Part II chapter 5, S8C1T—Send 8-Bit C1 Controls',
  ),
  _Gap(
    family: 'xterm',
    kind: 'esc',
    name: 'ansi-level-1',
    mnemonic: 'ANSI-LEVEL-1',
    syntax: 'ESC SP L',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[32],
      'finalByte': 76,
    },
    locator: 'ctlseqs.ms, ESC SP L',
  ),
  _Gap(
    family: 'xterm',
    kind: 'esc',
    name: 'ansi-level-2',
    mnemonic: 'ANSI-LEVEL-2',
    syntax: 'ESC SP M',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[32],
      'finalByte': 77,
    },
    locator: 'ctlseqs.ms, ESC SP M',
  ),
  _Gap(
    family: 'xterm',
    kind: 'esc',
    name: 'ansi-level-3',
    mnemonic: 'ANSI-LEVEL-3',
    syntax: 'ESC SP N',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[32],
      'finalByte': 78,
    },
    locator: 'ctlseqs.ms, ESC SP N',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decdhl-top',
    mnemonic: 'DECDHL-TOP',
    syntax: 'ESC # 3',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[35],
      'finalByte': 51,
    },
    locator: 'Part II chapter 5, DECDHL—Double Height Line',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decdhl-bottom',
    mnemonic: 'DECDHL-BOTTOM',
    syntax: 'ESC # 4',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[35],
      'finalByte': 52,
    },
    locator: 'Part II chapter 5, DECDHL—Double Height Line',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decswl',
    mnemonic: 'DECSWL',
    syntax: 'ESC # 5',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[35],
      'finalByte': 53,
    },
    locator: 'Part II chapter 5, DECSWL—Single Width Line',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decdwl',
    mnemonic: 'DECDWL',
    syntax: 'ESC # 6',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[35],
      'finalByte': 54,
    },
    locator: 'Part II chapter 5, DECDWL—Double Width Line',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decaln',
    mnemonic: 'DECALN',
    syntax: 'ESC # 8',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[35],
      'finalByte': 56,
    },
    locator: 'Part II chapter 5, DECALN—Screen Alignment Pattern',
  ),
  _Gap(
    family: 'xterm',
    kind: 'esc',
    name: 'select-default-charset',
    mnemonic: 'SELECT-DEFAULT-CHARSET',
    syntax: 'ESC % @',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[37],
      'finalByte': 64,
    },
    locator: 'ctlseqs.ms, ESC % @',
  ),
  _Gap(
    family: 'xterm',
    kind: 'esc',
    name: 'select-utf8',
    mnemonic: 'SELECT-UTF8',
    syntax: 'ESC % G',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[37],
      'finalByte': 71,
    },
    locator: 'ctlseqs.ms, ESC % G',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decbi',
    mnemonic: 'DECBI',
    syntax: 'ESC 6',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 54,
    },
    locator: 'Part II chapter 5, DECBI—Back Index',
  ),
  _Gap(
    family: 'dec',
    kind: 'esc',
    name: 'decfi',
    mnemonic: 'DECFI',
    syntax: 'ESC 9',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 57,
    },
    locator: 'Part II chapter 5, DECFI—Forward Index',
  ),
  _Gap(
    family: 'xterm',
    kind: 'esc',
    name: 'decid-7bit',
    mnemonic: 'DECID-7BIT',
    syntax: 'ESC Z',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 90,
    },
    locator: 'ctlseqs.ms, ESC Z—Return Terminal ID',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ss2-7bit',
    mnemonic: 'SS2-7BIT',
    syntax: 'ESC N',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 78,
    },
    locator: 'clause 8.3.141, SS2—Single Shift Two',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ss3-7bit',
    mnemonic: 'SS3-7BIT',
    syntax: 'ESC O',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 79,
    },
    locator: 'clause 8.3.142, SS3—Single Shift Three',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ls2',
    mnemonic: 'LS2',
    syntax: 'ESC n',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 110,
    },
    locator: 'clause 8.3.78, LS2—Locking Shift Two',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ls3',
    mnemonic: 'LS3',
    syntax: 'ESC o',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 111,
    },
    locator: 'clause 8.3.80, LS3—Locking Shift Three',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ls3r',
    mnemonic: 'LS3R',
    syntax: 'ESC |',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 124,
    },
    locator: 'clause 8.3.81, LS3R—Locking Shift Three Right',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ls2r',
    mnemonic: 'LS2R',
    syntax: 'ESC }',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 125,
    },
    locator: 'clause 8.3.79, LS2R—Locking Shift Two Right',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'esc',
    name: 'ls1r',
    mnemonic: 'LS1R',
    syntax: 'ESC ~',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[],
      'finalByte': 126,
    },
    locator: 'clause 8.3.77, LS1R—Locking Shift One Right',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'sl',
    mnemonic: 'SL',
    syntax: 'CSI Ps SP @',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[32],
      'finalByte': 64,
    },
    locator: 'clause 8.3.121, SL—Scroll Left',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'sr',
    mnemonic: 'SR',
    syntax: 'CSI Ps SP A',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[32],
      'finalByte': 65,
    },
    locator: 'clause 8.3.135, SR—Scroll Right',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsed',
    mnemonic: 'DECSED',
    syntax: 'CSI ? Ps J',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 74,
    },
    locator: 'Part II chapter 5, DECSED—Selective Erase in Display',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsel',
    mnemonic: 'DECSEL',
    syntax: 'CSI ? Ps K',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 75,
    },
    locator: 'Part II chapter 5, DECSEL—Selective Erase in Line',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtpushcolors',
    mnemonic: 'XTPUSHCOLORS',
    syntax: 'CSI # P',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 80,
    },
    locator: 'ctlseqs.ms, XTPUSHCOLORS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtpopcolors',
    mnemonic: 'XTPOPCOLORS',
    syntax: 'CSI # Q',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 81,
    },
    locator: 'ctlseqs.ms, XTPOPCOLORS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtreportcolors',
    mnemonic: 'XTREPORTCOLORS',
    syntax: 'CSI # R',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 82,
    },
    locator: 'ctlseqs.ms, XTREPORTCOLORS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xttitlepos',
    mnemonic: 'XTTITLEPOS',
    syntax: 'CSI # S',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 83,
    },
    locator: 'ctlseqs.ms, XTTITLEPOS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtsmgraphics',
    mnemonic: 'XTSMGRAPHICS',
    syntax: 'CSI ? Pi ; Pa ; Pv S',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 83,
    },
    locator: 'ctlseqs.ms, XTSMGRAPHICS',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decst8c',
    mnemonic: 'DECST8C',
    syntax: 'CSI ? 5 W',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 87,
    },
    locator: 'Part II chapter 5, DECST8C—Set Tab at Every Eighth Column',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'sd',
    mnemonic: 'SD',
    syntax: 'CSI Ps ^',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 94,
    },
    locator: 'clause 8.3.113, SD—Scroll Down',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'hpr',
    mnemonic: 'HPR',
    syntax: 'CSI Ps a',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 97,
    },
    locator: 'clause 8.3.59, HPR—Character Position Forward',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'rep',
    mnemonic: 'REP',
    syntax: 'CSI Ps b',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 98,
    },
    locator: 'clause 8.3.103, REP—Repeat',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'tertiary-da',
    mnemonic: 'TERTIARY-DA',
    syntax: 'CSI = Ps c',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 61,
      'intermediates': <int>[],
      'finalByte': 99,
    },
    locator: 'Part II chapter 5, DA—Tertiary Device Attributes',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'vpr',
    mnemonic: 'VPR',
    syntax: 'CSI Ps e',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 101,
    },
    locator: 'clause 8.3.160, VPR—Line Position Forward',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtfmtkeys',
    mnemonic: 'XTFMTKEYS',
    syntax: 'CSI > Pp ; Pv f',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 102,
    },
    locator: 'ctlseqs.ms, XTFMTKEYS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtqfmtkeys',
    mnemonic: 'XTQFMTKEYS',
    syntax: 'CSI ? Pp g',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 103,
    },
    locator: 'ctlseqs.ms, XTQFMTKEYS',
  ),
  _Gap(
    family: 'ecma48',
    kind: 'csi',
    name: 'mc',
    mnemonic: 'MC',
    syntax: 'CSI Ps i',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 105,
    },
    locator: 'clause 8.3.82, MC—Media Copy',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'dec-mc',
    mnemonic: 'DEC-MC',
    syntax: 'CSI ? Ps i',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 105,
    },
    locator: 'Part II chapter 5, DEC Media Copy',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtmodkeys',
    mnemonic: 'XTMODKEYS',
    syntax: 'CSI > Pp ; Pv m',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 109,
    },
    locator: 'ctlseqs.ms, XTMODKEYS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtqmodkeys',
    mnemonic: 'XTQMODKEYS',
    syntax: 'CSI ? Pp m',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 109,
    },
    locator: 'ctlseqs.ms, XTQMODKEYS',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'disable-modkeys',
    mnemonic: 'DISABLE-MODKEYS',
    syntax: 'CSI > Ps n',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 110,
    },
    locator: 'ctlseqs.ms, CSI > Ps n',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtsmpointer',
    mnemonic: 'XTSMPOINTER',
    syntax: 'CSI > Ps p',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 112,
    },
    locator: 'ctlseqs.ms, XTSMPOINTER',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decstr',
    mnemonic: 'DECSTR',
    syntax: 'CSI ! p',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[33],
      'finalByte': 112,
    },
    locator: 'Part II chapter 5, DECSTR—Soft Terminal Reset',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decscl',
    mnemonic: 'DECSCL',
    syntax: 'CSI Pl ; Pc " p',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[34],
      'finalByte': 112,
    },
    locator: 'Part II chapter 5, DECSCL—Set Conformance Level',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtpushsgr-alias',
    mnemonic: 'XTPUSHSGR-ALIAS',
    syntax: 'CSI # p',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 112,
    },
    locator: 'ctlseqs.ms, XTPUSHSGR alias',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtversion',
    mnemonic: 'XTVERSION',
    syntax: 'CSI > 0 q',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 113,
    },
    locator: 'ctlseqs.ms, XTVERSION',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decll',
    mnemonic: 'DECLL',
    syntax: 'CSI Ps q',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 113,
    },
    locator: 'Part II chapter 5, DECLL—Load LEDs',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsca',
    mnemonic: 'DECSCA',
    syntax: 'CSI Ps " q',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[34],
      'finalByte': 113,
    },
    locator: 'Part II chapter 5, DECSCA—Select Character Protection Attribute',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtpopsgr-alias',
    mnemonic: 'XTPOPSGR-ALIAS',
    syntax: 'CSI # q',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 113,
    },
    locator: 'ctlseqs.ms, XTPOPSGR alias',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtrestore',
    mnemonic: 'XTRESTORE',
    syntax: 'CSI ? Pm r',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 114,
    },
    locator: 'ctlseqs.ms, XTRESTORE',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'deccara',
    mnemonic: 'DECCARA',
    syntax: 'CSI Pt ; Pl ; Pb ; Pr ; Pm \$ r',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 114,
    },
    locator: 'Part II chapter 5, DECCARA—Change Attributes in Rectangular Area',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtshiftescape',
    mnemonic: 'XTSHIFTESCAPE',
    syntax: 'CSI > Ps s',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 115,
    },
    locator: 'ctlseqs.ms, XTSHIFTESCAPE',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtsave',
    mnemonic: 'XTSAVE',
    syntax: 'CSI ? Pm s',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 63,
      'intermediates': <int>[],
      'finalByte': 115,
    },
    locator: 'ctlseqs.ms, XTSAVE',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtsmtitle',
    mnemonic: 'XTSMTITLE',
    syntax: 'CSI > Pm t',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': 62,
      'intermediates': <int>[],
      'finalByte': 116,
    },
    locator: 'ctlseqs.ms, XTSMTITLE',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decswbv',
    mnemonic: 'DECSWBV',
    syntax: 'CSI Ps SP t',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[32],
      'finalByte': 116,
    },
    locator: 'Part II chapter 5, DECSWBV—Set Warning Bell Volume',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decrara',
    mnemonic: 'DECRARA',
    syntax: 'CSI Pt ; Pl ; Pb ; Pr ; Pm \$ t',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 116,
    },
    locator:
        'Part II chapter 5, DECRARA—Reverse Attributes in Rectangular Area',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decrqupss',
    mnemonic: 'DECRQUPSS',
    syntax: 'CSI & u',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[38],
      'finalByte': 117,
    },
    locator:
        'Part II chapter 5, DECRQUPSS—Request User Preferred Supplemental Set',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsmbv',
    mnemonic: 'DECSMBV',
    syntax: 'CSI Ps SP u',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[32],
      'finalByte': 117,
    },
    locator: 'Part II chapter 5, DECSMBV—Set Margin Bell Volume',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decrqde',
    mnemonic: 'DECRQDE',
    syntax: 'CSI " v',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[34],
      'finalByte': 118,
    },
    locator: 'Part II chapter 5, DECRQDE—Request Displayed Extent',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'deccra',
    mnemonic: 'DECCRA',
    syntax: 'CSI ... \$ v',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 118,
    },
    locator: 'Part II chapter 5, DECCRA—Copy Rectangular Area',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decrqpsr',
    mnemonic: 'DECRQPSR',
    syntax: 'CSI Ps \$ w',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 119,
    },
    locator: 'Part II chapter 5, DECRQPSR—Request Presentation State Report',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decefr',
    mnemonic: 'DECEFR',
    syntax: 'CSI Pt ; Pl ; Pb ; Pr \' w',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[39],
      'finalByte': 119,
    },
    locator: 'Part II chapter 5, DECEFR—Enable Filter Rectangle',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decreqtparm',
    mnemonic: 'DECREQTPARM',
    syntax: 'CSI Ps x',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 120,
    },
    locator: 'Part II chapter 5, DECREQTPARM—Request Terminal Parameters',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsace',
    mnemonic: 'DECSACE',
    syntax: 'CSI Ps * x',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[42],
      'finalByte': 120,
    },
    locator: 'Part II chapter 5, DECSACE—Select Attribute Change Extent',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decfra',
    mnemonic: 'DECFRA',
    syntax: 'CSI Pc ; Pt ; Pl ; Pb ; Pr \$ x',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 120,
    },
    locator: 'Part II chapter 5, DECFRA—Fill Rectangular Area',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtchecksum',
    mnemonic: 'XTCHECKSUM',
    syntax: 'CSI Ps # y',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 121,
    },
    locator: 'ctlseqs.ms, XTCHECKSUM',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decrqcra',
    mnemonic: 'DECRQCRA',
    syntax: 'CSI ... * y',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[42],
      'finalByte': 121,
    },
    locator: 'Part II chapter 5, DECRQCRA—Request Checksum of Rectangular Area',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decelr',
    mnemonic: 'DECELR',
    syntax: 'CSI Ps ; Pu \' z',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[39],
      'finalByte': 122,
    },
    locator: 'Part II chapter 5, DECELR—Enable Locator Reporting',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decera',
    mnemonic: 'DECERA',
    syntax: 'CSI Pt ; Pl ; Pb ; Pr \$ z',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 122,
    },
    locator: 'Part II chapter 5, DECERA—Erase Rectangular Area',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsle',
    mnemonic: 'DECSLE',
    syntax: 'CSI Pm \' {',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[39],
      'finalByte': 123,
    },
    locator: 'Part II chapter 5, DECSLE—Select Locator Events',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtpushsgr',
    mnemonic: 'XTPUSHSGR',
    syntax: 'CSI # {',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 123,
    },
    locator: 'ctlseqs.ms, XTPUSHSGR',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsera',
    mnemonic: 'DECSERA',
    syntax: 'CSI Pt ; Pl ; Pb ; Pr \$ {',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 123,
    },
    locator: 'Part II chapter 5, DECSERA—Selective Erase Rectangular Area',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtreportsgr',
    mnemonic: 'XTREPORTSGR',
    syntax: 'CSI Pt ; Pl ; Pb ; Pr # |',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 124,
    },
    locator: 'ctlseqs.ms, XTREPORTSGR',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decscpp',
    mnemonic: 'DECSCPP',
    syntax: 'CSI Ps \$ |',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 124,
    },
    locator: 'Part II chapter 5, DECSCPP—Select Columns Per Page',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decrqlp',
    mnemonic: 'DECRQLP',
    syntax: 'CSI Ps \' |',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[39],
      'finalByte': 124,
    },
    locator: 'Part II chapter 5, DECRQLP—Request Locator Position',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsnls',
    mnemonic: 'DECSNLS',
    syntax: 'CSI Ps * |',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[42],
      'finalByte': 124,
    },
    locator: 'Part II chapter 5, DECSNLS—Select Number of Lines per Screen',
  ),
  _Gap(
    family: 'xterm',
    kind: 'csi',
    name: 'xtpopsgr',
    mnemonic: 'XTPOPSGR',
    syntax: 'CSI # }',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[35],
      'finalByte': 125,
    },
    locator: 'ctlseqs.ms, XTPOPSGR',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decic',
    mnemonic: 'DECIC',
    syntax: 'CSI Ps \' }',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[39],
      'finalByte': 125,
    },
    locator: 'Part II chapter 5, DECIC—Insert Column',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decsasd',
    mnemonic: 'DECSASD',
    syntax: 'CSI Ps \$ }',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 125,
    },
    locator: 'Part II chapter 5, DECSASD—Select Active Status Display',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decdc',
    mnemonic: 'DECDC',
    syntax: 'CSI Ps \' ~',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[39],
      'finalByte': 126,
    },
    locator: 'Part II chapter 5, DECDC—Delete Column',
  ),
  _Gap(
    family: 'dec',
    kind: 'csi',
    name: 'decssdt',
    mnemonic: 'DECSSDT',
    syntax: 'CSI Ps \$ ~',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 126,
    },
    locator: 'Part II chapter 5, DECSSDT—Select Status Line Type',
  ),
];

const Map<int, String> _ansiModeGaps = <int, String>{
  2: 'KAM—Keyboard Action Mode',
  12: 'SRM—Send Receive Mode',
  20: 'LNM—Line Feed New Line Mode',
};

const Map<int, String> _decModeGaps = <int, String>{
  2: 'DECANM—ANSI Mode',
  3: 'DECCOLM—Column Mode',
  4: 'DECSCLM—Scrolling Mode',
  8: 'DECARM—Autorepeat Mode',
  10: 'RXVT toolbar',
  13: 'cursor blink resource',
  14: 'cursor blink XOR resource',
  18: 'DECPFF—Print Form Feed',
  19: 'DECPEX—Print Extent',
  30: 'rxvt scrollbar',
  35: 'rxvt font shifting',
  38: 'DECTEK—Tektronix Mode',
  40: 'xterm allow 80/132',
  41: 'xterm curses fix',
  42: 'DECNRCM—National Replacement Character Sets',
  43: 'DECGEPM—Graphic Expanded Print',
  44: 'xterm margin bell / DECGPCM',
  45: 'XTREVWRAP—Reverse Wraparound',
  46: 'XTLOGGING / graphic print background',
  66: 'DECNKM—Numeric Keypad Mode',
  67: 'DECBKM—Backarrow Key Mode',
  80: 'DECSDM—Sixel Display Mode',
  95: 'DECNCSM—No Clear on Column Mode',
  1001: 'xterm hilite mouse tracking',
  1007: 'xterm alternate scroll',
  1010: 'rxvt scroll on output',
  1011: 'rxvt scroll on key',
  1014: 'xterm fast scroll',
  1016: 'xterm SGR pixel mouse',
  1020: 'xterm UTF-8 resource report',
  1021: 'xterm CJK width resource report',
  1022: 'xterm emoji width resource report',
  1023: 'xterm private width resource report',
  1034: 'xterm eight-bit input',
  1035: 'xterm NumLock modifiers',
  1036: 'xterm Meta sends escape',
  1037: 'xterm Delete sends DEL',
  1039: 'xterm Alt sends escape',
  1040: 'xterm keep selection',
  1041: 'xterm select to clipboard',
  1042: 'xterm bell urgency',
  1043: 'xterm pop on bell',
  1044: 'xterm keep clipboard',
  1045: 'XTREVWRAP2—Extended Reverse Wraparound',
  1046: 'xterm alternate-screen switching permission',
  1050: 'xterm termcap function keys',
  1051: 'xterm Sun function keys',
  1052: 'xterm HP function keys',
  1053: 'xterm SCO function keys',
  1060: 'xterm legacy keyboard emulation',
  1061: 'xterm VT220 keyboard emulation',
  2001: 'xterm readline mouse button 1',
  2002: 'xterm readline mouse button 2',
  2003: 'xterm readline mouse button 3',
  2005: 'xterm readline character quoting',
  2006: 'xterm readline newline paste',
};

const List<_Gap> _dcsAndStringRecords = <_Gap>[
  _Gap(
    family: 'dec',
    kind: 'dcs',
    name: 'decudk',
    mnemonic: 'DECUDK',
    syntax: 'DCS Ps ; Ps | Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 124,
    },
    locator: 'Part II chapter 5, DECUDK—User Defined Keys',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'dec',
    kind: 'dcs',
    name: 'decaupss',
    mnemonic: 'DECAUPSS',
    syntax: 'DCS Ps ! u Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[33],
      'finalByte': 117,
    },
    locator:
        'Part II chapter 5, DECAUPSS—Assign User Preferred Supplemental Set',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'dec',
    kind: 'dcs',
    name: 'decrqss',
    mnemonic: 'DECRQSS',
    syntax: 'DCS \$ q Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 113,
    },
    locator: 'Part II chapter 5, DECRQSS—Request Selection or Setting',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'dec',
    kind: 'dcs',
    name: 'decrsps',
    mnemonic: 'DECRSPS',
    syntax: 'DCS Ps \$ t Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[36],
      'finalByte': 116,
    },
    locator: 'Part II chapter 5, DECRSPS—Restore Presentation State',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'xterm',
    kind: 'dcs',
    name: 'xtgetxres',
    mnemonic: 'XTGETXRES',
    syntax: 'DCS + Q Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[43],
      'finalByte': 81,
    },
    locator: 'ctlseqs.ms, XTGETXRES',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'xterm',
    kind: 'dcs',
    name: 'xtsettcap',
    mnemonic: 'XTSETTCAP',
    syntax: 'DCS + p Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[43],
      'finalByte': 112,
    },
    locator: 'ctlseqs.ms, XTSETTCAP',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'xterm',
    kind: 'dcs',
    name: 'sixel',
    mnemonic: 'SIXEL',
    syntax: 'DCS Ps q Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[],
      'finalByte': 113,
    },
    locator: 'ctlseqs.ms, Sixel Graphics',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'ecma48',
    kind: 'sos',
    name: 'sos',
    mnemonic: 'SOS',
    syntax: 'SOS Pt ST',
    selector: <String, Object?>{'kind': 'sos'},
    locator: 'clause 8.3.128, SOS—Start of String',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'ecma48',
    kind: 'pm',
    name: 'pm',
    mnemonic: 'PM',
    syntax: 'PM Pt ST',
    selector: <String, Object?>{'kind': 'pm'},
    locator: 'clause 8.3.94, PM—Privacy Message',
    notes: _boundedIgnoreNotes,
  ),
  _Gap(
    family: 'ecma48',
    kind: 'apc',
    name: 'apc',
    mnemonic: 'APC',
    syntax: 'APC Pt ST',
    selector: <String, Object?>{'kind': 'apc'},
    locator: 'clause 8.3.2, APC—Application Program Command',
    notes: _boundedIgnoreNotes,
  ),
];

const List<Map<String, Object?>> _sourcePins = <Map<String, Object?>>[
  <String, Object?>{
    'id': 'dec-vt510-rm-b01',
    'family': 'dec',
    'title': 'VT510 Video Terminal Programmer Information',
    'edition': 'B01, August 1995, EK-VT510-RM',
    'artifactUrl': 'https://vt100.net/mirror/mds-199909/cd3/term/vt510rmb.pdf',
    'artifactBytes': 3378497,
    'artifactSha256':
        '440bbee110eb75027a06b5b375683fbc87cb739edac32899005ad46981c7d514',
    'documentPath': null,
    'documentSha256': null,
    'retrievedOn': '2026-09-06',
  },
  <String, Object?>{
    'id': 'ecma-48-5e',
    'family': 'ecma48',
    'title': 'Control functions for coded character sets',
    'edition': 'ECMA-48, fifth edition, June 1991',
    'artifactUrl': 'https://ecma-international.org/wp-content/uploads/ECMA-48_5th_edition_june_1991.pdf',
    'artifactBytes': 1607865,
    'artifactSha256':
        '9577ad2514c411584b274ef7a4b3238c80aa93defbb349b18b8c78f78873f450',
    'documentPath': null,
    'documentSha256': null,
    'retrievedOn': '2026-09-06',
  },
  <String, Object?>{
    'id': 'iterm2-escape-codes-2026-09-07',
    'family': 'iterm2',
    'title': 'iTerm2 Proprietary Escape Codes',
    'edition': 'retrieved 2026-09-07',
    'artifactUrl': 'https://iterm2.com/documentation-escape-codes.html',
    'artifactBytes': 31258,
    'artifactSha256':
        'b297c4fcd7ea35908e145420d743fe98fc0ee5bbb5844ed4a1f35f2d547cac98',
    'documentPath': null,
    'documentSha256': null,
    'retrievedOn': '2026-09-07',
  },
  <String, Object?>{
    'id': 'xterm-411',
    'family': 'xterm',
    'title': 'XTerm Control Sequences',
    'edition': 'xterm Patch #411, 2026-08-24',
    'artifactUrl': 'https://invisible-island.net/archives/xterm/xterm-411.tgz',
    'artifactBytes': 1633400,
    'artifactSha256':
        '969be283670deadd66934865c4de6c5ab045e3a3facc2b228decf91a20d8c36c',
    'documentPath': 'xterm-411/ctlseqs.ms',
    'documentSha256':
        '69773380309da4c8b5d4ec9646eec703c47bc41db29a8efa5b94c30798c72349',
    'retrievedOn': '2026-09-06',
  },
];

String generateTerminalCompatibilityInventorySource() {
  _expectExactKeys(
    _controlMetadata.keys,
    TerminalCompatibilitySurface.controlBytes,
    'controls',
  );
  _expectExactKeys(
    _escapeMetadata.keys,
    TerminalCompatibilitySurface.escapeSelectors,
    'ESC selectors',
  );
  _expectExactKeys(
    _csiMetadata.keys,
    TerminalCompatibilitySurface.csiSelectors,
    'CSI selectors',
  );
  _expectExactKeys(
    _oscMetadata.keys,
    TerminalCompatibilitySurface.oscCommands,
    'OSC commands',
  );
  _expectExactKeys(
    _dcsMetadata.keys,
    TerminalCompatibilitySurface.dcsSelectors,
    'DCS selectors',
  );
  _expectExactKeys(
    _ansiModeMetadata.keys,
    TerminalCompatibilitySurface.ansiModes,
    'ANSI modes',
  );
  _expectExactKeys(
    _decModeMetadata.keys,
    TerminalCompatibilitySurface.decPrivateModes,
    'DEC private modes',
  );

  final List<Map<String, Object?>> records =
      <Map<String, Object?>>[
        for (final int code in TerminalCompatibilitySurface.controlBytes)
          _implementedControl(code, _controlMetadata[code]!),
        for (final int key in TerminalCompatibilitySurface.escapeSelectors)
          _implementedEscape(key, _escapeMetadata[key]!),
        for (final int key in TerminalCompatibilitySurface.csiSelectors)
          _implementedCsi(key, _csiMetadata[key]!),
        for (final int command in TerminalCompatibilitySurface.oscCommands)
          _implementedOsc(command, _oscMetadata[command]!),
        for (final int key in TerminalCompatibilitySurface.dcsSelectors)
          _implementedDcs(key, _dcsMetadata[key]!),
        for (final int mode in TerminalCompatibilitySurface.ansiModes)
          _implementedMode(mode, false, _ansiModeMetadata[mode]!),
        for (final int mode in TerminalCompatibilitySurface.decPrivateModes)
          _implementedMode(mode, true, _decModeMetadata[mode]!),
        for (final _Gap gap in _gaps) _unsupportedRecord(gap),
        for (final MapEntry<int, String> gap in _ansiModeGaps.entries)
          _unsupportedMode(gap.key, false, gap.value),
        for (final MapEntry<int, String> gap in _decModeGaps.entries)
          _unsupportedMode(gap.key, true, gap.value),
        for (final _Gap gap in _dcsAndStringRecords) _safeIgnoreRecord(gap),
      ]..sort(
        (Map<String, Object?> a, Map<String, Object?> b) =>
            (a['id']! as String).compareTo(b['id']! as String),
      );
  final Map<String, Object?> root = <String, Object?>{
    'format': 'dart-terminal-sequence-mode-inventory',
    'version': 1,
    'inventoryRevision': 2,
    'scope': 'complete-baseline',
    'sourcePins': _sourcePins,
    'records': records,
  };
  return '${const JsonEncoder.withIndent('  ').convert(root)}\n';
}

bool terminalCompatibilityInventoryIsFresh(File output) =>
    output.existsSync() &&
    output.readAsStringSync() == generateTerminalCompatibilityInventorySource();

Map<String, Object?> _implementedControl(
  int code,
  _Metadata metadata,
) => _record(
  metadata: metadata,
  kind: code <= 0x1f ? 'c0' : 'c1',
  syntax:
      '${metadata.mnemonic} (0x${code.toRadixString(16).padLeft(2, '0').toUpperCase()})',
  selector: <String, Object?>{'kind': code <= 0x1f ? 'c0' : 'c1', 'code': code},
);

Map<String, Object?> _implementedEscape(int key, _Metadata metadata) {
  final int count = (key >> 16) & 0xff;
  final int intermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  return _record(
    metadata: metadata,
    kind: 'esc',
    syntax:
        'ESC ${count == 1 ? '${_intermediateName(intermediate)} ' : ''}${String.fromCharCode(finalByte)}',
    selector: <String, Object?>{
      'kind': 'esc',
      'intermediates': <int>[if (count == 1) intermediate],
      'finalByte': finalByte,
    },
  );
}

Map<String, Object?> _implementedCsi(int key, _Metadata metadata) {
  final int marker = (key >> 24) & 0xff;
  final int count = (key >> 16) & 0xff;
  final int intermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  return _record(
    metadata: metadata,
    kind: 'csi',
    syntax:
        'CSI ${marker == 0 ? '' : '${String.fromCharCode(marker)} '}${count == 1 ? '${_intermediateName(intermediate)} ' : ''}${String.fromCharCode(finalByte)}',
    selector: <String, Object?>{
      'kind': 'csi',
      'privateMarker': marker == 0 ? null : marker,
      'intermediates': <int>[if (count == 1) intermediate],
      'finalByte': finalByte,
    },
  );
}

Map<String, Object?> _implementedOsc(int command, _Metadata metadata) =>
    _record(
      metadata: metadata,
      kind: 'osc',
      syntax: command == 52 ? 'OSC 52 ; Pc ; Pd ST' : 'OSC $command ; Pt ST',
      selector: <String, Object?>{'kind': 'osc', 'command': command},
    );

Map<String, Object?> _implementedDcs(int key, _Metadata metadata) {
  final int count = (key >> 16) & 0xff;
  final int intermediate = (key >> 8) & 0xff;
  final int finalByte = key & 0xff;
  return _record(
    metadata: metadata,
    kind: 'dcs',
    syntax:
        'DCS ${count == 1 ? '${_intermediateName(intermediate)} ' : ''}${String.fromCharCode(finalByte)} Pt ST',
    selector: <String, Object?>{
      'kind': 'dcs',
      'privateMarker': null,
      'intermediates': <int>[if (count == 1) intermediate],
      'finalByte': finalByte,
    },
  );
}

Map<String, Object?> _implementedMode(
  int mode,
  bool decPrivate,
  _Metadata metadata,
) => _record(
  metadata: metadata,
  kind: 'mode',
  syntax:
      'CSI ${decPrivate ? '? ' : ''}$mode h / CSI ${decPrivate ? '? ' : ''}$mode l',
  selector: <String, Object?>{
    'kind': 'mode',
    'private': decPrivate,
    'number': mode,
  },
);

Map<String, Object?> _record({
  required _Metadata metadata,
  required String kind,
  required String syntax,
  required Map<String, Object?> selector,
}) => <String, Object?>{
  'id': '${metadata.family}:$kind:${metadata.name}',
  'mnemonic': metadata.mnemonic,
  'syntax': syntax,
  'selector': selector,
  'support': metadata.support,
  'disposition': metadata.reply ? 'reply' : 'execute',
  'sourceRefs': <Map<String, Object?>>[
    <String, Object?>{
      'source': _sourceId(metadata.family),
      'locator': metadata.locator,
    },
  ],
  'implementationEvidence': <String>[_implementationEvidence],
  'testEvidence': <String>[_implementationTestEvidence],
  'notes': metadata.notes,
};

Map<String, Object?> _unsupportedRecord(_Gap gap) => <String, Object?>{
  'id': '${gap.family}:${gap.kind}:${gap.name}',
  'mnemonic': gap.mnemonic,
  'syntax': gap.syntax,
  'selector': gap.selector,
  'support': 'unsupported',
  'disposition': 'reject',
  'sourceRefs': <Map<String, Object?>>[
    <String, Object?>{'source': _sourceId(gap.family), 'locator': gap.locator},
  ],
  'implementationEvidence': <String>[],
  'testEvidence': <String>[],
  'notes': gap.notes,
};

Map<String, Object?> _safeIgnoreRecord(_Gap gap) => <String, Object?>{
  'id': '${gap.family}:${gap.kind}:${gap.name}',
  'mnemonic': gap.mnemonic,
  'syntax': gap.syntax,
  'selector': gap.selector,
  'support': 'safe-ignore',
  'disposition': 'ignore',
  'sourceRefs': <Map<String, Object?>>[
    <String, Object?>{'source': _sourceId(gap.family), 'locator': gap.locator},
  ],
  'implementationEvidence': <String>[_implementationEvidence],
  'testEvidence': <String>[_implementationTestEvidence],
  'notes': gap.notes,
};

Map<String, Object?> _unsupportedMode(
  int mode,
  bool decPrivate,
  String description,
) {
  final String mnemonic = description
      .split('—')
      .first
      .toUpperCase()
      .replaceAll(RegExp('[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final String name = mnemonic.toLowerCase();
  return <String, Object?>{
    'id': 'xterm:mode:$name',
    'mnemonic': mnemonic,
    'syntax':
        'CSI ${decPrivate ? '? ' : ''}$mode h / CSI ${decPrivate ? '? ' : ''}$mode l',
    'selector': <String, Object?>{
      'kind': 'mode',
      'private': decPrivate,
      'number': mode,
    },
    'support': 'unsupported',
    'disposition': 'reject',
    'sourceRefs': <Map<String, Object?>>[
      <String, Object?>{
        'source': 'xterm-411',
        'locator':
            'ctlseqs.ms, ${decPrivate ? 'DEC private ' : 'ANSI '}mode $mode—$description',
      },
    ],
    'implementationEvidence': <String>[],
    'testEvidence': <String>[],
    'notes': _unsupportedNotes,
  };
}

String _sourceId(String family) => switch (family) {
  'dec' => 'dec-vt510-rm-b01',
  'ecma48' => 'ecma-48-5e',
  'iterm2' => 'iterm2-escape-codes-2026-09-07',
  'xterm' => 'xterm-411',
  _ => throw StateError('unknown source family $family'),
};

String _intermediateName(int byte) =>
    byte == 0x20 ? 'SP' : String.fromCharCode(byte);

void _expectExactKeys(Iterable<int> actual, List<int> expected, String name) {
  final Set<int> actualSet = actual.toSet();
  final Set<int> expectedSet = expected.toSet();
  if (actualSet.length != expectedSet.length ||
      !actualSet.containsAll(expectedSet))
    throw StateError('$name metadata does not match product declarations');
}

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln(
      'TERMINAL_COMPATIBILITY_INVENTORY_GENERATOR_FAIL usage: dart run tool/generate_terminal_compatibility_inventory.dart [--check]',
    );
    exitCode = 64;
    return;
  }
  final Directory root = File.fromUri(Platform.script).absolute.parent.parent;
  final File output = File.fromUri(
    root.uri.resolve(defaultGeneratedTerminalCompatibilityInventoryPath),
  );
  if (arguments.isNotEmpty) {
    if (!terminalCompatibilityInventoryIsFresh(output)) {
      stderr.writeln(
        'TERMINAL_COMPATIBILITY_INVENTORY_STALE path=$defaultGeneratedTerminalCompatibilityInventoryPath',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'TERMINAL_COMPATIBILITY_INVENTORY_GENERATED_CHECK_PASS path=$defaultGeneratedTerminalCompatibilityInventoryPath',
    );
    return;
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(generateTerminalCompatibilityInventorySource());
  stdout.writeln(
    'TERMINAL_COMPATIBILITY_INVENTORY_GENERATED path=$defaultGeneratedTerminalCompatibilityInventoryPath',
  );
}
