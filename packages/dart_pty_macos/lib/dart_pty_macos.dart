/// A bounded asynchronous macOS PTY/process API.
library;

export 'src/api.dart';
export 'src/native_backend.dart' show MacosPtyBackend, startPty;
