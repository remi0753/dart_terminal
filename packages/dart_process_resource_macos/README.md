# dart_process_resource_macos

A small macOS-only Dart package for content-free current-process resource
sampling. It reports monotonic CPU time, current and peak resident bytes, and
an aggregate open-file-descriptor count. It does not retain descriptor
identities, process IDs, commands, paths, environment, or application data.
