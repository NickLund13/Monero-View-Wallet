/// Screen 1a of the design: Scan wallet QR. Fills Setup from the Monero GUI's
/// View Only Wallet code or Feather's View-Only QR, and refuses any code that
/// carries a spend key or seed (lib/wallet_qr.dart).
///
/// The camera reads codes on the device. The picture is never saved, and the
/// decoded text is held in memory only until Setup's fields are filled.
library;

import 'package:flutter/material.dart';

import 'ui.dart';
import 'wallet_qr.dart';

/// The device's camera, reading QR codes.
abstract interface class QrCamera {
  /// Whether this app may use the camera. Asks the person the first time.
  Future<bool> allowed();

  /// Opens this app's page in the phone's Settings, where the camera can be
  /// turned back on.
  Future<void> openSettings();

  /// The live picture. It reads until it finds a QR code, hands that code's
  /// text to [onCode] and stops. Taking the widget away turns the camera off.
  Widget view(ValueChanged<String> onCode);
}

/// The camera Setup scans with, or null where the app has none, as in the
/// Windows test build: Setup then has no Scan QR code and stays typed.
QrCamera? qrCamera;

class ScanWalletScreen extends StatefulWidget {
  const ScanWalletScreen({super.key, required this.camera});

  final QrCamera camera;

  @override
  State<ScanWalletScreen> createState() => _ScanWalletScreenState();
}

class _ScanWalletScreenState extends State<ScanWalletScreen> {
  /// Null until the person has answered whether the app may use the camera.
  bool? _allowed;
  Refusal? _refusal;

  /// True from the first code the camera hands over until Scan again: the
  /// screen reads one code per scan.
  bool _read = false;

  /// Each scan gets a camera view of its own.
  int _scan = 0;

  @override
  void initState() {
    super.initState();
    widget.camera.allowed().then((allowed) {
      if (mounted) setState(() => _allowed = allowed);
    });
  }

  void _onCode(String code) {
    if (_read || !mounted) return;
    _read = true;
    try {
      final wallet = readWalletQr(code);
      Navigator.pop(context, wallet);
    } on RefusedCode catch (e) {
      // The camera view goes, which turns the camera off.
      setState(() => _refusal = e.reason);
    }
  }

  void _scanAgain() => setState(() {
    _refusal = null;
    _read = false;
    _scan++;
  });

  void _typeIn() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final refusal = _refusal;
    final live = _allowed == true && refusal == null;
    return Screen(
      title: 'Scan wallet QR',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IN THE MONERO GUI',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 0.52,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 8),
              const _Step('1', Text('Settings → Wallet → Show seed & keys')),
              const _Step('2', Text('Enter your wallet password')),
              _Step(
                '3',
                Text.rich(
                  TextSpan(
                    text: 'Under Export wallet, choose ',
                    children: [
                      TextSpan(
                        text: 'View Only Wallet',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Note(
          'The GUI opens on the Spendable Wallet code. It holds your spend '
          'key, so this app refuses it.',
        ),
        _Viewfinder(
          live: live,
          label: switch (_allowed) {
            null => '',
            false => 'Camera off',
            true => 'Camera paused',
          },
          camera: live
              ? KeyedSubtree(
                  key: ValueKey(_scan),
                  child: widget.camera.view(_onCode),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (_allowed == false) ...[
          Text(
            'The camera is off for this app.',
            textAlign: TextAlign.center,
            style: context.body,
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: widget.camera.openSettings,
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: _typeIn,
                child: const Text('Type it in instead'),
              ),
            ],
          ),
        ] else if (refusal != null)
          _RefusalCard(refusal, onScanAgain: _scanAgain, onTypeIn: _typeIn)
        else if (_allowed == true) ...[
          Text(
            'Hold the View Only Wallet code inside the frame.',
            textAlign: TextAlign.center,
            style: context.body,
          ),
          const SizedBox(height: 6),
          Text(
            'The picture stays on this iPhone and is never saved.',
            textAlign: TextAlign.center,
            style: context.caption,
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Feather Wallet works too: Wallet → View-Only → Show QR.',
          textAlign: TextAlign.center,
          style: context.caption,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final String number;
  final Widget text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Text(
            number,
            style: mono(color: context.colors.accentText).copyWith(height: 1.4),
          ),
        ),
        Expanded(
          child: DefaultTextStyle.merge(style: context.body, child: text),
        ),
      ],
    ),
  );
}

/// The camera's picture in a rounded frame, with corner guides that are
/// orange while it reads and grey while it is off.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.live,
    required this.label,
    required this.camera,
  });

  final bool live;
  final String label;
  final Widget? camera;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 230,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: dark ? const Color(0xFF050506) : const Color(0xFF1A1B1E),
            ),
            if (camera case final camera?)
              camera
            else
              Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A8C93),
                  ),
                ),
              ),
            IgnorePointer(
              child: CustomPaint(
                painter: _Corners(
                  live ? AppColors.accent : context.colors.chev,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Corners extends CustomPainter {
  _Corners(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const side = 170.0, arm = 40.0, radius = 10.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    for (final (corner, dx, dy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * arm)
          ..lineTo(corner.dx, corner.dy + dy * radius)
          ..arcToPoint(
            Offset(corner.dx + dx * radius, corner.dy),
            radius: const Radius.circular(radius),
            clockwise: dx * dy > 0,
          )
          ..lineTo(corner.dx + dx * arm, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Corners oldDelegate) => oldDelegate.color != color;
}

class _RefusalCard extends StatelessWidget {
  const _RefusalCard(
    this.refusal, {
    required this.onScanAgain,
    required this.onTypeIn,
  });

  final Refusal refusal;
  final VoidCallback onScanAgain;
  final VoidCallback onTypeIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (
      String title,
      String body,
      bool typeIn,
      Color icon,
    ) = switch (refusal) {
      Refusal.spendKey => (
        'That code holds your spend key',
        'Nothing from it was kept. In the GUI, choose View Only Wallet '
            "and scan that code. This app can't send, so it never takes "
            'a spend key.',
        false,
        c.red,
      ),
      Refusal.notWalletCode => (
        'Not a wallet code',
        'Scan the View Only Wallet code under Export wallet in the '
            "Monero GUI, or Feather's View-Only QR.",
        true,
        c.amber,
      ),
      Refusal.testnet => (
        'This is a test network wallet',
        'The address is for testnet. This app watches mainnet and '
            'stagenet wallets.',
        false,
        c.amber,
      ),
      Refusal.keyMismatch => (
        "This key isn't this address's view key",
        'Nothing from the code was kept. Scan the View Only Wallet code '
            'again.',
        true,
        c.red,
      ),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.btn2,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded, size: 20, color: icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: context.body.copyWith(fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onScanAgain,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Scan again'),
                ),
              ),
              if (typeIn) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onTypeIn,
                    style: context.secondaryButton.copyWith(
                      backgroundColor: WidgetStatePropertyAll(c.btn2),
                      minimumSize: const WidgetStatePropertyAll(
                        Size.fromHeight(44),
                      ),
                    ),
                    child: const Text('Type it in instead'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
