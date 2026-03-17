import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Plugin for taking screenshots on Linux.
///
/// Architecture
/// ============
/// A small Dart HTTP server (the *subprocess*) is started in a separate
/// [Process].  The subprocess uses native Linux tools (scrot for X11, grim for
/// Wayland) to capture the screen and serves the image bytes over a loopback
/// HTTP connection.
///
/// The main Flutter process controls the subprocess entirely through HTTP so
/// that UI rendering is never blocked.
///
/// Usage
/// -----
/// ```dart
/// final plugin = LinuxScreenshotPlugin();
///
/// // Optional: start eagerly so the first capture is faster.
/// await plugin.start();
///
/// // Capture with interactive region selection (QQ-style).
/// final bytes = await plugin.captureScreen(interactive: true);
///
/// // Always stop the subprocess when you are done.
/// await plugin.stop();
/// ```
class LinuxScreenshotPlugin {
  /// Path to the subprocess entry point (`bin/main.dart`).
  ///
  /// If null the plugin searches common locations relative to the current
  /// working directory.
  final String? subprocessScriptPath;

  Process? _process;
  HttpClient? _client;
  int _port = 0;
  bool _running = false;

  LinuxScreenshotPlugin({this.subprocessScriptPath});

  // ────────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ────────────────────────────────────────────────────────────────────────────

  /// Start the screenshot subprocess.
  ///
  /// Idempotent – calling [start] when the subprocess is already running is a
  /// no-op.
  Future<void> start() async {
    if (_running) return;

    final script = subprocessScriptPath ?? _resolveScriptPath();
    if (script == null || !File(script).existsSync()) {
      throw StateError(
        'Screenshot subprocess not found.\n'
        'Expected path: ${subprocessScriptPath ?? "<auto-detect>"}\n'
        'Provide the correct path via LinuxScreenshotPlugin(subprocessScriptPath: …).',
      );
    }

    _process = await Process.start(
      'dart',
      ['run', script],
      environment: Platform.environment,
    );

    // Forward subprocess stderr to our own stderr for debugging.
    _process!.stderr
        .transform(utf8.decoder)
        .listen((data) => stderr.write('[screenshot_subprocess] $data'));

    // Read the port from subprocess stdout.
    _port = await _readPort(_process!).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process!.kill();
        throw TimeoutException(
            'Screenshot subprocess did not report its port within 10 s');
      },
    );

    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 30);

    _running = true;
  }

  /// Stop the subprocess and release all resources.
  Future<void> stop() async {
    try {
      await _postJson('/shutdown', {});
    } catch (_) {} // best-effort

    _client?.close(force: true);
    _client = null;
    _process?.kill();
    _process = null;
    _running = false;
    _port = 0;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────────

  /// Capture a screenshot and return the raw image bytes.
  ///
  /// Parameters
  /// ----------
  /// [interactive]
  ///   When `true` (default) the user is shown a region-selection UI
  ///   (scrot -s on X11, slurp+grim on Wayland) before the image is captured.
  ///   When `false` the entire screen is captured immediately.
  ///
  /// [format]
  ///   `"png"` (default) or `"jpeg"`.
  ///
  /// Returns `null` when the user cancels the selection.
  /// Throws a [ScreenshotException] on capture errors.
  Future<Uint8List?> captureScreen({
    bool interactive = true,
    String format = 'png',
  }) async {
    if (!_running) await start();

    final response = await _postJson('/capture', {
      'interactive': interactive,
      'format': format,
    });

    if (response.statusCode == 200) {
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return Uint8List.fromList(bytes);
    }

    // 500 from subprocess → capture failed / user cancelled.
    final body = await utf8.decodeStream(response);
    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {}

    final msg = json['error'] as String? ?? body;
    if (msg.toLowerCase().contains('cancel')) return null;
    throw ScreenshotException(msg);
  }

  /// Check whether the subprocess HTTP server is reachable.
  Future<bool> isAlive() async {
    if (!_running) return false;
    try {
      final req = await _client!.get('127.0.0.1', _port, '/status');
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────────

  /// Sends a POST request with a JSON body and returns the raw response.
  Future<HttpClientResponse> _postJson(
      String path, Map<String, dynamic> body) async {
    final req = await _client!.post('127.0.0.1', _port, path);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    return req.close();
  }

  /// Reads lines from the subprocess stdout until the port announcement is
  /// found: `SCREENSHOT_SERVER_PORT:<number>`.
  static Future<int> _readPort(Process process) {
    const prefix = 'SCREENSHOT_SERVER_PORT:';
    final completer = Completer<int>();

    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        if (!completer.isCompleted && line.startsWith(prefix)) {
          final port = int.tryParse(line.substring(prefix.length).trim());
          if (port != null && port > 0) completer.complete(port);
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    return completer.future;
  }

  /// Searches common locations for the subprocess script relative to the
  /// current working directory (works for development & `pub run`).
  static String? _resolveScriptPath() {
    final cwd = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$cwd/linux/screenshot_subprocess/bin/main.dart',
      // Packaged next to the executable.
      '$exeDir/screenshot_subprocess/bin/main.dart',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Exceptions
// ──────────────────────────────────────────────────────────────────────────────

/// Thrown when the screenshot subprocess reports a capture failure.
class ScreenshotException implements Exception {
  final String message;
  const ScreenshotException(this.message);

  @override
  String toString() => 'ScreenshotException: $message';
}
