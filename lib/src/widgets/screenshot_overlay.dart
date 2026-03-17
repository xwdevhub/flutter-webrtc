import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A full-screen overlay widget that mimics the QQ screenshot experience.
///
/// The widget is given a full-screen [screenshot] (as raw PNG/JPEG bytes).
/// It displays the screenshot as the background with a semi-transparent dim,
/// then lets the user drag a rubber-band selection rectangle.  The selected
/// region remains at full brightness.
///
/// Once the user confirms their selection the [onCapture] callback receives a
/// [ScreenshotSelection] that holds the selection [Rect] and the original
/// [imageProvider].  Use [ScreenshotSelection.cropBytes] to get the cropped
/// PNG bytes.
///
/// Example
/// -------
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => ScreenshotOverlayPage(
///     screenshot: bytes,
///     onCapture: (sel) async {
///       final cropped = await sel.cropBytes();
///       // …use cropped bytes…
///     },
///   ),
/// ));
/// ```
class ScreenshotOverlayPage extends StatefulWidget {
  /// Raw PNG or JPEG bytes of the full-screen capture.
  final Uint8List screenshot;

  /// Called with the confirmed selection.  The callback receives a
  /// [ScreenshotSelection]; call [ScreenshotSelection.cropBytes] to get the
  /// cropped image.
  final void Function(ScreenshotSelection selection)? onCapture;

  /// Called when the user cancels (presses Escape or the ✕ button).
  final void Function()? onCancel;

  /// Opacity of the dim layer outside the selected region (0.0–1.0).
  final double dimOpacity;

  const ScreenshotOverlayPage({
    Key? key,
    required this.screenshot,
    this.onCapture,
    this.onCancel,
    this.dimOpacity = 0.5,
  }) : super(key: key);

  @override
  _ScreenshotOverlayPageState createState() => _ScreenshotOverlayPageState();
}

class _ScreenshotOverlayPageState extends State<ScreenshotOverlayPage> {
  // Raw selection in logical pixels (Flutter coordinate space).
  Offset? _start;
  Offset? _end;
  bool _confirmed = false;

  Rect? get _selection {
    if (_start == null || _end == null) return null;
    return Rect.fromPoints(_start!, _end!);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Keyboard
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return true;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter) {
      _confirm();
      return true;
    }
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Actions
  // ──────────────────────────────────────────────────────────────────────────

  void _cancel() {
    if (mounted) {
      Navigator.of(context).pop();
      widget.onCancel?.call();
    }
  }

  void _confirm() {
    final sel = _selection;
    if (sel == null || sel.isEmpty) return;
    if (_confirmed) return;
    _confirmed = true;

    final selection = ScreenshotSelection(
      rect: sel,
      screenshotBytes: widget.screenshot,
      screenSize: MediaQuery.of(context).size,
    );
    Navigator.of(context).pop();
    widget.onCapture?.call(selection);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Background: full-screen screenshot ──────────────────────────
          Positioned.fill(
            child: Image.memory(
              widget.screenshot,
              fit: BoxFit.fill,
            ),
          ),

          // ── Gesture detector (rubber-band) ──────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              cursor: SystemMouseCursors.crosshair,
              onPanStart: (d) {
                setState(() {
                  _start = d.localPosition;
                  _end = d.localPosition;
                });
              },
              onPanUpdate: (d) {
                setState(() => _end = d.localPosition);
              },
              onPanEnd: (_) {
                // Selection is kept; the toolbar will let the user confirm.
              },
              child: _selection != null
                  ? CustomPaint(
                      painter: _OverlayPainter(
                        selection: _selection!,
                        dimOpacity: widget.dimOpacity,
                      ),
                    )
                  : CustomPaint(
                      painter: _FullDimPainter(opacity: widget.dimOpacity),
                    ),
            ),
          ),

          // ── Toolbar (confirm / cancel) ───────────────────────────────────
          if (_selection != null && !_confirmed)
            _ToolbarWidget(
              selection: _selection!,
              screenSize: MediaQuery.of(context).size,
              onConfirm: _confirm,
              onCancel: _cancel,
              onReset: () => setState(() {
                _start = null;
                _end = null;
              }),
            ),

          // ── Size hint ───────────────────────────────────────────────────
          if (_selection != null && !_confirmed)
            Positioned(
              left: _selection!.left,
              top: _selection!.top - 22,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${_selection!.width.toInt()} × '
                  '${_selection!.height.toInt()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ),
            ),

          // ── ESC hint ────────────────────────────────────────────────────
          const Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Drag to select · Enter to confirm · Esc to cancel',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Toolbar widget
// ──────────────────────────────────────────────────────────────────────────────

class _ToolbarWidget extends StatelessWidget {
  final Rect selection;
  final Size screenSize;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onReset;

  const _ToolbarWidget({
    Key? key,
    required this.selection,
    required this.screenSize,
    required this.onConfirm,
    required this.onCancel,
    required this.onReset,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const toolbarH = 40.0;
    const toolbarW = 136.0;
    const margin = 6.0;

    // Position toolbar just below the selection, or above if it doesn't fit.
    double top = selection.bottom + margin;
    if (top + toolbarH > screenSize.height) {
      top = selection.top - toolbarH - margin;
    }
    double left = selection.right - toolbarW;
    if (left < margin) left = margin;

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: toolbarH,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarBtn(
                icon: Icons.refresh,
                tooltip: 'Reselect',
                onTap: onReset,
              ),
              const _Divider(),
              _ToolbarBtn(
                icon: Icons.close,
                tooltip: 'Cancel (Esc)',
                onTap: onCancel,
                color: Colors.red,
              ),
              const _Divider(),
              _ToolbarBtn(
                icon: Icons.check,
                tooltip: 'Confirm (Enter)',
                onTap: onConfirm,
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ToolbarBtn({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, size: 18, color: color ?? Colors.black87),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: Colors.grey.shade300);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Custom painters
// ──────────────────────────────────────────────────────────────────────────────

/// Dims the entire canvas.
class _FullDimPainter extends CustomPainter {
  final double opacity;
  const _FullDimPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withOpacity(opacity),
    );
  }

  @override
  bool shouldRepaint(_FullDimPainter old) => old.opacity != opacity;
}

/// Dims everything outside [selection]; draws a bright border around it.
class _OverlayPainter extends CustomPainter {
  final Rect selection;
  final double dimOpacity;

  const _OverlayPainter({
    required this.selection,
    required this.dimOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dim = Paint()..color = Colors.black.withOpacity(dimOpacity);

    // Draw dim in four rectangles around the selection (avoids xor issues).
    final rects = [
      Rect.fromLTRB(0, 0, full.width, selection.top),
      Rect.fromLTRB(0, selection.bottom, full.width, full.height),
      Rect.fromLTRB(0, selection.top, selection.left, selection.bottom),
      Rect.fromLTRB(
          selection.right, selection.top, full.width, selection.bottom),
    ];
    for (final r in rects) {
      if (!r.isEmpty) canvas.drawRect(r, dim);
    }

    // Selection border.
    canvas.drawRect(
      selection,
      Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Corner handles.
    _drawHandles(canvas, selection);
  }

  void _drawHandles(Canvas canvas, Rect r) {
    const len = 8.0;
    final paint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final corners = [
      // top-left
      [r.topLeft, r.topLeft + const Offset(len, 0)],
      [r.topLeft, r.topLeft + const Offset(0, len)],
      // top-right
      [r.topRight, r.topRight + const Offset(-len, 0)],
      [r.topRight, r.topRight + const Offset(0, len)],
      // bottom-left
      [r.bottomLeft, r.bottomLeft + const Offset(len, 0)],
      [r.bottomLeft, r.bottomLeft + const Offset(0, -len)],
      // bottom-right
      [r.bottomRight, r.bottomRight + const Offset(-len, 0)],
      [r.bottomRight, r.bottomRight + const Offset(0, -len)],
    ];

    for (final seg in corners) {
      canvas.drawLine(seg[0], seg[1], paint);
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.selection != selection || old.dimOpacity != dimOpacity;
}

// ──────────────────────────────────────────────────────────────────────────────
// Selection result
// ──────────────────────────────────────────────────────────────────────────────

/// Holds the result of a screenshot selection made in [ScreenshotOverlayPage].
class ScreenshotSelection {
  /// The selected rectangle in logical-pixel coordinates of the Flutter widget.
  final Rect rect;

  /// Raw bytes of the full-screen screenshot that was shown in the overlay.
  final Uint8List screenshotBytes;

  /// The screen size at the time of selection (logical pixels).
  final Size screenSize;

  const ScreenshotSelection({
    required this.rect,
    required this.screenshotBytes,
    required this.screenSize,
  });

  /// Decode the screenshot and crop it to [rect], returning PNG bytes.
  ///
  /// The method scales the selection from logical pixel space to the actual
  /// image resolution automatically.
  Future<Uint8List> cropBytes() async {
    final codec =
        await ui.instantiateImageCodec(screenshotBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final scaleX = img.width / screenSize.width;
    final scaleY = img.height / screenSize.height;

    final srcRect = Rect.fromLTRB(
      (rect.left * scaleX).clamp(0.0, img.width.toDouble()),
      (rect.top * scaleY).clamp(0.0, img.height.toDouble()),
      (rect.right * scaleX).clamp(0.0, img.width.toDouble()),
      (rect.bottom * scaleY).clamp(0.0, img.height.toDouble()),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dstRect = Rect.fromLTWH(0, 0, srcRect.width, srcRect.height);
    canvas.drawImageRect(img, srcRect, dstRect, Paint());
    final picture = recorder.endRecording();

    final cropped = await picture.toImage(
      srcRect.width.toInt(),
      srcRect.height.toInt(),
    );
    final byteData =
        await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to encode cropped image as PNG');
    }
    return byteData.buffer.asUint8List();
  }
}
