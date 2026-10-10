import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'session.dart';
import 'ui.dart';
import 'wallet.dart';

/// Where a payment went, one entry per subaddress: 0 is the primary address,
/// and the label is the one given on Receive, or empty. Nothing for spends,
/// nor for payments to another account, whose subaddresses the app doesn't
/// show.
List<(int, String)> paidTo(WalletSession session, Transfer t) => [
  if (t.incoming)
    for (final i in t.subaddresses.toList()..sort())
      (i, i == 0 ? '' : session.wallet.label(i)),
];

/// Screen 9 of the design: one transaction, opened by tapping it on Home. It
/// follows the wallet, so the confirmations go up while it is open.
class TransactionScreen extends StatefulWidget {
  const TransactionScreen(this.session, this.transfer, {super.key});

  final WalletSession session;
  final Transfer transfer;

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  bool _copied = false;

  Future<void> _copy(String hash) async {
    await Clipboard.setData(ClipboardData(text: hash));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final c = context.colors;
      // A payment that drops out of the node's pool stays as it was last seen.
      final t = widget.session.transfers.firstWhere(
        widget.transfer.sameAs,
        orElse: () => widget.transfer,
      );
      final incoming = t.incoming;
      final to = paidTo(widget.session, t);
      final rows = <(String, Widget)>[
        if (to.isNotEmpty)
          (
            to.length == 1 ? 'Address' : 'Addresses',
            Text(
              [
                for (final (i, label) in to)
                  (i == 0 ? 'Primary address' : 'Subaddress #$i') +
                      (label.isEmpty ? '' : ' · $label'),
              ].join('\n'),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        // The sender paid the fee of a payment received.
        if (!incoming) ('Fee', _number(formatXmr(t.fee))),
        (
          'Confirmations',
          t.height == 0
              ? _words('None yet')
              : _number(
                  t.confirmations < unlockBlocks
                      ? '${t.confirmations} of $unlockBlocks'
                      : _grouped(t.confirmations),
                ),
        ),
        (
          'Block',
          t.height == 0
              ? _words('Not in a block yet')
              : _number(_grouped(t.height)),
        ),
        (
          'Account',
          _words(t.account == 0 ? 'Primary account' : 'Account #${t.account}'),
        ),
      ];
      return Screen(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
              child: Icon(
                incoming ? Icons.south_west : Icons.north_east,
                size: 26,
                color: incoming ? c.green : c.muted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              incoming ? 'Received' : 'Sent',
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${incoming ? '+' : '−'}${formatXmr(t.amount)}',
                    style: mono(size: 36, weight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' XMR',
                    style: mono(size: 16, color: c.accentText),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '${formatDate(t.time)}, ${formatTime(t.time)}',
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (final (i, (label, value)) in rows.indexed)
                  _Row(label, value, divider: i > 0),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transaction ID', style: context.body),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.hash,
                              style: mono(size: 13).copyWith(height: 1.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: _copied ? 'Copied' : 'Copy transaction ID',
                            onPressed: () => _copy(t.hash),
                            style: IconButton.styleFrom(
                              backgroundColor: c.btn2,
                              foregroundColor: c.text,
                              fixedSize: const Size(44, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: Icon(
                              _copied ? Icons.check : Icons.copy,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!incoming) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1, right: 10),
                  child: Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: c.muted,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Found through imported key images. A view-only wallet '
                    "can't see who you paid, only what left this wallet.",
                    style: context.body.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  static Widget _number(String text) => Text(text, style: mono(size: 14));

  static Widget _words(String text) =>
      Text(text, style: const TextStyle(fontSize: 14));
}

/// "3,233,240"
String _grouped(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// A "label ... value" row of the card.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {required this.divider});

  final String label;
  final Widget value;

  /// A line above the row, between it and the one before.
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 50),
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: divider
          ? Border(top: BorderSide(color: context.colors.border))
          : null,
    ),
    child: Row(
      children: [
        Text(label, style: context.body),
        const SizedBox(width: 12),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: value),
        ),
      ],
    ),
  );
}
