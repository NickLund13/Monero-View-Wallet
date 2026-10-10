/// Screen 5 of the design: "Key images by QR", for a signing device that holds
/// the spend key and uses Monero's animated QR codes (UR), as Passport with
/// Cake Signer and Feather's offline signing do:
///
/// 1. The app shows the wallet's outputs as an animated `xmr-output` code, and
///    the signing device reads it and works out their key images.
/// 2. The signing device shows them as an animated `xmr-keyimage` code, which
///    the app reads part by part (lib/ur.dart) and imports the way it imports
///    a key images file.
///
/// The wallet library encrypts both with the view key, so only a device with
/// this wallet's keys can read them. The parts read are held in memory only,
/// until the key images are imported or the screen goes; nothing is written
/// to a file. The camera picture is never saved. A code that might carry a
/// spend key or seed is refused, as at setup.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'key_images_screen.dart';
import 'lock.dart';
import 'qr_tile.dart';
import 'scan_screen.dart';
import 'session.dart';
import 'ui.dart';
import 'ur.dart';
import 'wallet.dart';
import 'wallet_qr.dart';

/// How long each part of the outputs code shows: five parts a second.
const partEvery = Duration(milliseconds: 200);

/// What a key images code holds starts with this, as a key images file does.
final _keyImagesMagic = ascii.encode('Monero key image export');

enum _Refusal {
  /// The code might carry a spend key or seed.
  spendKey,

  /// Not the signing device's key images code.
  notKeyImages,
}

class KeyImagesQrScreen extends StatefulWidget {
  const KeyImagesQrScreen(this.session, {super.key, required this.camera});

  final WalletSession session;
  final QrCamera camera;

  @override
  State<KeyImagesQrScreen> createState() => _KeyImagesQrScreenState();
}

class _KeyImagesQrScreenState extends State<KeyImagesQrScreen> {
  /// 1 shows the outputs, 2 reads the key images.
  int _step = 1;

  /// The outputs code, once made.
  OutputsQr? _outputs;
  bool _making = false;
  bool _makingFailed = false;

  /// Shows every output, not only those from the first without a key image.
  bool _all = false;
  int _part = 0;
  Timer? _animation;

  /// Null until the person has answered whether the app may use the camera.
  bool? _allowed;
  var _reader = UrReader('xmr-keyimage');
  _Refusal? _refusal;

  /// True while the key images read are imported, or wait on the Import
  /// problem screen.
  bool _importing = false;

  /// Each scan gets a camera view of its own.
  int _scan = 0;
  bool _screenOn = false;
  final _lock = appLock;

  WalletSession get _s => widget.session;

  List<String>? get _parts {
    final outputs = _outputs;
    if (outputs == null) return null;
    return _all ? outputs.all : outputs.fresh;
  }

  @override
  void initState() {
    super.initState();
    _s.addListener(_makeWhenReady);
    _lock.addListener(_keepScreenOn);
    _makeWhenReady();
    _keepScreenOn();
  }

  @override
  void dispose() {
    _animation?.cancel();
    _s.removeListener(_makeWhenReady);
    _lock.removeListener(_keepScreenOn);
    if (_screenOn) widget.camera.keepScreenOn(false).ignore();
    super.dispose();
  }

  /// The screen stays on while this screen is open, for the other device to
  /// read the code and for this one to read its code back, unless the app
  /// locks.
  void _keepScreenOn() {
    final on = !_lock.locked;
    if (on == _screenOn) return;
    _screenOn = on;
    widget.camera.keepScreenOn(on).ignore();
  }

  /// The code has to hold every output this device can find, so it is made
  /// once sync has caught up.
  Future<void> _makeWhenReady() async {
    final s = _s;
    if (_outputs != null || _making || _makingFailed) return;
    if (!s.scanned || s.catchingUp || s.importing || s.rescanning) return;
    _making = true;
    try {
      final outputs = await s.outputsQr();
      if (!mounted) return;
      setState(() {
        _outputs = outputs;
        // With a key image for every output, only all of them make a code
        // worth showing.
        _all = outputs.freshCount == 0;
        _part = 0;
      });
      _animate();
    } catch (_) {
      // A WalletException from the library, or anything unexpected: the
      // screen must not stay on "Making the code…".
      if (mounted) setState(() => _makingFailed = true);
    } finally {
      _making = false;
    }
  }

  void _tryAgain() {
    setState(() => _makingFailed = false);
    _makeWhenReady();
  }

  /// Steps through the parts while step 1 shows a code of more than one.
  void _animate() {
    final parts = _parts;
    if (_step == 1 && parts != null && parts.length > 1) {
      _animation ??= Timer.periodic(partEvery, (_) {
        final parts = _parts;
        if (parts == null || !mounted) return;
        setState(() => _part = (_part + 1) % parts.length);
      });
    } else {
      _animation?.cancel();
      _animation = null;
    }
  }

  void _showAll(bool all) {
    setState(() {
      _all = all;
      _part = 0;
    });
    _animate();
  }

  Future<void> _toScanning() async {
    setState(() => _step = 2);
    _animate();
    if (_allowed != null) return;
    final allowed = await widget.camera.allowed();
    if (mounted) setState(() => _allowed = allowed);
  }

  void _showOutputs() {
    setState(() {
      _step = 1;
      _part = 0;
      _refusal = null;
      _scan++;
    });
    _animate();
  }

  void _scanAgain() => setState(() {
    _refusal = null;
    _scan++;
  });

  void _onPart(String text) {
    if (!mounted || _step != 2 || _refusal != null || _importing) return;
    if (carriesSpendAuthority(text)) {
      setState(() => _refusal = _Refusal.spendKey);
      return;
    }
    if (urType(text) != _reader.type) {
      setState(() => _refusal = _Refusal.notKeyImages);
      return;
    }
    if (!_reader.add(text)) return;
    setState(() {});
    if (_reader.complete) _import();
  }

  /// Imports the key images read, or explains why not, as for a file.
  Future<void> _import() async {
    final bytes = _reader.bytes;
    final code = _reader.asOneCode;
    final isKeyImages =
        bytes != null &&
        bytes.length > _keyImagesMagic.length &&
        Iterable.generate(_keyImagesMagic.length)
            .every((i) => bytes[i] == _keyImagesMagic[i]);
    if (!isKeyImages) {
      setState(() {
        _refusal = _Refusal.notKeyImages;
        _reader = UrReader('xmr-keyimage');
      });
      return;
    }
    setState(() => _importing = true);
    var outcome = ImportOutcome.cancelled;
    try {
      outcome = await importOrExplain(
        context,
        _s,
        source: (name: byQr, size: bytes.length, scanned: true),
        import: () => _s.importScannedKeyImages(code),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _reader = UrReader('xmr-keyimage');
          _scan++;
        });
      }
    }
    // Imported, or given up: back to Import key images. Otherwise the person
    // asked to scan again.
    if (mounted && outcome != ImportOutcome.another) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _s,
    builder: (context, _) => PopScope(
      canPop: !_importing,
      child: Screen(
        title: 'Key images by QR',
        canGoBack: !_importing,
        bottom: _step == 1
            ? FilledButton(
                onPressed: _outputs == null ? null : _toScanning,
                child: const Text('Next: scan key images'),
              )
            : FilledButton(
                onPressed: _importing ? null : _showOutputs,
                style: context.secondaryButton,
                child: const Text('Show outputs again'),
              ),
        children: [
          _Steps(_step),
          const SizedBox(height: 16),
          if (_step == 1) ..._outputsStep(context) else ..._scanStep(context),
          const SizedBox(height: 24),
          Text(
            "The Monero GUI can't make these codes. Import its key images "
            'as a file instead.',
            textAlign: TextAlign.center,
            style: context.caption,
          ),
        ],
      ),
    ),
  );

  List<Widget> _outputsStep(BuildContext context) {
    final c = context.colors;
    final s = _s;
    final outputs = _outputs;
    final parts = _parts;
    const size = 296.0;
    return [
      Text(
        "Scan this code with the signing device. It holds this wallet's "
        'outputs, encrypted with the view key, so the device can work out '
        'their key images.',
        style: context.body,
      ),
      const SizedBox(height: 16),
      Center(
        child: outputs != null && parts != null
            ? QrTile(
                parts[_part % parts.length],
                label: 'Animated QR code of the outputs',
                size: size,
                errorCorrectLevel: QrErrorCorrectLevel.low,
              )
            : Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _makingFailed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "The code couldn't be made.",
                            textAlign: TextAlign.center,
                            style: context.body,
                          ),
                          TextButton(
                            onPressed: _tryAgain,
                            child: const Text('Try again'),
                          ),
                        ],
                      )
                    : Text(
                        !s.scanned || s.catchingUp
                            ? 'Finishing sync first · '
                                  '${plural(s.blocksToGo, 'block')} to go. '
                                  'The code needs every output.'
                            : 'Making the code…',
                        textAlign: TextAlign.center,
                        style: context.body,
                      ),
              ),
      ),
      if (outputs != null && parts != null) ...[
        const SizedBox(height: 10),
        Text(
          parts.length > 1
              ? 'Animated code · part ${_part % parts.length + 1} of '
                    '${parts.length} · screen stays on'
              : 'One code · screen stays on',
          textAlign: TextAlign.center,
          style: mono(size: 13, color: c.muted),
        ),
        const SizedBox(height: 4),
        Text(
          outputs.count == 0
              ? 'No outputs found yet.'
              : _all
              ? 'All ${plural(outputs.count, 'output')}'
              : '${plural(outputs.freshCount, 'output')}, from the first '
                    'without a key image',
          textAlign: TextAlign.center,
          style: context.caption,
        ),
        if (outputs.freshCount > 0 && outputs.freshCount < outputs.count) ...[
          const SizedBox(height: 12),
          SwitchRow(
            title: 'All outputs',
            caption:
                "For a signing device that hasn't read this wallet's "
                'outputs before, or says some are missing.',
            value: _all,
            onChanged: _showAll,
          ),
        ],
      ],
    ];
  }

  List<Widget> _scanStep(BuildContext context) {
    final c = context.colors;
    final refusal = _refusal;
    final live = _allowed == true && refusal == null && !_importing;
    final known = _reader.partsKnown;
    final total = _reader.partsTotal;
    return [
      Text(
        'Scan the animated code the signing device shows once it has read '
        'the outputs.',
        style: context.body,
      ),
      const SizedBox(height: 16),
      Viewfinder(
        live: live,
        label: switch (_allowed) {
          null => '',
          false => 'Camera off',
          true when _importing => 'Importing…',
          true => 'Camera paused',
        },
        camera: live
            ? KeyedSubtree(
                key: ValueKey(_scan),
                child: widget.camera.view(_onPart, animated: true),
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
        Center(
          child: TextButton(
            onPressed: widget.camera.openSettings,
            child: const Text('Open Settings'),
          ),
        ),
      ] else if (refusal != null)
        ScanProblemCard(
          title: switch (refusal) {
            _Refusal.spendKey => 'That code may hold a spend key or seed',
            _Refusal.notKeyImages => 'Not a key images code',
          },
          body: switch (refusal) {
            _Refusal.spendKey =>
              "Nothing from it was kept. This app can't send, so it never "
                  'takes a spend key or seed. Scan the key images code the '
                  'signing device shows.',
            _Refusal.notKeyImages =>
              'Scan the animated code the signing device shows once it has '
                  'read the outputs.',
          },
          color: refusal == _Refusal.spendKey ? c.red : c.amber,
          onScanAgain: _scanAgain,
        )
      else if (_allowed == true) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: total == 0 ? 0 : known / total,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          total == 0
              ? 'Hold the code inside the frame.'
              : '$known of $total parts scanned',
          textAlign: TextAlign.center,
          style: mono(size: 13, color: c.muted),
        ),
        const SizedBox(height: 6),
        Text(
          'The picture stays on this iPhone and is never saved.',
          textAlign: TextAlign.center,
          style: context.caption,
        ),
      ],
    ];
  }
}

/// The two steps, the current one picked out.
class _Steps extends StatelessWidget {
  const _Steps(this.step);

  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (final (n, label) in [(1, 'Show outputs'), (2, 'Scan key images')])
          Expanded(
            child: Semantics(
              selected: n == step,
              child: Container(
                height: 36,
                margin: EdgeInsets.only(
                  left: n == 1 ? 0 : 4,
                  right: n == 1 ? 4 : 0,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: n == step ? c.seg : c.btn2,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '$n  $label',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: n == step ? c.text : c.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
