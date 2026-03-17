import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Demonstrates the Linux screenshot plugin (QQ-style region capture).
///
/// How it works
/// ------------
/// 1. The page starts a [LinuxScreenshotPlugin] subprocess via [_plugin.start].
/// 2. "Full Screen" captures the entire desktop without any selection UI.
/// 3. "Select Region (interactive)" lets the user drag a region *outside* the
///    Flutter window using the native Linux screenshot tool (scrot -s / slurp).
/// 4. "QQ-Style Overlay" first captures the full screen, then shows a
///    [ScreenshotOverlayPage] on top so the user can choose a region
///    completely within Flutter.  The selection is cropped with
///    [ScreenshotSelection.cropBytes].
///
/// Note: This page is Linux-only; it shows an informational message on other
/// platforms.
class LinuxScreenshotSample extends StatefulWidget {
  static const String tag = 'linux_screenshot_sample';

  @override
  _LinuxScreenshotSampleState createState() => _LinuxScreenshotSampleState();
}

class _LinuxScreenshotSampleState extends State<LinuxScreenshotSample> {
  late final LinuxScreenshotPlugin _plugin;

  Uint8List? _screenshot;
  bool _loading = false;
  String? _error;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    _plugin = LinuxScreenshotPlugin(
      subprocessScriptPath:
          'linux/screenshot_subprocess/bin/main.dart',
    );
    if (Platform.isLinux) _startPlugin();
  }

  @override
  void dispose() {
    _plugin.stop();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Plugin lifecycle
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _startPlugin() async {
    setState(() {
      _statusMsg = 'Starting screenshot server…';
      _error = null;
    });
    try {
      await _plugin.start();
      setState(() => _statusMsg = 'Screenshot server ready.');
    } catch (e) {
      setState(() {
        _error = 'Failed to start subprocess: $e';
        _statusMsg = null;
      });
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Capture helpers
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _captureFullScreen() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusMsg = 'Capturing full screen…';
    });
    try {
      final bytes = await _plugin.captureScreen(interactive: false);
      setState(() {
        _screenshot = bytes;
        _loading = false;
        _statusMsg = 'Full-screen capture done.';
      });
    } on ScreenshotException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
        _statusMsg = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _statusMsg = null;
      });
    }
  }

  Future<void> _captureInteractive() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusMsg = 'Select a region with the mouse…';
    });
    try {
      final bytes =
          await _plugin.captureScreen(interactive: true);
      if (bytes == null) {
        setState(() {
          _loading = false;
          _statusMsg = 'Capture cancelled.';
        });
        return;
      }
      setState(() {
        _screenshot = bytes;
        _loading = false;
        _statusMsg = 'Region captured.';
      });
    } on ScreenshotException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
        _statusMsg = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _statusMsg = null;
      });
    }
  }

  /// QQ-style: capture the full screen first, then show the Flutter overlay
  /// for in-app region selection and cropping.
  Future<void> _captureQqStyle() async {
    setState(() {
      _loading = true;
      _error = null;
      _statusMsg = 'Capturing full screen…';
    });

    Uint8List? fullScreenBytes;
    try {
      fullScreenBytes =
          await _plugin.captureScreen(interactive: false);
    } on ScreenshotException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
        _statusMsg = null;
      });
      return;
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _statusMsg = null;
      });
      return;
    }

    if (fullScreenBytes == null) {
      setState(() {
        _loading = false;
        _statusMsg = 'Capture cancelled.';
      });
      return;
    }

    setState(() {
      _loading = false;
      _statusMsg = 'Drag to select a region…';
    });

    // Push the overlay on top of the current page.
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, _, __) => ScreenshotOverlayPage(
          screenshot: fullScreenBytes!,
          onCapture: (ScreenshotSelection sel) async {
            setState(() {
              _loading = true;
              _statusMsg = 'Cropping selection…';
            });
            try {
              final cropped = await sel.cropBytes();
              setState(() {
                _screenshot = cropped;
                _loading = false;
                _statusMsg =
                    'Captured ${sel.rect.width.toInt()}×'
                    '${sel.rect.height.toInt()} px.';
              });
            } catch (e) {
              setState(() {
                _error = 'Crop error: $e';
                _loading = false;
                _statusMsg = null;
              });
            }
          },
          onCancel: () => setState(() {
            _statusMsg = 'Cancelled.';
            _loading = false;
          }),
        ),
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    if (_screenshot == null) return;
    // On Linux, copying image bytes to the clipboard requires a native
    // implementation (e.g. xclip / wl-copy).  Here we notify the user that
    // the image is available as bytes.
    await Clipboard.setData(
        const ClipboardData(text: '<screenshot captured – see image below>'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Image captured. Integrate xclip/wl-copy to copy to clipboard.')),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) {
      return Scaffold(
        appBar: AppBar(title: const Text('Linux Screenshot')),
        body: const Center(
          child: Text(
            'This feature is only available on Linux.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux Screenshot (QQ Style)'),
        actions: [
          if (_screenshot != null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy to clipboard',
              onPressed: _copyToClipboard,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Buttons ──────────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _loading ? null : _captureFullScreen,
                  icon: const Icon(Icons.fullscreen),
                  label: const Text('Full Screen'),
                ),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _captureInteractive,
                  icon: const Icon(Icons.crop),
                  label: const Text('Select Region (native)'),
                ),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _captureQqStyle,
                  icon: const Icon(Icons.screenshot),
                  label: const Text('QQ-Style Overlay'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // ── Status / Error ────────────────────────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          if (_statusMsg != null && !_loading)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _statusMsg!,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // ── Preview ───────────────────────────────────────────────────────
          if (_screenshot != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _screenshot!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            )
          else if (!_loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.screenshot,
                        size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No screenshot yet.\n'
                      'Press one of the buttons above to capture.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
