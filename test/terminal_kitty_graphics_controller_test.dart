import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/src/runtime_image_worker.dart';
import 'package:dart_terminal/src/runtime_image_worker_protocol.dart';
import 'package:dart_terminal/src/runtime_lifecycle.dart';
import 'package:dart_terminal/src/terminal_core/terminal_kitty_graphics.dart';
import 'package:dart_terminal/src/terminal_core/terminal_kitty_image_store.dart';
import 'package:dart_terminal/src/terminal_core/terminal_screen_set.dart';
import 'package:dart_terminal/src/terminal_kitty_graphics_controller.dart';
import 'package:dart_terminal/src/terminal_pane.dart';
import 'package:dart_terminal/src/terminal_session.dart';

Future<void> main() => runTerminalKittyGraphicsControllerTests();

Future<void> runTerminalKittyGraphicsControllerTests() async {
  _testStoreIdentityCopiesReplacementAndCaps();
  _testPlacementStoreGeometryIdentityAndDeletion();
  _testEveryStaticDeleteSelector();
  await _testControllerQueryStorageMultipartAndRejection();
  await _testControllerStorageCapQueueCapAndStaleWorker();
  await _testControllerPlacementActionsAndDelete();
  await _testControllerFailureReplyAndPendingTeardown();
  await _testSessionParserAndReplyFifo();
  await _testRealWorkerSessionRoundTripAndTeardown();
}

void _testStoreIdentityCopiesReplacementAndCaps() {
  final TerminalKittyImageStore store = TerminalKittyImageStore(
    maximumImages: 3,
    maximumRetainedBytes: 12,
  );
  final Uint8List firstBytes = Uint8List.fromList(const <int>[1, 2, 3, 4]);
  final TerminalKittyImage first = store
      .store(
        imageId: 7,
        imageNumber: 0,
        width: 1,
        height: 1,
        transient: false,
        rgba: firstBytes,
      )
      .image!;
  firstBytes[0] = 99;
  _expectInts(first.copyRgba(), const <int>[1, 2, 3, 4], 'store owns RGBA');
  final Uint8List copied = first.copyRgba()..[1] = 88;
  _expect(
    copied[1] == 88 && first.copyRgba()[1] == 2,
    'image access returns an independent RGBA copy',
  );

  final TerminalKittyImage replacement = store
      .store(
        imageId: 7,
        imageNumber: 0,
        width: 1,
        height: 1,
        transient: true,
        rgba: Uint8List.fromList(const <int>[5, 6, 7, 8]),
      )
      .image!;
  _expect(
    store.length == 1 &&
        store.retainedBytes == 4 &&
        replacement.resourceGeneration > first.resourceGeneration &&
        replacement.transient,
    'explicit ID replacement is atomic and receives a fresh generation',
  );

  final TerminalKittyImage numberedFirst = store
      .store(
        imageId: 0,
        imageNumber: 13,
        width: 1,
        height: 1,
        transient: false,
        rgba: Uint8List.fromList(const <int>[9, 10, 11, 12]),
      )
      .image!;
  final TerminalKittyImage numberedSecond = store
      .store(
        imageId: 0,
        imageNumber: 13,
        width: 1,
        height: 1,
        transient: false,
        rgba: Uint8List.fromList(const <int>[13, 14, 15, 16]),
      )
      .image!;
  _expect(
    numberedFirst.id != numberedSecond.id &&
        identical(store.newestImageByNumber(13), numberedSecond),
    'image numbers allocate unique IDs and resolve newest-first',
  );

  final TerminalKittyImageStoreResult rejected = store.store(
    imageId: 7,
    imageNumber: 0,
    width: 2,
    height: 1,
    transient: false,
    rgba: Uint8List.fromList(const <int>[1, 2, 3, 4, 5, 6, 7, 8]),
  );
  _expect(
    rejected.disposition == TerminalKittyImageStoreDisposition.resourceLimit &&
        identical(store.imageById(7), replacement) &&
        store.retainedBytes == 12,
    'rejected replacement preserves the existing image and accounting',
  );
  store.clear();
  _expect(
    store.isEmpty && store.retainedBytes == 0,
    'store clear releases every retained byte',
  );
}

void _testPlacementStoreGeometryIdentityAndDeletion() {
  final TerminalKittyImageStore store = TerminalKittyImageStore(
    maximumImages: 4,
    maximumPlacements: 2,
    maximumRetainedBytes: 128,
  );
  final TerminalKittyImage image = store
      .store(
        imageId: 1,
        imageNumber: 0,
        width: 4,
        height: 2,
        transient: false,
        rgba: Uint8List(32),
      )
      .image!;
  final TerminalKittyImagePlacement first = store
      .place(
        imageId: 1,
        imageNumber: 0,
        placementId: 7,
        logicalLineId: 10,
        logicalLineEpoch: 1,
        logicalCellOffset: 3,
        sourceX: 1,
        sourceY: 0,
        sourceWidth: 0,
        sourceHeight: 0,
        cellOffsetX: 9,
        cellOffsetY: 19,
        columns: 2,
        rows: 0,
        z: -2,
      )
      .placement!;
  final TerminalKittyImagePlacementGeometry geometry = first.geometry(
    image: image,
    cellWidth: 10,
    cellHeight: 20,
  );
  _expect(
    geometry.source.x == 1 &&
        geometry.source.width == 3 &&
        geometry.pixelWidth == 11 &&
        geometry.pixelHeight == 7 &&
        geometry.columns == 2 &&
        geometry.rows == 2,
    'placement geometry intersects crop and preserves aspect ratio',
  );

  final TerminalKittyImagePlacement replacement = store
      .place(
        imageId: 1,
        imageNumber: 0,
        placementId: 7,
        logicalLineId: 11,
        logicalLineEpoch: 1,
        logicalCellOffset: 4,
        sourceX: 0,
        sourceY: 0,
        sourceWidth: 0,
        sourceHeight: 0,
        cellOffsetX: 0,
        cellOffsetY: 0,
        columns: 1,
        rows: 1,
        z: 3,
      )
      .placement!;
  _expect(
    store.placementCount == 1 &&
        replacement.placementGeneration > first.placementGeneration,
    'explicit placement identity replaces atomically with a fresh generation',
  );
  store.place(
    imageId: 1,
    imageNumber: 0,
    placementId: 0,
    logicalLineId: 12,
    logicalLineEpoch: 1,
    logicalCellOffset: 5,
    sourceX: 0,
    sourceY: 0,
    sourceWidth: 0,
    sourceHeight: 0,
    cellOffsetX: 0,
    cellOffsetY: 0,
    columns: 1,
    rows: 1,
    z: 0,
  );
  final TerminalKittyImagePlacementResult capped = store.place(
    imageId: 1,
    imageNumber: 0,
    placementId: 0,
    logicalLineId: 13,
    logicalLineEpoch: 1,
    logicalCellOffset: 6,
    sourceX: 0,
    sourceY: 0,
    sourceWidth: 0,
    sourceHeight: 0,
    cellOffsetX: 0,
    cellOffsetY: 0,
    columns: 1,
    rows: 1,
    z: 0,
  );
  _expect(
    capped.disposition ==
            TerminalKittyImagePlacementDisposition.resourceLimit &&
        store.placementCount == 2,
    'anonymous placement admission rejects beyond the independent cap',
  );

  final TerminalKittyImageDeleteResult lower = store.delete(
    deletion: _command('Ga=d,d=i,i=1,p=7').deletion,
    cursorRow: 0,
    cursorColumn: 0,
    screenRows: 4,
    screenColumns: 4,
    cellWidth: 10,
    cellHeight: 20,
    resolvePosition: (TerminalKittyImagePlacement placement) =>
        TerminalKittyImagePlacementPosition(
          row: placement.logicalLineId - 11,
          column: 0,
        ),
  );
  _expect(
    lower.deletedPlacements == 1 &&
        lower.deletedImages == 0 &&
        store.imageById(1) != null,
    'lowercase identified delete removes placement but retains image data',
  );
  final TerminalKittyImageDeleteResult upper = store.delete(
    deletion: _command('Ga=d,d=P,x=1,y=2').deletion,
    cursorRow: 0,
    cursorColumn: 0,
    screenRows: 4,
    screenColumns: 4,
    cellWidth: 10,
    cellHeight: 20,
    resolvePosition: (TerminalKittyImagePlacement placement) =>
        TerminalKittyImagePlacementPosition(
          row: placement.logicalLineId - 11,
          column: 0,
        ),
  );
  _expect(
    upper.deletedPlacements == 1 && upper.deletedImages == 1 && store.isEmpty,
    'uppercase cell delete reclaims now-unused image data',
  );

  final TerminalKittyImageStore numbered = TerminalKittyImageStore(
    maximumImages: 4,
    maximumRetainedBytes: 64,
  );
  final TerminalKittyImage older = numbered
      .store(
        imageId: 0,
        imageNumber: 9,
        width: 1,
        height: 1,
        transient: false,
        rgba: Uint8List(4),
      )
      .image!;
  final TerminalKittyImage newer = numbered
      .store(
        imageId: 0,
        imageNumber: 9,
        width: 1,
        height: 1,
        transient: false,
        rgba: Uint8List(4),
      )
      .image!;
  final TerminalKittyImagePlacementResult newestPlacement = numbered.place(
    imageId: 0,
    imageNumber: 9,
    placementId: 2,
    logicalLineId: 20,
    logicalLineEpoch: 1,
    logicalCellOffset: 0,
    sourceX: 0,
    sourceY: 0,
    sourceWidth: 0,
    sourceHeight: 0,
    cellOffsetX: 0,
    cellOffsetY: 0,
    columns: 1,
    rows: 1,
    z: 0,
  );
  _expect(
    newestPlacement.image!.id == newer.id && older.id != newer.id,
    'placement by image number resolves only the newest image',
  );
  numbered.store(
    imageId: newer.id,
    imageNumber: 0,
    width: 1,
    height: 1,
    transient: false,
    rgba: Uint8List.fromList(const <int>[1, 2, 3, 4]),
  );
  _expect(
    numbered.placementCount == 0,
    'explicit image replacement removes every old placement',
  );
}

void _testEveryStaticDeleteSelector() {
  final List<({String command, int placements, int images})> cases =
      <({String command, int placements, int images})>[
        (command: 'Ga=d,d=a', placements: 4, images: 0),
        (command: 'Ga=d,d=A', placements: 4, images: 3),
        (command: 'Ga=d,d=c', placements: 1, images: 0),
        (command: 'Ga=d,d=C', placements: 1, images: 1),
        (command: 'Ga=d,d=n,I=9', placements: 1, images: 0),
        (command: 'Ga=d,d=N,I=9', placements: 1, images: 1),
        (command: 'Ga=d,d=i,i=10', placements: 2, images: 0),
        (command: 'Ga=d,d=I,i=10', placements: 2, images: 1),
        (command: 'Ga=d,d=p,x=1,y=1', placements: 1, images: 0),
        (command: 'Ga=d,d=P,x=1,y=1', placements: 1, images: 0),
        (command: 'Ga=d,d=q,x=1,y=1,z=-1', placements: 1, images: 0),
        (command: 'Ga=d,d=Q,x=1,y=1,z=-1', placements: 1, images: 0),
        (command: 'Ga=d,d=r,x=10,y=20', placements: 3, images: 0),
        (command: 'Ga=d,d=R,x=10,y=20', placements: 3, images: 2),
        (command: 'Ga=d,d=x,x=4', placements: 1, images: 0),
        (command: 'Ga=d,d=X,x=4', placements: 1, images: 0),
        (command: 'Ga=d,d=y,y=2', placements: 2, images: 0),
        (command: 'Ga=d,d=Y,y=2', placements: 2, images: 1),
        (command: 'Ga=d,d=z,z=5', placements: 2, images: 0),
        (command: 'Ga=d,d=Z,z=5', placements: 2, images: 1),
      ];
  for (final ({String command, int placements, int images}) testCase in cases) {
    final ({
      TerminalKittyImageStore store,
      Map<int, TerminalKittyImagePlacementPosition> positions,
    })
    fixture = _deleteFixture();
    final TerminalKittyImageDeleteResult result = fixture.store.delete(
      deletion: _command(testCase.command).deletion,
      cursorRow: 1,
      cursorColumn: 4,
      screenRows: 4,
      screenColumns: 6,
      cellWidth: 10,
      cellHeight: 20,
      resolvePosition: (TerminalKittyImagePlacement placement) =>
          fixture.positions[placement.placementGeneration],
    );
    _expect(
      result.deletedPlacements == testCase.placements &&
          result.deletedImages == testCase.images,
      '${testCase.command} has exact static deletion semantics',
    );
  }
}

({
  TerminalKittyImageStore store,
  Map<int, TerminalKittyImagePlacementPosition> positions,
})
_deleteFixture() {
  final TerminalKittyImageStore store = TerminalKittyImageStore(
    maximumImages: 8,
    maximumRetainedBytes: 64,
  );
  for (final int imageId in const <int>[10, 20, 30]) {
    store.store(
      imageId: imageId,
      imageNumber: 0,
      width: 1,
      height: 1,
      transient: false,
      rgba: Uint8List(4),
    );
  }
  final TerminalKittyImage numbered = store
      .store(
        imageId: 0,
        imageNumber: 9,
        width: 1,
        height: 1,
        transient: false,
        rgba: Uint8List(4),
      )
      .image!;
  final Map<int, TerminalKittyImagePlacementPosition> positions =
      <int, TerminalKittyImagePlacementPosition>{};
  void add({
    required int imageId,
    required int placementId,
    required int row,
    required int column,
    required int columns,
    required int rows,
    required int z,
  }) {
    final TerminalKittyImagePlacement placement = store
        .place(
          imageId: imageId,
          imageNumber: 0,
          placementId: placementId,
          logicalLineId: 100 + placementId,
          logicalLineEpoch: 1,
          logicalCellOffset: column,
          sourceX: 0,
          sourceY: 0,
          sourceWidth: 0,
          sourceHeight: 0,
          cellOffsetX: 0,
          cellOffsetY: 0,
          columns: columns,
          rows: rows,
          z: z,
        )
        .placement!;
    positions[placement.placementGeneration] =
        TerminalKittyImagePlacementPosition(row: row, column: column);
  }

  add(
    imageId: 10,
    placementId: 1,
    row: 0,
    column: 0,
    columns: 2,
    rows: 2,
    z: -1,
  );
  add(
    imageId: 10,
    placementId: 2,
    row: 3,
    column: 3,
    columns: 1,
    rows: 1,
    z: 5,
  );
  add(
    imageId: 20,
    placementId: 3,
    row: 1,
    column: 4,
    columns: 1,
    rows: 1,
    z: 5,
  );
  add(
    imageId: numbered.id,
    placementId: 9,
    row: 2,
    column: 1,
    columns: 1,
    rows: 1,
    z: 7,
  );
  return (store: store, positions: positions);
}

Future<void> _testControllerQueryStorageMultipartAndRejection() async {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 4);
  final _InProcessImageWorker worker = _InProcessImageWorker();
  final List<String> replies = <String>[];
  final TerminalKittyGraphicsController controller =
      TerminalKittyGraphicsController(
        screenSet: screens,
        paneId: 1,
        sessionGeneration: 2,
        worker: worker,
        onReply: (Uint8List bytes) {
          replies.add(ascii.decode(bytes));
          return true;
        },
      );

  controller.enqueueCommand(_command('Ga=q,i=1,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.isEmpty &&
        replies.single == '\x1b_Gi=1;OK\x1b\\',
    'query decodes and replies without storing image data',
  );

  controller.enqueueCommand(_command('Gi=7,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  final TerminalKittyImage original = screens.primaryKittyImages.imageById(7)!;
  controller.enqueueCommand(_command('Gi=7,f=32,s=1,v=1;BQYHCA=='));
  await controller.waitForIdle();
  final TerminalKittyImage replacement = screens.primaryKittyImages.imageById(
    7,
  )!;
  _expect(
    replacement.resourceGeneration > original.resourceGeneration &&
        screens.primaryKittyImages.length == 1,
    're-transmission replaces one explicit ID with a fresh resource',
  );
  _expectInts(replacement.copyRgba(), const <int>[
    5,
    6,
    7,
    8,
  ], 'replacement publishes decoded RGBA');

  controller.enqueueCommand(_command('GI=13,f=32,s=1,v=1;CQoLDA=='));
  await controller.waitForIdle();
  final TerminalKittyImage firstNumber = screens.primaryKittyImages
      .newestImageByNumber(13)!;
  controller.enqueueCommand(_command('GI=13,f=32,s=1,v=1;DQ4PEA=='));
  await controller.waitForIdle();
  final TerminalKittyImage secondNumber = screens.primaryKittyImages
      .newestImageByNumber(13)!;
  _expect(
    firstNumber.id != secondNumber.id &&
        replies.contains('\x1b_Gi=${firstNumber.id},I=13;OK\x1b\\') &&
        replies.contains('\x1b_Gi=${secondNumber.id},I=13;OK\x1b\\'),
    'numbered transmissions create IDs and acknowledge both identities',
  );

  screens.setAlternateMode1049(false);
  controller.enqueueCommand(_command('Gi=9,f=32,s=1,v=1,m=1;AQID'));
  await controller.waitForIdle();
  _expect(
    controller.hasPendingTransfer &&
        worker.service.pendingTransferCount == 1 &&
        screens.primaryKittyImages.imageById(9) == null,
    'first multipart chunk remains worker-owned and undisplayed',
  );
  screens.setAlternateMode1049(true);
  controller.enqueueCommand(_command('Gm=0;BA=='));
  await controller.waitForIdle();
  _expect(
    !controller.hasPendingTransfer &&
        screens.primaryKittyImages.imageById(9) != null &&
        screens.alternateKittyImages.imageById(9) == null,
    'multipart storage remains owned by the screen active at first chunk',
  );

  controller.enqueueCommand(_command('Gi=10,f=32,s=1,v=1,m=1;AQID'));
  await controller.waitForIdle();
  final int repliesBeforeDelete = replies.length;
  controller.enqueueCommand(_command('Ga=d,d=i,i=10'));
  await controller.waitForIdle();
  _expect(
    !controller.hasPendingTransfer &&
        worker.service.pendingTransferCount == 0 &&
        replies.length == repliesBeforeDelete,
    'delete aborts partial worker data and emits no success reply',
  );

  final int requestCount = worker.requests.length;
  controller.enqueueCommand(_command('Gi=11,t=f,f=100;L3RtcC94'));
  controller.enqueueCommand(_command('Ga=f,i=11;AAAA'));
  controller.enqueueCommand(_command('Gi=11,I=12,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  _expect(
    worker.requests.length == requestCount &&
        replies.any(
          (String value) => value.contains('local image transport'),
        ) &&
        replies.any((String value) => value.contains('image animation')) &&
        replies.any((String value) => value.contains('mutually exclusive')),
    'local media, animation, and conflicting identities fail before decode',
  );

  final int replyCount = replies.length;
  controller.enqueueCommand(_command('Gi=12,q=2,f=32,s=1,v=1;invalid!'));
  await controller.waitForIdle();
  _expect(
    replies.length == replyCount,
    'quiet level two suppresses a worker decode failure reply',
  );
  await controller.dispose();
  worker.dispose();
}

Future<void> _testControllerStorageCapQueueCapAndStaleWorker() async {
  final TerminalScreenSet boundedScreens = TerminalScreenSet(
    rows: 2,
    columns: 2,
    primaryKittyImages: TerminalKittyImageStore(
      maximumImages: 1,
      maximumRetainedBytes: 4,
    ),
    alternateKittyImages: TerminalKittyImageStore(
      maximumImages: 1,
      maximumRetainedBytes: 4,
    ),
  );
  final _InProcessImageWorker boundedWorker = _InProcessImageWorker();
  final List<String> boundedReplies = <String>[];
  final TerminalKittyGraphicsController bounded =
      TerminalKittyGraphicsController(
        screenSet: boundedScreens,
        paneId: 20,
        sessionGeneration: 1,
        worker: boundedWorker,
        onReply: (Uint8List bytes) {
          boundedReplies.add(ascii.decode(bytes));
          return true;
        },
      );
  bounded.enqueueCommand(_command('Gi=1,f=32,s=1,v=1;AQIDBA=='));
  bounded.enqueueCommand(_command('Gi=2,f=32,s=1,v=1;BQYHCA=='));
  await bounded.waitForIdle();
  _expect(
    boundedScreens.primaryKittyImages.length == 1 &&
        boundedScreens.primaryKittyImages.imageById(1) != null &&
        boundedReplies.last.contains('ENOSPC:image storage limit reached'),
    'storage rejection preserves the first image and reports ENOSPC',
  );
  await bounded.dispose();
  boundedWorker.dispose();

  final TerminalScreenSet queueScreens = TerminalScreenSet(rows: 2, columns: 2);
  final _InProcessImageWorker queueWorker = _InProcessImageWorker();
  final Completer<void> queueGate = Completer<void>();
  queueWorker.gate = queueGate;
  final TerminalKittyGraphicsController queued =
      TerminalKittyGraphicsController(
        screenSet: queueScreens,
        paneId: 21,
        sessionGeneration: 1,
        worker: queueWorker,
        maximumQueuedJobs: 2,
        onReply: (_) => true,
      );
  _expect(
    queued.enqueueCommand(_command('Gi=3,f=32,s=1,v=1,m=1;AQID')) &&
        queued.enqueueCommand(_command('Gm=0;BA==')) &&
        !queued.enqueueCommand(_command('Gi=4,f=32,s=1,v=1;AQIDBA==')),
    'bounded command FIFO rejects work beyond its configured job cap',
  );
  queueGate.complete();
  await queued.waitForIdle();
  _expect(
    queued.rejectedCommandCount == 1 &&
        !queued.hasPendingTransfer &&
        queueWorker.service.pendingTransferCount == 0 &&
        queueScreens.primaryKittyImages.isEmpty,
    'a dropped graphics command desynchronizes and aborts multipart state',
  );
  await queued.dispose();
  queueWorker.dispose();

  final TerminalScreenSet staleScreens = TerminalScreenSet(rows: 2, columns: 2);
  final _InProcessImageWorker oldWorker = _InProcessImageWorker();
  final _InProcessImageWorker replacementWorker = _InProcessImageWorker();
  final Completer<void> staleGate = Completer<void>();
  oldWorker.gate = staleGate;
  final List<String> staleReplies = <String>[];
  final TerminalKittyGraphicsController stale = TerminalKittyGraphicsController(
    screenSet: staleScreens,
    paneId: 22,
    sessionGeneration: 1,
    worker: oldWorker,
    onReply: (Uint8List bytes) {
      staleReplies.add(ascii.decode(bytes));
      return true;
    },
  );
  stale.enqueueCommand(_command('Gi=30,f=32,s=1,v=1;AQIDBA=='));
  await Future<void>.delayed(Duration.zero);
  _expect(
    stale.attachWorker(replacementWorker),
    'replacement worker changes the controller epoch',
  );
  staleGate.complete();
  await stale.waitForIdle();
  _expect(
    stale.staleCompletionCount == 1 &&
        staleScreens.primaryKittyImages.isEmpty &&
        staleReplies.isEmpty,
    'old worker completion cannot publish state or a reply',
  );
  stale.enqueueCommand(_command('Gi=31,f=32,s=1,v=1;AQIDBA=='));
  await stale.waitForIdle();
  _expect(
    staleScreens.primaryKittyImages.imageById(31) != null &&
        staleReplies.single == '\x1b_Gi=31;OK\x1b\\',
    'replacement worker serves the next generation-safe command',
  );
  await stale.dispose();
  oldWorker.dispose();
  replacementWorker.dispose();
}

Future<void> _testControllerPlacementActionsAndDelete() async {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 4, columns: 6);
  screens.updateLogicalCellSize(width: 10, height: 20);
  final _InProcessImageWorker worker = _InProcessImageWorker();
  final List<String> replies = <String>[];
  var changeCount = 0;
  final TerminalKittyGraphicsController controller =
      TerminalKittyGraphicsController(
        screenSet: screens,
        paneId: 25,
        sessionGeneration: 1,
        worker: worker,
        onReply: (Uint8List bytes) {
          replies.add(ascii.decode(bytes));
          return true;
        },
        onChanged: () => changeCount++,
      );
  controller.enqueueCommand(_command('Gi=70,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  screens.activeScreen.setCursorPosition(1, 1);
  controller.enqueueCommand(_command('Ga=p,i=70,p=3,c=2,r=2,C=1,z=-1,x=0,y=0'));
  await controller.waitForIdle();
  final TerminalKittyImagePlacement first = screens.primaryKittyImages
      .placementSnapshot()
      .single;
  _expect(
    replies.last == '\x1b_Gi=70,p=3;OK\x1b\\' &&
        first.imageId == 70 &&
        first.z == -1 &&
        screens.activeScreen.cursorRow == 1 &&
        screens.activeScreen.cursorColumn == 1,
    'identified put stores one below-text placement without cursor movement',
  );

  screens.activeScreen.setCursorPosition(2, 2);
  controller.enqueueCommand(_command('Ga=p,i=70,p=3,c=1,r=1,C=1'));
  await controller.waitForIdle();
  final TerminalKittyImagePlacement replacement = screens.primaryKittyImages
      .placementSnapshot()
      .single;
  _expect(
    replacement.placementGeneration > first.placementGeneration &&
        replacement.logicalLineId != first.logicalLineId,
    'the same explicit image/placement pair moves atomically',
  );

  screens.activeScreen.setCursorPosition(0, 0);
  controller.enqueueCommand(_command('Ga=p,i=70,c=2,r=2'));
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.placementCount == 2 &&
        screens.activeScreen.cursorRow == 1 &&
        screens.activeScreen.cursorColumn == 2,
    'anonymous placement remains distinct and applies bounded cursor movement',
  );

  controller.enqueueCommand(
    _command('Ga=T,i=71,p=4,f=32,s=1,v=1,c=1,r=1,C=1;BQYHCA=='),
  );
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.imageById(71) != null &&
        screens.primaryKittyImages.placementSnapshot().any(
          (TerminalKittyImagePlacement placement) =>
              placement.imageId == 71 && placement.placementId == 4,
        ) &&
        replies.last == '\x1b_Gi=71,p=4;OK\x1b\\',
    'transmit-and-place publishes image and placement before one success reply',
  );

  final int beforeErrors = screens.primaryKittyImages.placementCount;
  controller.enqueueCommand(_command('Ga=p,i=999,C=1'));
  controller.enqueueCommand(_command('Ga=p,i=70,U=2,C=1'));
  controller.enqueueCommand(_command('Ga=p,i=70,P=70,Q=3,C=1'));
  controller.enqueueCommand(_command('Ga=p,i=70,z=-1073741825,C=1'));
  controller.enqueueCommand(_command('Ga=p,i=70,C=2'));
  controller.enqueueCommand(_command('Ga=d,d=f,i=70'));
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.placementCount == beforeErrors &&
        replies.any(
          (String value) => value.contains('ENOENT:image not found'),
        ) &&
        replies.any(
          (String value) => value.contains('virtual image placement'),
        ) &&
        replies.any(
          (String value) => value.contains('relative image placement'),
        ) &&
        replies.any((String value) => value.contains('extreme negative')) &&
        replies.any((String value) => value.contains('cursor movement')) &&
        replies.any((String value) => value.contains('frame deletion')),
    'unsupported placement and animation-delete forms fail without mutation',
  );

  final int repliesBeforeLowerDelete = replies.length;
  controller.enqueueCommand(_command('Ga=d,d=i,i=70,p=3'));
  await controller.waitForIdle();
  _expect(
    replies.length == repliesBeforeLowerDelete &&
        screens.primaryKittyImages.imageById(70) != null &&
        screens.primaryKittyImages.placementSnapshot().every(
          (TerminalKittyImagePlacement placement) =>
              placement.imageId != 70 || placement.placementId != 3,
        ),
    'lowercase delete is silent and retains decoded image data',
  );
  controller.enqueueCommand(_command('Ga=d,d=I,i=70'));
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.imageById(70) == null &&
        screens.primaryKittyImages.placementSnapshot().every(
          (TerminalKittyImagePlacement placement) => placement.imageId != 70,
        ),
    'uppercase image delete removes placements and now-unused data',
  );

  screens.activeScreen.setCursorPosition(0, 0);
  controller.enqueueCommand(_command('Ga=p,i=71,p=8,c=1,r=1,C=1'));
  await controller.waitForIdle();
  final TerminalKittyImage oldImage = screens.primaryKittyImages.imageById(71)!;
  final Completer<void> replacementGate = Completer<void>();
  worker.gate = replacementGate;
  controller.enqueueCommand(_command('Gi=71,f=32,s=1,v=1;CQoLDA=='));
  await Future<void>.delayed(Duration.zero);
  _expect(
    screens.primaryKittyImages.placementSnapshot().every(
          (TerminalKittyImagePlacement placement) => placement.imageId != 71,
        ) &&
        identical(screens.primaryKittyImages.imageById(71), oldImage),
    'replacement start removes old placements before worker completion',
  );
  replacementGate.complete();
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.imageById(71)!.resourceGeneration >
            oldImage.resourceGeneration &&
        changeCount >= 8,
    'replacement completion publishes a fresh resource and presentation notice',
  );
  await controller.dispose();
  worker.dispose();
}

Future<void> _testControllerFailureReplyAndPendingTeardown() async {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 2);
  final _InProcessImageWorker worker = _InProcessImageWorker();
  final List<String> replies = <String>[];
  var acceptReplies = true;
  final TerminalKittyGraphicsController controller =
      TerminalKittyGraphicsController(
        screenSet: screens,
        paneId: 23,
        sessionGeneration: 1,
        worker: worker,
        onReply: (Uint8List bytes) {
          replies.add(ascii.decode(bytes));
          return acceptReplies;
        },
      );

  worker.forcedStatus = RuntimeLifecycleRequestStatus.backpressured;
  controller.enqueueCommand(_command('Gi=60,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.isEmpty &&
        replies.single.contains(
          'i=60;EBUSY:image worker did not accept the request',
        ) &&
        controller.workerFailureCount == 1,
    'worker backpressure fails closed with an exact identified reply',
  );

  worker.forcedStatus = RuntimeLifecycleRequestStatus.response;
  worker.throwRequest = true;
  controller.enqueueCommand(_command('Gi=61,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  _expect(
    replies.last.contains('i=61;EIO:image worker request failed') &&
        controller.workerFailureCount == 2,
    'worker exceptions fail closed without publishing image state',
  );

  worker.throwRequest = false;
  acceptReplies = false;
  controller.enqueueCommand(_command('Ga=q,i=62,f=32,s=1,v=1;AQIDBA=='));
  await controller.waitForIdle();
  _expect(
    screens.primaryKittyImages.isEmpty &&
        controller.emittedGraphicsReplyCount == 2 &&
        controller.rejectedGraphicsReplyCount == 1,
    'a rejected PTY write is counted and does not turn a query into storage',
  );
  await controller.dispose();
  worker.dispose();

  final TerminalScreenSet teardownScreens = TerminalScreenSet(
    rows: 2,
    columns: 2,
  );
  final _InProcessImageWorker teardownWorker = _InProcessImageWorker();
  final Completer<void> teardownGate = Completer<void>();
  teardownWorker.gate = teardownGate;
  final TerminalKittyGraphicsController teardown =
      TerminalKittyGraphicsController(
        screenSet: teardownScreens,
        paneId: 24,
        sessionGeneration: 1,
        worker: teardownWorker,
        onReply: (_) => true,
      );
  teardown.enqueueCommand(_command('Gi=63,f=32,s=1,v=1,m=1;AQID'));
  await Future<void>.delayed(Duration.zero);
  _expect(
    teardown.hasPendingTransfer,
    'a blocked first chunk exposes one controller-owned pending transfer',
  );
  final Future<void> disposing = teardown.dispose();
  teardownGate.complete();
  await disposing;
  await teardown.waitForIdle();
  _expect(
    teardown.isDisposed &&
        !teardown.hasPendingTransfer &&
        teardownWorker.service.pendingTransferCount == 0 &&
        teardownScreens.primaryKittyImages.isEmpty &&
        teardownScreens.alternateKittyImages.isEmpty,
    'dispose invalidates an in-flight completion and aborts helper state',
  );
  teardownWorker.dispose();
}

Future<void> _testSessionParserAndReplyFifo() async {
  final FakePtyBackend backend = FakePtyBackend();
  final _InProcessImageWorker worker = _InProcessImageWorker();
  final Completer<void> gate = Completer<void>();
  worker.gate = gate;
  var sessionChangeCount = 0;
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(40), generation: 2),
    ptyBackend: backend,
    graphicsWorker: worker,
    onChanged: () => sessionChangeCount++,
    onTerminated: () {},
  );
  await session.start();
  final FakePtyProcess process = backend.processes.single;
  process.emitOutput(
    _bytes(
      '\x1b_Ga=q,i=44,f=32,s=1,v=1;AQIDBA==\x1b\\'
      '\x1b[5n',
    ),
  );
  await Future<void>.delayed(Duration.zero);
  _expect(
    process.writes.isEmpty &&
        session.kittyGraphicsController.pendingJobCount == 2,
    'ordinary reply waits behind the earlier asynchronous graphics query',
  );
  gate.complete();
  await session.kittyGraphicsController.waitForIdle();
  _expectWrites(process.writes, const <String>[
    '\x1b_Gi=44;OK\x1b\\',
    '\x1b[0n',
  ]);
  _expect(
    session.terminalParserSink.acceptedKittyGraphicsCommandCount == 1 &&
        session.terminalParserSink.rejectedKittyGraphicsCommandCount == 0 &&
        session.terminalParserSink.acceptedReplyCount == 1,
    'session parser accounts the queued Kitty command and ordinary reply',
  );

  process.emitOutput(_bytes('\x1b_Gi=;\x1b\\'));
  await session.kittyGraphicsController.waitForIdle();
  _expect(
    session.terminalParserSink.acceptedKittyGraphicsCommandCount == 1 &&
        session.terminalParserSink.rejectedKittyGraphicsCommandCount == 1,
    'malformed leading-G APC is rejected without poisoning later parsing',
  );

  process.emitOutput(_bytes('\x1b_Gi=45,f=32,s=1,v=1;AQIDBA==\x1b\\'));
  await session.kittyGraphicsController.waitForIdle();
  _expect(
    session.terminalScreenSet.primaryKittyImages.imageById(45) != null,
    'session parser publishes a direct image into its active screen store',
  );
  session.terminalScreenSet.updateLogicalCellSize(width: 10, height: 20);
  process.emitOutput(_bytes('\x1b_Ga=p,i=45,p=2,c=1,r=1,C=1\x1b\\'));
  await session.kittyGraphicsController.waitForIdle();
  _expect(
    session.terminalScreenSet.primaryKittyImages.placementCount == 1 &&
        sessionChangeCount > 0,
    'fake PTY placement reaches session state and presentation notification',
  );
  await session.dispose();
  _expect(
    session.terminalScreenSet.primaryKittyImages.isEmpty &&
        session.kittyGraphicsController.isDisposed,
    'session teardown clears image bytes and closes the controller',
  );
  worker.dispose();
}

Future<void> _testRealWorkerSessionRoundTripAndTeardown() async {
  final RuntimeLifecycleCoordinator coordinator = RuntimeLifecycleCoordinator(
    scenario: RuntimeLifecycleScenario.normal,
    workerCommand: _workerCommand(),
    observer: (_) {},
    startupTimeout: const Duration(seconds: 3),
    requestTimeout: const Duration(seconds: 3),
    shutdownTimeout: const Duration(seconds: 1),
    forcedExitTimeout: const Duration(seconds: 1),
  );
  _expect(
    await coordinator.start() == RuntimeLifecycleStartStatus.ready,
    'real session image worker reaches ready',
  );
  final FakePtyBackend backend = FakePtyBackend();
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(41), generation: 3),
    ptyBackend: backend,
    graphicsWorker: coordinator,
    onChanged: () {},
    onTerminated: () {},
  );
  await session.start();
  final FakePtyProcess process = backend.processes.single;
  process.emitOutput(_bytes('\x1b_Gi=51,f=32,s=1,v=1;AQIDBA==\x1b\\'));
  await session.kittyGraphicsController.waitForIdle();
  _expect(
    session.terminalScreenSet.primaryKittyImages.imageById(51) != null &&
        ascii.decode(process.writes.single) == '\x1b_Gi=51;OK\x1b\\',
    'real worker result reaches the session store and PTY reply path',
  );
  await session.dispose();
  final RuntimeLifecycleShutdownResult shutdown = await coordinator.shutdown();
  _expect(
    shutdown.termination == RuntimeLifecycleWorkerTermination.graceful &&
        RuntimeLifecycleCoordinator.outstandingProcessCount == 0 &&
        session.terminalScreenSet.primaryKittyImages.isEmpty,
    'session clears image state before the real helper is reaped',
  );
}

final class _InProcessImageWorker implements RuntimeWorkerPayloadClient {
  final RuntimeImageWorkerService service = RuntimeImageWorkerService();
  final List<RuntimeImageWorkerRequest> requests =
      <RuntimeImageWorkerRequest>[];
  Completer<void>? gate;
  RuntimeLifecycleRequestStatus forcedStatus =
      RuntimeLifecycleRequestStatus.response;
  bool throwRequest = false;

  @override
  Future<RuntimeLifecyclePayloadRequestResult> requestPayload(
    Uint8List payload, {
    bool expectsInt64Response = false,
  }) async {
    await gate?.future;
    if (throwRequest) throw StateError('injected image worker failure');
    if (forcedStatus != RuntimeLifecycleRequestStatus.response) {
      return RuntimeLifecyclePayloadRequestResult(forcedStatus);
    }
    requests.add(RuntimeImageWorkerRequestCodec.decode(payload));
    return RuntimeLifecyclePayloadRequestResult(
      RuntimeLifecycleRequestStatus.response,
      payload: service.handle(payload),
    );
  }

  void dispose() => service.dispose();
}

TerminalKittyGraphicsCommand _command(String payload) =>
    TerminalKittyGraphicsCommandParser.parse(_bytes(payload));

RuntimeLifecycleWorkerCommand _workerCommand() {
  return RuntimeLifecycleWorkerCommand(
    executable: Platform.resolvedExecutable,
    arguments: <String>['${Directory.current.path}/bin/runtime_worker.dart'],
    workingDirectory: Directory.current.path,
  );
}

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);

void _expectWrites(List<Uint8List> actual, List<String> expected) {
  _expect(actual.length == expected.length, 'PTY write count');
  for (var index = 0; index < expected.length; index++) {
    _expect(
      ascii.decode(actual[index]) == expected[index],
      'PTY write $index is byte exact',
    );
  }
}

void _expectInts(List<int> actual, List<int> expected, String description) {
  _expect(actual.length == expected.length, '$description length');
  for (var index = 0; index < expected.length; index++) {
    _expect(actual[index] == expected[index], '$description byte $index');
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError('test failed: $message');
}
