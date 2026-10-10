import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'session.dart';
import 'ui.dart';
import 'wallet.dart';

/// "iPhone" in the iPhone app, "device" elsewhere.
String get thisDevice =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'device';

/// Settings → Advanced: rescan from an earlier height, and the subaddress
/// lookahead. Import problem's "Rescan from an earlier height" opens it too.
class AdvancedScreen extends StatefulWidget {
  const AdvancedScreen(this.session, {super.key});

  final WalletSession session;

  @override
  State<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends State<AdvancedScreen> {
  late final _height = TextEditingController(
    text: '${widget.session.wallet.restoreHeight}',
  );
  late final _accounts = TextEditingController(
    text: '${widget.session.wallet.lookahead.accounts}',
  );
  late final _addresses = TextEditingController(
    text: '${widget.session.wallet.lookahead.addresses}',
  );
  bool _rescanning = false;
  bool _saving = false;

  /// Why the last rescan didn't start.
  String? _rescanFailed;

  WalletSession get _s => widget.session;

  @override
  void dispose() {
    _height.dispose();
    _accounts.dispose();
    _addresses.dispose();
    super.dispose();
  }

  int? get _from => int.tryParse(_height.text);

  /// Null when [_from] can be rescanned from.
  String? get _heightProblem {
    final from = _from;
    final now = _s.wallet.restoreHeight;
    if (from == null) return 'Type a block height.';
    if (from > now) {
      return 'Use $now or an earlier height. A later one can miss payments.';
    }
    return null;
  }

  Future<void> _rescan() async {
    final from = _from!;
    final c = context.colors;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Rescan from block $from?'),
        content: Text(
          'The balance and history start again from block $from. The app '
          'forgets the key images imported so far, so import them again '
          'when the scan is done. Subaddresses and their labels stay.',
          style: context.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rescan'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final navigator = Navigator.of(context);
    setState(() {
      _rescanning = true;
      _rescanFailed = null;
    });
    try {
      await _s.rescan(from);
      // Home shows the scan, as on the first sync.
      navigator.popUntil((route) => route.isFirst);
    } on WalletException {
      if (mounted) {
        setState(
          () => _rescanFailed =
              "Can't reach your node, so nothing was changed. Try again "
              'when it answers.',
        );
      }
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  Lookahead? get _lookahead {
    final accounts = int.tryParse(_accounts.text);
    final addresses = int.tryParse(_addresses.text);
    if (accounts == null || addresses == null) return null;
    final lookahead = (accounts: accounts, addresses: addresses);
    return ViewWallet.validLookahead(lookahead) ? lookahead : null;
  }

  Future<void> _saveLookahead() async {
    setState(() => _saving = true);
    try {
      await _s.setLookahead(_lookahead!);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _s,
    builder: (context, _) {
      final c = context.colors;
      final busy = _rescanning || _saving;
      final heightProblem = _heightProblem;
      final canRescan = !busy && _s.reachable && heightProblem == null;
      final lookahead = _lookahead;
      final current = _s.wallet.lookahead;
      return PopScope(
        canPop: !busy,
        child: Screen(
          title: 'Advanced',
          canGoBack: !busy,
          children: [
            const SectionHeader('Rescan'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Rescan from an earlier height',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scans the blockchain again from the height below, for '
                    'payments this $thisDevice missed because it started '
                    "scanning after they arrived. Use the Monero GUI's "
                    'restore height (Settings → Info) or an earlier one. '
                    'This $thisDevice started from block '
                    '${_s.wallet.restoreHeight}.',
                    style: context.body,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('rescanFrom'),
                    controller: _height,
                    enabled: !busy,
                    onChanged: (_) => setState(() => _rescanFailed = null),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: mono(),
                    decoration: const InputDecoration(
                      labelText: 'Rescan from block',
                    ),
                  ),
                  if (heightProblem != null || _rescanFailed != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _rescanFailed ?? heightProblem!,
                        style: context.caption.copyWith(color: c.red),
                      ),
                    ),
                  if (!_s.reachable)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        "Can't reach your node. Rescan when it answers.",
                        style: context.caption,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: canRescan ? _rescan : null,
                    child: Text(
                      _rescanning ? 'Starting the rescan…' : 'Rescan',
                    ),
                  ),
                ],
              ),
            ),
            const Note(
              'A rescan forgets the key images imported so far: the app asks '
              'for them again when the scan is done. Scanning from an '
              'earlier height takes longer.',
            ),
            const SectionHeader('Subaddress lookahead'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How far past the last account and address in use the app '
                    'looks for payments. The Monero GUI looks '
                    '${defaultLookahead.accounts} accounts × '
                    '${defaultLookahead.addresses} addresses ahead. If it gave '
                    'out more than ${defaultLookahead.addresses} addresses in '
                    'a row before one was paid, raise this, then rescan.',
                    style: context.body,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _NumberField(
                          key: const Key('lookaheadAccounts'),
                          controller: _accounts,
                          label: 'Accounts',
                          enabled: !busy,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        child: Text('×', style: context.body),
                      ),
                      Expanded(
                        child: _NumberField(
                          key: const Key('lookaheadAddresses'),
                          controller: _addresses,
                          label: 'Addresses',
                          enabled: !busy,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  if (lookahead == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Use at least 1 of each, and no more than '
                        '$maxLookahead in all.',
                        style: context.caption.copyWith(color: c.red),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        !busy && lookahead != null && lookahead != current
                        ? _saveLookahead
                        : null,
                    style: context.secondaryButton.copyWith(
                      backgroundColor: WidgetStatePropertyAll(c.btn2),
                    ),
                    child: Text(_saving ? 'Saving…' : 'Save lookahead'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    onChanged: (_) => onChanged(),
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: mono(),
    decoration: InputDecoration(labelText: label),
  );
}
