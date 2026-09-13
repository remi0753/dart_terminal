import 'dart:io';

import 'package:dart_process_resource_macos/dart_process_resource_macos.dart';

void main() {
  final MacosCurrentProcessResourceSampler sampler =
      MacosCurrentProcessResourceSampler();
  final int descriptorBaseline = sampler.openFileDescriptorCount();
  final RandomAccessFile descriptor = File('/dev/null').openSync();
  final int descriptorOpen = sampler.openFileDescriptorCount();
  descriptor.closeSync();
  final int descriptorClosed = sampler.openFileDescriptorCount();
  _expect(
    descriptorOpen == descriptorBaseline + 1 &&
        descriptorClosed == descriptorBaseline,
    'descriptor count observes one exact open and close',
  );

  final MacosCurrentProcessResourceSnapshot before = sampler.snapshot();
  var accumulator = 0;
  for (var index = 0; index < 1000000; index++) {
    accumulator = (accumulator + index) & 0x7fffffff;
  }
  final MacosCurrentProcessResourceSnapshot after = sampler.snapshot();
  _expect(
    accumulator != -1 &&
        after.cpuTimeMicroseconds >= before.cpuTimeMicroseconds &&
        after.currentResidentBytes > 0 &&
        after.peakResidentBytes >= after.currentResidentBytes,
    'resource snapshot is positive and monotonic',
  );
  stdout.writeln(
    'DART_PROCESS_RESOURCE_MACOS_PASS descriptors=true cpu=true rss=true '
    'content_free=true',
  );
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('Expectation failed: $description');
}
