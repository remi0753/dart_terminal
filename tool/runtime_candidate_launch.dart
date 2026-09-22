/// Rejects any app outside the canonical runtime build root.
///
/// Resolve symlinks for both arguments before calling this function, so a
/// build-directory alias cannot point at an installed app.
String requireRuntimeBuildCandidatePath({
  required String canonicalBundlePath,
  required String canonicalBuildRoot,
}) {
  final String prefix = canonicalBuildRoot.endsWith('/')
      ? canonicalBuildRoot
      : '$canonicalBuildRoot/';
  if (!canonicalBundlePath.startsWith(prefix) ||
      !canonicalBundlePath.endsWith('.app')) {
    throw ArgumentError.value(
      canonicalBundlePath,
      'canonicalBundlePath',
      'an app inside the runtime build root',
    );
  }
  return canonicalBundlePath;
}

/// Builds a Launch Services invocation for one validated build candidate.
///
/// The app path is positional and absolute. A bundle-ID lookup could instead
/// select a separately installed copy with the same identifier.
List<String> runtimeCandidateOpenArguments({
  required String bundlePath,
  required String stdoutPath,
  required String stderrPath,
  required Map<String, String> environment,
  required List<String> applicationArguments,
  String? architecture,
}) {
  if (!bundlePath.startsWith('/') || !bundlePath.endsWith('.app')) {
    throw ArgumentError.value(bundlePath, 'bundlePath', 'absolute .app path');
  }
  return <String>[
    '-W',
    '-n',
    '-F',
    if (architecture != null) ...<String>['--arch', architecture],
    '-o',
    stdoutPath,
    '--stderr',
    stderrPath,
    for (final MapEntry<String, String> value
        in environment.entries) ...<String>[
      '--env',
      '${value.key}=${value.value}',
    ],
    bundlePath,
    '--args',
    ...applicationArguments,
  ];
}
