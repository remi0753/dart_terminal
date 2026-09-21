# dart_system_entropy_macos

A small macOS-only Dart package for bounded cryptographically secure random
bytes. The package owns the `arc4random_buf` FFI boundary and returns immutable
byte lists. It has no application identity, persistence, UI, or identifier
policy.
