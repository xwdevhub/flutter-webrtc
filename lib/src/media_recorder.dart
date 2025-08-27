import 'dart:async';

import 'package:flutter/services.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

import '../flutter_webrtc.dart';

class MediaRecorder extends rtc.MediaRecorder {
  MediaRecorder() : _delegate = mediaRecorder();
  final rtc.MediaRecorder _delegate;

  Function(double progress)? onProgress;
  Function(String path)? onSuccess;
  Function(String error)? onFailure;

  StreamSubscription<dynamic>? _eventSubscription;

  EventChannel _eventChannelFor(String path) {
    return EventChannel('FlutterWebRTC/MediaRecorderEvent/$path');
  }

  void eventListener(dynamic event) {
    final Map<dynamic, dynamic> map = event;
    switch (map['event']) {
      case 'onProgress':
        onProgress?.call(map['progress']);
        break;
      case 'onSuccess':
        onSuccess?.call(map['path']);
        break;
      case 'onFailure':
        onFailure?.call(map['error']);
        break;
    }
  }

  @override
  Future<void> start(String path,
      {MediaStreamTrack? videoTrack,
      RecorderAudioChannel? audioChannel}) async {
    await _delegate.start(path,
        videoTrack: videoTrack, audioChannel: audioChannel);
  }

  @override
  Future stop() {
    return _delegate.stop();
  }

  Future<void> transcode(String path) async {
    _eventSubscription?.cancel();
    _eventSubscription =
        _eventChannelFor(path).receiveBroadcastStream().listen(eventListener);
    await WebRTC.invokeMethod('transRecordToFile', {'path': path});
  }

  @override
  void startWeb(
    MediaStream stream, {
    Function(dynamic blob, bool isLastOne)? onDataChunk,
    String? mimeType,
    int timeSlice = 1000,
  }) =>
      _delegate.startWeb(
        stream,
        onDataChunk: onDataChunk,
        mimeType: mimeType ?? 'video/webm',
        timeSlice: timeSlice,
      );

  void close() {
    _eventSubscription?.cancel();
  }
}
