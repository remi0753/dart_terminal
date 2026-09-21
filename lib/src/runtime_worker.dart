import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'runtime_image_worker.dart';
import 'runtime_image_worker_protocol.dart';
import 'runtime_lifecycle.dart';
import 'runtime_worker_protocol.dart';
import 'terminal_note_store_process.dart';

Future<void> runRuntimeLifecycleWorkerProcess(List<String> arguments) async {
  RuntimeLifecycleScenario? scenario;
  int? generation;
  for (final String argument in arguments) {
    if (argument.startsWith('--scenario=')) {
      if (scenario != null) {
        throw const FormatException('--scenario may be supplied only once');
      }
      scenario = RuntimeLifecycleScenario.byName(
        argument.substring('--scenario='.length),
      );
      if (scenario == null) {
        throw FormatException('unknown worker scenario: $argument');
      }
      continue;
    }
    if (argument.startsWith('--generation=')) {
      if (generation != null) {
        throw const FormatException('--generation may be supplied only once');
      }
      generation = int.tryParse(argument.substring('--generation='.length));
      if (generation == null || generation <= 0 || generation > 0xffffffff) {
        throw FormatException('invalid worker generation: $argument');
      }
      continue;
    }
    throw FormatException('unknown worker argument: $argument');
  }
  if (scenario == null || generation == null) {
    throw const FormatException('worker scenario and generation are required');
  }
  if (scenario == RuntimeLifecycleScenario.rootStartupFailure ||
      scenario == RuntimeLifecycleScenario.rootUncaught) {
    throw FormatException('root-only scenario cannot run in worker: $scenario');
  }
  if (scenario == RuntimeLifecycleScenario.workerStartupFailure) {
    throw StateError('requested lifecycle worker startup failure');
  }

  final RuntimeWorkerFrameDecoder decoder = RuntimeWorkerFrameDecoder(stdin);
  final RuntimeWorkerFrameWriter writer = RuntimeWorkerFrameWriter(stdout);
  final RuntimeImageWorkerService imageWorker = RuntimeImageWorkerService();
  final TerminalNoteStoreProcessWorkerService noteStoreWorker =
      TerminalNoteStoreProcessWorkerService();
  Timer? idleAction;
  Future<void>? lateResponse;
  try {
    await writer.send(
      RuntimeWorkerFrame(
        type: RuntimeWorkerMessageType.ready,
        generation: generation,
        operation: 0,
        payload: RuntimeWorkerFrameCodec.int64Payload(pid),
      ),
    );
    if (scenario == RuntimeLifecycleScenario.workerIdleUncaught) {
      idleAction = Timer(const Duration(milliseconds: 35), () {
        throw StateError('requested idle worker failure');
      });
    } else if (scenario == RuntimeLifecycleScenario.workerIdleExit) {
      idleAction = Timer(const Duration(milliseconds: 35), () => exit(0));
    }

    await for (final RuntimeWorkerFrame frame in decoder.frames) {
      if (frame.generation != generation) {
        throw FormatException(
          'parent generation ${frame.generation} != $generation',
        );
      }
      switch (frame.type) {
        case RuntimeWorkerMessageType.request:
          if (frame.operation == 0) {
            throw const FormatException('request operation must be nonzero');
          }
          if (scenario == RuntimeLifecycleScenario.workerSyncUncaught) {
            throw StateError('requested synchronous worker failure');
          }
          if (scenario == RuntimeLifecycleScenario.workerAsyncUncaught) {
            await Future<void>.delayed(Duration.zero);
            throw StateError('requested asynchronous worker failure');
          }
          if (scenario == RuntimeLifecycleScenario.workerUnexpectedExit) {
            exit(0);
          }
          if (scenario == RuntimeLifecycleScenario.workerTraffic) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          final Uint8List responsePayload;
          if (RuntimeImageWorkerRequestCodec.hasMagic(frame.payload)) {
            responsePayload = imageWorker.handle(frame.payload);
          } else if (TerminalNoteStoreProcessProtocol.hasMagic(frame.payload)) {
            responsePayload = noteStoreWorker.handle(frame.payload);
          } else {
            final int value = RuntimeWorkerFrameCodec.readInt64Payload(frame);
            responsePayload = RuntimeWorkerFrameCodec.int64Payload(value + 1);
          }
          final RuntimeWorkerFrame response = RuntimeWorkerFrame(
            type: RuntimeWorkerMessageType.response,
            generation: generation,
            operation: frame.operation,
            payload: responsePayload,
          );
          if (scenario == RuntimeLifecycleScenario.lateCompletion) {
            lateResponse = Future<void>.delayed(
              const Duration(milliseconds: 35),
              () => writer.send(response),
            );
          } else {
            await writer.send(response);
          }
          break;
        case RuntimeWorkerMessageType.stop:
          if (frame.operation != 0 || frame.payload.isNotEmpty) {
            throw const FormatException('invalid stop frame');
          }
          if (scenario == RuntimeLifecycleScenario.shutdownTimeout) {
            await Completer<void>().future;
          }
          if (scenario == RuntimeLifecycleScenario.workerStopUncaught) {
            throw StateError('requested worker failure while stopping');
          }
          imageWorker.dispose();
          noteStoreWorker.dispose();
          await writer.send(
            RuntimeWorkerFrame(
              type: RuntimeWorkerMessageType.stopAcknowledged,
              generation: generation,
              operation: 0,
              payload: Uint8List(0),
            ),
          );
          if (scenario == RuntimeLifecycleScenario.lateCompletion) {
            await Future<void>.delayed(const Duration(milliseconds: 70));
            await lateResponse;
          }
          return;
        case RuntimeWorkerMessageType.ready:
        case RuntimeWorkerMessageType.response:
        case RuntimeWorkerMessageType.stopAcknowledged:
          throw FormatException(
            'parent sent worker-only frame ${frame.type.name}',
          );
      }
    }
  } finally {
    imageWorker.dispose();
    noteStoreWorker.dispose();
    idleAction?.cancel();
    await decoder.cancel();
    await stdout.flush();
  }
}
