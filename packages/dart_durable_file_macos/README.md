# dart_durable_file_macos

A path-agnostic macOS capability for bounded durable regular-file operations.
Callers inject an absolute directory, bounded safe UTF-8 leaf names, and bytes. The package
owns descriptor-relative type/owner/link checks, caller-selected directory
permission handling, 0600 file permission narrowing,
an advisory exclusive lock, bounded reads, exclusive temporary writes, rename,
unlink, and directory `fsync`.

The package does not define an application location, schema, recovery policy, or
user-facing diagnostics. Failures are fixed classifications and never retain a
path or file content.
