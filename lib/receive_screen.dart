import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'qr_tile.dart';
import 'session.dart';
import 'ui.dart';
import 'wallet.dart';

/// Screen 8 of the design: "Receive", a subaddress nobody has paid yet, to
/// give one payer.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen(this.session, {super.key});

  final WalletSession session;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  late int _index;
  late String _address;
  final _label = TextEditingController();
  bool _copied = false;

  WalletSession get _s => widget.session;

  /// Flutter's engine opens the phone's share sheet on iOS and Android. The
  /// Windows test build has none, so it offers Copy only.
  bool get _canShare =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _show(_s.freshSubaddress());
  }

  @override
  void dispose() {
    // Keeps the subaddress made here, and its label, for the next launch.
    _s.save();
    _label.dispose();
    super.dispose();
  }

  void _show(int index) {
    _index = index;
    _address = _s.wallet.subaddress(index);
    _label.text = _s.wallet.label(index);
    _copied = false;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _address));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _share() =>
      SystemChannels.platform.invokeMethod('Share.invoke', _address);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _s,
    builder: (context, _) {
      final c = context.colors;
      final paid = _s.paidSubaddresses.contains(_index);
      final canAdd = _s.canAddSubaddress;
      return Screen(
        title: 'Receive',
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subaddress #$_index',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        paid
                            ? 'Paid already · tap New for the next payer'
                            : 'New · not used yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: paid ? c.muted : c.green,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: canAdd
                      ? () => setState(() => _show(_s.wallet.addSubaddress()))
                      : null,
                  style: TextButton.styleFrom(
                    backgroundColor: c.btn2,
                    foregroundColor: c.text,
                    disabledBackgroundColor: c.btn2,
                    disabledForegroundColor: c.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'New',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          if (!canAdd)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No more new ones for now. The app stays within '
                '$receiveAhead of the last one paid, so the Monero GUI sees '
                'payments to them: it looks ${defaultLookahead.addresses} ahead, '
                'but only moves on as payments confirm.',
                style: context.caption,
              ),
            ),
          const SizedBox(height: 16),
          Center(child: QrTile(_address, label: 'QR code of the subaddress')),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                _address,
                textAlign: TextAlign.center,
                style: mono(size: 13, color: c.text).copyWith(height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _copy,
                  style: _buttonStyle,
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                  label: Text(_copied ? 'Copied' : 'Copy'),
                ),
              ),
              if (_canShare) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _share,
                    style: _buttonStyle.copyWith(
                      backgroundColor: WidgetStatePropertyAll(c.card),
                      foregroundColor: WidgetStatePropertyAll(c.text),
                    ),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text('Label (kept on this phone)', style: context.caption),
          const SizedBox(height: 6),
          TextField(
            key: const Key('label'),
            controller: _label,
            onChanged: (label) => _s.wallet.setLabel(_index, label),
            textCapitalization: TextCapitalization.sentences,
            // Keeps the keyboard from learning the label (Android).
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              hintText: 'e.g. Rent from Alex',
              fillColor: c.card,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 10),
                child: Icon(Icons.info_outline, size: 18, color: c.muted),
              ),
              Expanded(
                child: Text(
                  "Give each payer a new subaddress so their payments can't "
                  'be linked. The Monero GUI sees payments to it too, just '
                  'not the label. It numbers subaddresses the same way, so '
                  'skip any number you already gave out from it.',
                  style: context.body.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  static final _buttonStyle = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
