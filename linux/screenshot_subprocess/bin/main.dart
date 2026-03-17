// Linux screenshot subprocess.
//
// Starts a loopback HTTP server and reports the chosen port on stdout so the
// parent Flutter process can connect.
//
// Usage:
//   dart run bin/main.dart [--port <PORT>]
//
// Endpoints:
//   GET  /status   – health-check, returns JSON {"status":"ok"}
//   POST /capture  – take a screenshot and return image bytes
//                    Body (optional JSON):
//                      interactive : bool   – show region-selection UI (default true)
//                      format      : string – "png" or "jpeg"           (default "png")
//   POST /shutdown – gracefully stop the server

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ──────────────────────────────────────────────────────────────────────────────
// Entry point
// ──────────────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  int port = 0; // 0 → OS picks an available port

  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') {
      port = int.tryParse(args[i + 1]) ?? 0;
      break;
    }
  }

  final server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  port = server.port;

  // Tell the parent process which port we are using.
  // The parent reads stdout and looks for this line.
  stdout.writeln('SCREENSHOT_SERVER_PORT:$port');
  await stdout.flush();

  await _serveRequests(server);
}

// ──────────────────────────────────────────────────────────────────────────────
// Request dispatcher
// ──────────────────────────────────────────────────────────────────────────────

HttpServer? _server;

Future<void> _serveRequests(HttpServer server) async {
  _server = server;
  await for (final HttpRequest req in server) {
    try {
      await _dispatch(req);
    } catch (e, st) {
      stderr.writeln('[screenshot_subprocess] error: $e\n$st');
      _sendJsonError(req.response, 500, 'Internal error: $e');
    }
  }
}

Future<void> _dispatch(HttpRequest req) async {
  final path = req.uri.path;
  final method = req.method.toUpperCase();

  if (path == '/status' && method == 'GET') {
    _sendJson(req.response, 200, {'status': 'ok', 'version': '1.0.0'});
    return;
  }

  if (path == '/capture' && method == 'POST') {
    await _handleCapture(req);
    return;
  }

  if (path == '/shutdown' && method == 'POST') {
    _sendJson(req.response, 200, {'status': 'shutting_down'});
    await _server?.close();
    return;
  }

  _sendJsonError(req.response, 404, 'Not found: $method $path');
}

// ──────────────────────────────────────────────────────────────────────────────
// Capture handler
// ──────────────────────────────────────────────────────────────────────────────

Future<void> _handleCapture(HttpRequest req) async {
  // Parse optional JSON body.
  String bodyStr = '';
  try {
    bodyStr = await utf8.decodeStream(req);
  } catch (_) {}

  Map<String, dynamic> params = {};
  if (bodyStr.isNotEmpty) {
    try {
      params = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {}
  }

  final bool interactive = params['interactive'] as bool? ?? true;
  final String format =
      (params['format'] as String?)?.toLowerCase() == 'jpeg' ? 'jpeg' : 'png';

  final tmpPath =
      '/tmp/flutter_screenshot_${DateTime.now().millisecondsSinceEpoch}.$format';

  bool success = false;
  String captureError = '';

  // Detect display server.
  final bool isWayland =
      Platform.environment.containsKey('WAYLAND_DISPLAY') &&
          Platform.environment['WAYLAND_DISPLAY']!.isNotEmpty;

  if (isWayland) {
    success = await _captureWayland(
      tmpPath,
      interactive,
      onError: (e) => captureError = e,
    );
  } else {
    success = await _captureX11(
      tmpPath,
      interactive,
      onError: (e) => captureError = e,
    );
  }

  if (!success) {
    _sendJsonError(req.response, 500,
        captureError.isNotEmpty ? captureError : 'Screen capture failed');
    return;
  }

  final file = File(tmpPath);
  if (!await file.exists()) {
    _sendJsonError(req.response, 500, 'Screenshot file was not created');
    return;
  }

  try {
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) {}); // best-effort cleanup

    req.response.statusCode = 200;
    req.response.headers.contentType = format == 'png'
        ? ContentType('image', 'png')
        : ContentType('image', 'jpeg');
    req.response.add(bytes);
    await req.response.close();
  } catch (e) {
    _sendJsonError(req.response, 500, 'Error reading screenshot file: $e');
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Platform-specific capture helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Wayland capture: uses grim + slurp (for region selection).
Future<bool> _captureWayland(
  String outputPath,
  bool interactive, {
  required void Function(String) onError,
}) async {
  if (interactive) {
    // slurp lets the user draw a rectangle and outputs "x,y WxH".
    final slurp = await Process.run('slurp', []);
    if (slurp.exitCode != 0) {
      onError('Region selection cancelled or slurp not available');
      return false;
    }
    final region = (slurp.stdout as String).trim();
    final grim = await Process.run('grim', ['-g', region, outputPath]);
    if (grim.exitCode != 0) {
      onError('grim failed: ${grim.stderr}');
      return false;
    }
    return true;
  } else {
    final grim = await Process.run('grim', [outputPath]);
    if (grim.exitCode == 0) return true;
    onError('grim failed: ${grim.stderr}');
    return false;
  }
}

/// X11 capture: tries scrot, then gnome-screenshot, then ImageMagick import.
Future<bool> _captureX11(
  String outputPath,
  bool interactive, {
  required void Function(String) onError,
}) async {
  if (interactive) {
    // scrot -s: user draws a selection rectangle.
    final scrot = await Process.run('scrot', ['-s', outputPath]);
    if (scrot.exitCode == 0) return true;

    // Fallback: gnome-screenshot area selection.
    final gs = await Process.run('gnome-screenshot', ['-a', '-f', outputPath]);
    if (gs.exitCode == 0) return true;

    onError(
        'No interactive screenshot tool found. Install scrot or gnome-screenshot.');
    return false;
  } else {
    // Full-screen, no UI.
    final scrot = await Process.run('scrot', [outputPath]);
    if (scrot.exitCode == 0) return true;

    // ImageMagick import.
    final imp =
        await Process.run('import', ['-window', 'root', outputPath]);
    if (imp.exitCode == 0) return true;

    // xwd + convert (ImageMagick).
    final xwdOut = '/tmp/flutter_screenshot_tmp.xwd';
    final xwd = await Process.run('xwd', ['-root', '-silent', '-out', xwdOut]);
    if (xwd.exitCode == 0) {
      final conv = await Process.run('convert', [xwdOut, outputPath]);
      await File(xwdOut).delete().catchError((_) {});
      if (conv.exitCode == 0) return true;
    }

    onError(
        'No screenshot tool found. Install scrot or imagemagick (import).');
    return false;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Response helpers
// ──────────────────────────────────────────────────────────────────────────────

void _sendJson(
    HttpResponse response, int statusCode, Map<String, dynamic> data) {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(data));
  response.close(); // intentionally not awaited – fire-and-forget for simple responses
}

void _sendJsonError(HttpResponse response, int statusCode, String message) {
  _sendJson(response, statusCode, {'error': message});
}
