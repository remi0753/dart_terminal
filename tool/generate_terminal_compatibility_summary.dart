import 'dart:io';

import 'terminal_compatibility_inventory.dart';

const String defaultTerminalCompatibilitySummaryPath =
    'docs/phase6/sequence-mode-support.md';

String generateTerminalCompatibilitySummary(
  TerminalCompatibilityInventory inventory,
) {
  final Map<TerminalCompatibilitySupport, int> support =
      inventory.supportCounts;
  final Map<TerminalCompatibilitySelectorKind, int> kinds =
      inventory.selectorKindCounts;
  final int productRecords =
      support[TerminalCompatibilitySupport.implemented]! +
      support[TerminalCompatibilitySupport.partial]!;
  final int productModes = inventory.records
      .where(
        (TerminalCompatibilityRecord record) =>
            record.selector.kind == TerminalCompatibilitySelectorKind.mode &&
            (record.support == TerminalCompatibilitySupport.implemented ||
                record.support == TerminalCompatibilitySupport.partial),
      )
      .length;
  final int productSelectors = productRecords - productModes;
  final int safeIgnoreDcs = inventory.records
      .where(
        (TerminalCompatibilityRecord record) =>
            record.selector.kind == TerminalCompatibilitySelectorKind.dcs &&
            record.support == TerminalCompatibilitySupport.safeIgnore,
      )
      .length;
  final StringBuffer output = StringBuffer()
    ..writeln('# Terminal sequence and mode support baseline')
    ..writeln()
    ..writeln(
      'Generated from `compatibility/sequence_mode_inventory.json` revision '
      '${inventory.inventoryRevision}. Do not edit this summary by hand.',
    )
    ..writeln()
    ..writeln('## Reviewed boundary')
    ..writeln()
    ..writeln(
      'This is a host-to-terminal compatibility baseline, not a claim to '
      'implement every function ever assigned by ECMA or every hardware '
      'option in a VT510. It includes:',
    )
    ..writeln()
    ..writeln(
      '- every selector and mode in the product-code implementation surface;',
    )
    ..writeln(
      '- terminal-display ECMA-48 controls for cursor movement, editing, '
      'erasure, scrolling, rendition, modes, tabulation, and status;',
    )
    ..writeln(
      '- DEC VT100–VT510 controls relevant to screen/cursor/margin/mode, '
      'character-set, rectangle, locator, and status behavior;',
    )
    ..writeln(
      '- every DEC-private mode number listed by xterm Patch #411, plus its '
      'high-use CSI, DCS, OSC, mouse, title, palette, and clipboard families;',
    )
    ..writeln(
      '- iTerm2 OSC 7 current-directory and OSC 8 hyperlink extensions because '
      'they are part of the current/later product contract.',
    )
    ..writeln()
    ..writeln(
      'Excluded from this bounded baseline are ECMA transmission controls and '
      'paged-media/typesetting functions without modern terminal application '
      'meaning; exhaustive ISO-2022 national replacement-set final-byte '
      'variants beyond ASCII and DEC line drawing; physical printer/modem '
      'parameter variants; Tektronix command details; terminal-to-host keyboard '
      'output; and Kitty/Ghostty-only protocols assigned to later roadmap '
      'tasks. An exclusion is not silently supported.',
    )
    ..writeln()
    ..writeln('## Pinned sources')
    ..writeln()
    ..writeln('| Source | Family | Edition | Exact artifact |')
    ..writeln('| --- | --- | --- | --- |');
  for (final TerminalCompatibilitySourcePin pin in inventory.sourcePins) {
    output.writeln(
      '| `${pin.id}` | `${pin.family.name}` | ${_cell(pin.edition)} | '
      '${pin.artifactBytes} bytes, `${pin.artifactSha256}` |',
    );
  }
  output
    ..writeln()
    ..writeln(
      'Full URLs, inner-document hashes, and citation rules are in '
      '[`specification-source-pins.md`](specification-source-pins.md).',
    )
    ..writeln()
    ..writeln('## Coverage totals')
    ..writeln()
    ..writeln('| Support classification | Records |')
    ..writeln('| --- | ---: |');
  for (final TerminalCompatibilitySupport value
      in TerminalCompatibilitySupport.values) {
    output.writeln('| `${_supportName(value)}` | ${support[value]} |');
  }
  output
    ..writeln('| **Total** | **${inventory.records.length}** |')
    ..writeln()
    ..writeln('| Selector kind | Records |')
    ..writeln('| --- | ---: |');
  for (final TerminalCompatibilitySelectorKind kind
      in TerminalCompatibilitySelectorKind.values) {
    output.writeln('| `${kind.name}` | ${kinds[kind]} |');
  }
  output
    ..writeln('| **Total** | **${inventory.records.length}** |')
    ..writeln()
    ..writeln(
      'The ${support[TerminalCompatibilitySupport.implemented]} implemented '
      'plus ${support[TerminalCompatibilitySupport.partial]} partial records '
      'reconcile exactly to all $productRecords product declarations '
      '($productSelectors sequence selectors and $productModes modes). The '
      '${support[TerminalCompatibilitySupport.safeIgnore]} safe-ignore records '
      'cover $safeIgnoreDcs concrete DCS forms and SOS/PM/APC; all '
      '${support[TerminalCompatibilitySupport.unsupported]} remaining records '
      'are explicitly unsupported/rejected.',
    )
    ..writeln()
    ..writeln('## Partial implementation limits')
    ..writeln()
    ..writeln('| ID | Syntax | Reviewed limit |')
    ..writeln('| --- | --- | --- |');
  for (final TerminalCompatibilityRecord record in inventory.records.where(
    (TerminalCompatibilityRecord record) =>
        record.support == TerminalCompatibilitySupport.partial,
  )) {
    output.writeln(
      '| `${record.id}` | `${_cell(record.syntax)}` | ${_cell(record.notes)} |',
    );
  }
  output
    ..writeln()
    ..writeln('## Bounded safe-ignore controls')
    ..writeln()
    ..writeln('| ID | Syntax |')
    ..writeln('| --- | --- |');
  for (final TerminalCompatibilityRecord record in inventory.records.where(
    (TerminalCompatibilityRecord record) =>
        record.support == TerminalCompatibilitySupport.safeIgnore,
  )) {
    output.writeln('| `${record.id}` | `${_cell(record.syntax)}` |');
  }
  output
    ..writeln()
    ..writeln('## Gap ownership')
    ..writeln()
    ..writeln(
      '- The next black-box differential and real-application matrix tasks '
      'decide which generic ECMA/DEC/xterm gaps become implementation work.',
    )
    ..writeln(
      '- The later focus/mouse/query task owns focus mode 1004, SGR pixel mouse '
      '1016, and remaining report behavior.',
    )
    ..writeln(
      '- The OSC policy task has implemented title commands 0/1/2, cwd '
      'command 7, and cursor color 12/112; its remaining gap is the '
      'security-sensitive clipboard command 52.',
    )
    ..writeln(
      '- The terminfo task owns remaining XTSETTCAP decisions; the existing '
      '`v1 保留` feature-matrix decision continues to own Sixel.',
    )
    ..writeln(
      '- Unsupported extended character-set, rectangular-editing, locator, printer, '
      'and terminal-local xterm resource controls stay rejected until '
      'differential/application evidence justifies a new ordered task.',
    )
    ..writeln()
    ..writeln('## Review acceptance')
    ..writeln()
    ..writeln(
      '- Inventory IDs/selectors are sorted and unique, source references are '
      'pinned, and implemented/partial records have code and test evidence.',
    )
    ..writeln(
      '- Product declarations and inventory support records reconcile '
      'byte-for-byte by canonical selector key.',
    )
    ..writeln(
      '- Every in-scope non-implementation is either bounded safe-ignore or '
      'explicit unsupported/reject with a disposition note.',
    )
    ..writeln(
      '- The JSON inventory is the review authority; this generated summary '
      'and `FEATURE_MATRIX.md` are navigation views.',
    );
  return output.toString();
}

bool terminalCompatibilitySummaryIsFresh(
  File output,
  TerminalCompatibilityInventory inventory,
) =>
    output.existsSync() &&
    output.readAsStringSync() ==
        generateTerminalCompatibilitySummary(inventory);

String _supportName(TerminalCompatibilitySupport support) => switch (support) {
  TerminalCompatibilitySupport.implemented => 'implemented',
  TerminalCompatibilitySupport.partial => 'partial',
  TerminalCompatibilitySupport.safeIgnore => 'safe-ignore',
  TerminalCompatibilitySupport.unsupported => 'unsupported',
};

String _cell(String value) =>
    value.replaceAll('|', r'\|').replaceAll('\n', ' ');

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln(
      'TERMINAL_COMPATIBILITY_SUMMARY_FAIL usage: '
      'dart run tool/generate_terminal_compatibility_summary.dart [--check]',
    );
    exitCode = 64;
    return;
  }
  final Directory repositoryRoot = File.fromUri(Platform.script)
      .absolute
      .parent
      .parent;
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File.fromUri(
          repositoryRoot.uri.resolve(defaultTerminalCompatibilityInventoryPath),
        ),
        repositoryRoot: repositoryRoot,
      );
  inventory.reconcileImplementationSurface(
    File.fromUri(
      repositoryRoot.uri.resolve(defaultTerminalImplementationSurfacePath),
    ),
  );
  final File output = File.fromUri(
    repositoryRoot.uri.resolve(defaultTerminalCompatibilitySummaryPath),
  );
  if (arguments.isNotEmpty) {
    if (!terminalCompatibilitySummaryIsFresh(output, inventory)) {
      stderr.writeln(
        'TERMINAL_COMPATIBILITY_SUMMARY_STALE '
        'path=$defaultTerminalCompatibilitySummaryPath',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'TERMINAL_COMPATIBILITY_SUMMARY_CHECK_PASS '
      'path=$defaultTerminalCompatibilitySummaryPath',
    );
    return;
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(generateTerminalCompatibilitySummary(inventory));
  stdout.writeln(
    'TERMINAL_COMPATIBILITY_SUMMARY_GENERATED '
    'path=$defaultTerminalCompatibilitySummaryPath',
  );
}
