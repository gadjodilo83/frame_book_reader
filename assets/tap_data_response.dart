import 'dart:async';

import 'package:logging/logging.dart';

final _log = Logger("TapDR");

// Frame to Phone flags
const tapFlag = 0x09;

/// Multi-Tap data stream, returns the number of taps detected
Stream<int> tapDataResponse(Stream<List<int>> dataResponse, final Duration threshold) {

  // the subscription to the underlying data stream
  StreamSubscription<List<int>>? dataResponseSubs;

  // Our stream controller that transforms/accumulates the raw data into audio (as bytes)
  StreamController<int> controller = StreamController();

  // track state of multi-taps
  int lastTapTime = 0;
  int taps = 0;
  Timer? t;

  controller.onListen = () {
    dataResponseSubs = dataResponse
      .where((data) => data[0] == tapFlag)
      .listen((data) {
        int tapTime = DateTime.now().millisecondsSinceEpoch;
        // debounce taps that occur too close to the prior tap
        if (tapTime - lastTapTime < 40) {
          _log.finer('tap ignored - debouncing');
          lastTapTime = tapTime;
        }
        else {
          _log.finer('tap detected');
          lastTapTime = tapTime;

          taps++;
          t?.cancel();
          t = Timer(threshold, () {
            controller.add(taps);
            taps = 0;
          });
        }

    }, onDone: controller.close, onError: controller.addError);
    _log.fine('TapDataResponse Controller being listened to');
  };

  controller.onCancel = () {
    dataResponseSubs?.cancel();
    controller.close();
    _log.fine('Controller cancelled');
  };

  return controller.stream;
}
