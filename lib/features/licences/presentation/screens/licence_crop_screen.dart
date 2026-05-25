import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';

/// Full-screen, native Flutter crop UI.
///
/// Shows the captured photo with a draggable crop rectangle so the user
/// can frame just the licence card before OCR. Returns the cropped JPEG
/// bytes, or `null` if the user cancels.
///
/// Works identically on web and native — no JS bridge, no platform plugin.
/// Replaces [ImageCropper] on web, which has a Flutter web interop bug
/// where its confirm button resolves to `null`.
///
/// Usage:
/// ```dart
/// final cropped = await Navigator.of(context).push<Uint8List>(
///   MaterialPageRoute(
///     fullscreenDialog: true,
///     builder: (_) => LicenceCropScreen(imageBytes: pickedBytes),
///   ),
/// );
/// if (cropped == null) return; // user cancelled
/// ```
class LicenceCropScreen extends StatefulWidget {
  const LicenceCropScreen({super.key, required this.imageBytes});

  /// Raw bytes of the picked image. Any format that the `image` package
  /// can decode (JPEG, PNG, WEBP, GIF) is accepted.
  final Uint8List imageBytes;

  @override
  State<LicenceCropScreen> createState() => _LicenceCropScreenState();
}

class _LicenceCropScreenState extends State<LicenceCropScreen> {
  // Image dimensions — loaded via dart:ui (hardware-accelerated decode
  // of just the header, not the full pixel data).
  double _imgW = 0;
  double _imgH = 0;

  // Crop rectangle in normalised image space [0, 1].
  // Initialised to a centred rectangle at ~85 % width; _loadImageSize
  // refines the height to match the ID-1 card aspect ratio (1.586:1).
  Rect _crop = const Rect.fromLTWH(0.075, 0.2, 0.85, 0.6);

  // Actual size of the image-display area (set on first layout pass).
  Size _containerSize = Size.zero;

  // Index of the corner handle being dragged [0=TL, 1=TR, 2=BR, 3=BL].
  int? _activeHandle;

  // True while the image is being decoded and re-encoded after confirm.
  bool _processing = false;

  // Logical-pixel radius for corner-handle hit detection.
  static const double _hitRadius = 28;

  @override
  void initState() {
    super.initState();
    unawaited(_loadImageSize());
  }

  /// Decode only the image header via dart:ui to get width/height, then
  /// adjust the default crop to match the ID-1 card aspect ratio.
  Future<void> _loadImageSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
      if (!mounted || w == 0 || h == 0) return;
      const cardAspect = 1.586; // ISO/IEC 7810 ID-1
      const cropW = 0.85;
      final cropH = (cropW * w / cardAspect / h).clamp(0.1, 0.9);
      final cropT = ((1 - cropH) / 2).clamp(0.05, 0.45);
      setState(() {
        _imgW = w;
        _imgH = h;
        _crop = Rect.fromLTWH(0.075, cropT, cropW, cropH);
      });
    } catch (_) {
      // If header decode fails, keep the default crop. The full decode in
      // _confirm() will still work or return the original bytes as fallback.
    }
  }

  // ---------------------------------------------------------------------------
  // Coordinate helpers
  // ---------------------------------------------------------------------------

  /// Screen rect where the image is drawn (BoxFit.contain letterboxing).
  Rect get _displayRect {
    if (_imgW == 0 ||
        _imgH == 0 ||
        _containerSize.width == 0 ||
        _containerSize.height == 0) {
      return Rect.fromLTWH(
        0,
        0,
        _containerSize.width,
        _containerSize.height,
      );
    }
    final imgAspect = _imgW / _imgH;
    final ctnAspect = _containerSize.width / _containerSize.height;
    final double dw, dh;
    if (imgAspect > ctnAspect) {
      dw = _containerSize.width;
      dh = dw / imgAspect;
    } else {
      dh = _containerSize.height;
      dw = dh * imgAspect;
    }
    return Rect.fromLTWH(
      (_containerSize.width - dw) / 2,
      (_containerSize.height - dh) / 2,
      dw,
      dh,
    );
  }

  /// Normalised crop → screen-space rect.
  Rect get _screenCrop {
    final d = _displayRect;
    return Rect.fromLTRB(
      d.left + _crop.left * d.width,
      d.top + _crop.top * d.height,
      d.left + _crop.right * d.width,
      d.top + _crop.bottom * d.height,
    );
  }

  // ---------------------------------------------------------------------------
  // Gesture handling
  // ---------------------------------------------------------------------------

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    final corners = [
      _screenCrop.topLeft,
      _screenCrop.topRight,
      _screenCrop.bottomRight,
      _screenCrop.bottomLeft,
    ];
    for (var i = 0; i < corners.length; i++) {
      if ((pos - corners[i]).distance <= _hitRadius) {
        setState(() => _activeHandle = i);
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == null) return;
    final dr = _displayRect;
    if (dr.width == 0 || dr.height == 0) return;
    final dx = details.delta.dx / dr.width;
    final dy = details.delta.dy / dr.height;
    const minDim = 0.1;
    setState(() {
      var l = _crop.left;
      var t = _crop.top;
      var r = _crop.right;
      var b = _crop.bottom;
      switch (_activeHandle) {
        case 0: // TL
          l = (l + dx).clamp(0.0, r - minDim);
          t = (t + dy).clamp(0.0, b - minDim);
        case 1: // TR
          r = (r + dx).clamp(l + minDim, 1.0);
          t = (t + dy).clamp(0.0, b - minDim);
        case 2: // BR
          r = (r + dx).clamp(l + minDim, 1.0);
          b = (b + dy).clamp(t + minDim, 1.0);
        case 3: // BL
          l = (l + dx).clamp(0.0, r - minDim);
          b = (b + dy).clamp(t + minDim, 1.0);
        default:
          break;
      }
      _crop = Rect.fromLTRB(l, t, r, b);
    });
  }

  void _onPanEnd(DragEndDetails _) => setState(() => _activeHandle = null);

  // ---------------------------------------------------------------------------
  // Confirm — decode, crop, encode
  // ---------------------------------------------------------------------------

  Future<void> _confirm() async {
    setState(() => _processing = true);
    try {
      // Full decode via the `image` package (pure Dart — platform-agnostic).
      final decoded = img.decodeImage(widget.imageBytes);
      if (decoded == null) {
        // Decode failed — return original so the user can still proceed to OCR.
        if (mounted) Navigator.of(context).pop(widget.imageBytes);
        return;
      }
      final x = (_crop.left * decoded.width).round().clamp(0, decoded.width - 1);
      final y = (_crop.top * decoded.height).round().clamp(0, decoded.height - 1);
      final w = (_crop.width * decoded.width)
          .round()
          .clamp(1, decoded.width - x);
      final h = (_crop.height * decoded.height)
          .round()
          .clamp(1, decoded.height - y);
      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      // Re-encode as JPEG (85 % quality matches the picker's imageQuality).
      final jpeg = img.encodeJpg(cropped, quality: 85);
      if (mounted) Navigator.of(context).pop(Uint8List.fromList(jpeg));
    } catch (_) {
      // Crop failed — return original so the user isn't blocked.
      if (mounted) Navigator.of(context).pop(widget.imageBytes);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Title bar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.md,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Frame your licence',
                      style: EqTypography.headingM.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: EqColours.sky, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),

            // ── Image + crop overlay ─────────────────────────────────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  // Capture container size on every layout pass. Uses a
                  // post-frame callback to avoid setState during build.
                  if (_containerSize != size) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) {
                        if (mounted) setState(() => _containerSize = size);
                      },
                    );
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                        CustomPaint(
                          painter: _CropPainter(
                            crop: _crop,
                            displayRect: _displayRect,
                            activeHandle: _activeHandle,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // ── Hint + action ────────────────────────────────────────────
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(
                EqSpacing.md,
                EqSpacing.sm,
                EqSpacing.md,
                EqSpacing.lg,
              ),
              child: Column(
                children: [
                  Text(
                    'Drag the corner handles to frame the card, then tap Scan.',
                    style: EqTypography.label.copyWith(color: Colors.white60),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _processing ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: EqColours.sky,
                        disabledBackgroundColor:
                            EqColours.sky.withValues(alpha: 0.5),
                        padding:
                            const EdgeInsets.symmetric(vertical: EqSpacing.md),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _processing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Scan licence',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter — dim + border + corner brackets
// ---------------------------------------------------------------------------

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.crop,
    required this.displayRect,
    required this.activeHandle,
  });

  final Rect crop;
  final Rect displayRect;
  final int? activeHandle;

  /// Normalised crop → screen rect, clipped to the canvas.
  Rect _screenCrop(Size canvasSize) {
    final d = displayRect.isEmpty
        ? Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height)
        : displayRect;
    return Rect.fromLTRB(
      d.left + crop.left * d.width,
      d.top + crop.top * d.height,
      d.left + crop.right * d.width,
      d.top + crop.bottom * d.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sr = _screenCrop(size);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);

    // Four dim rects outside the crop area.
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, sr.top), dim)
      ..drawRect(
        Rect.fromLTRB(0, sr.bottom, size.width, size.height),
        dim,
      )
      ..drawRect(Rect.fromLTRB(0, sr.top, sr.left, sr.bottom), dim)
      ..drawRect(
        Rect.fromLTRB(sr.right, sr.top, size.width, sr.bottom),
        dim,
      );

    // Crop border.
    canvas.drawRect(
      sr,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Corner L-brackets — more precise than circles for alignment.
    const armLen = 18.0;
    final bracketPaint = Paint()
      ..color = EqColours.sky
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    void bracket(Offset corner, double hDir, double vDir) {
      canvas
        ..drawLine(corner, corner + Offset(hDir * armLen, 0), bracketPaint)
        ..drawLine(corner, corner + Offset(0, vDir * armLen), bracketPaint);
    }

    bracket(sr.topLeft, 1, 1);
    bracket(sr.topRight, -1, 1);
    bracket(sr.bottomRight, -1, -1);
    bracket(sr.bottomLeft, 1, -1);

    // Highlight the active handle.
    if (activeHandle != null) {
      final corners = [
        sr.topLeft,
        sr.topRight,
        sr.bottomRight,
        sr.bottomLeft,
      ];
      canvas.drawCircle(
        corners[activeHandle!],
        12,
        Paint()..color = EqColours.sky.withValues(alpha: 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      crop != old.crop ||
      displayRect != old.displayRect ||
      activeHandle != old.activeHandle;
}
