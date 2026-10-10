import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'ui.dart';

/// QR codes are dark on white in both themes, since that is what scanners
/// read best.
const _qrDark = Color(0xFF141414);

/// [data] as a QR code, made on the device.
class QrTile extends StatelessWidget {
  const QrTile(
    this.data, {
    super.key,
    required this.label,
    this.size = 236,
    this.errorCorrectLevel = QrErrorCorrectLevel.medium,
  });

  final String data;

  /// What a screen reader says the code is.
  final String label;
  final double size;

  /// Low lets a long text use larger modules.
  final QrErrorCorrectLevel errorCorrectLevel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: label,
    child: Container(
      width: size,
      height: size,
      // About 4 modules of white around the code, as QR readers expect.
      padding: EdgeInsets.all(size * 20 / 236),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: CustomPaint(painter: _QrPainter(data, errorCorrectLevel)),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data, QrErrorCorrectLevel errorCorrectLevel)
    : _qr = QrImage(
        QrCode(
          payload: QrPayload.fromString(data),
          errorCorrectLevel: errorCorrectLevel,
        ),
      );

  final String data;
  final QrImage _qr;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _qr.moduleCount;
    final module = size.shortestSide / n;
    final dark = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_qr.isDark(y, x)) {
          dark.addRect(Rect.fromLTWH(x * module, y * module, module, module));
        }
      }
    }
    // Without anti-aliasing, neighbouring modules meet with no hairline gap.
    canvas.drawPath(
      dark,
      Paint()
        ..color = _qrDark
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
