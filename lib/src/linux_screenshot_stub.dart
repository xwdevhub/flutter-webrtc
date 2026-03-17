import 'dart:typed_data';

/// Web stub for [LinuxScreenshotPlugin].
///
/// The Linux screenshot plugin is not available in the browser.
/// All methods throw [UnsupportedError].
class LinuxScreenshotPlugin {
  // ignore: avoid_unused_constructor_parameters
  LinuxScreenshotPlugin({String? subprocessScriptPath});

  Future<void> start() =>
      Future.error(UnsupportedError('LinuxScreenshotPlugin is not available on web.'));

  Future<void> stop() async {}

  Future<Uint8List?> captureScreen({
    bool interactive = true,
    String format = 'png',
  }) =>
      Future.error(UnsupportedError('LinuxScreenshotPlugin is not available on web.'));

  Future<bool> isAlive() async => false;
}

/// Thrown when the screenshot subprocess reports a capture failure.
class ScreenshotException implements Exception {
  final String message;
  const ScreenshotException(this.message);

  @override
  String toString() => 'ScreenshotException: $message';
}
