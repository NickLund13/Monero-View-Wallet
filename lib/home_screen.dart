import 'package:flutter/material.dart';

import 'key_images_screen.dart';
import 'lock.dart';
import 'node_screen.dart';
import 'pick_file.dart';
import 'price.dart';
import 'receive_screen.dart';
import 'secret_guard.dart';
import 'session.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'sync_view.dart';
import 'tor.dart';
import 'transaction_screen.dart';
import 'ui.dart';
import 'wallet.dart';

/// Screen 7 of the design: balance and history. Shows the first-sync screen
/// until the first scan is done, then asks once for key images. A wallet that
/// finished its first scan on an earlier launch opens here directly.
class HomeScreen extends StatefulWidget {
  const HomeScreen(this.session, {super.key});

  /// Closed when this screen goes away.
  final WalletSession session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late bool _firstSync;

  /// The balance is showing USD, which needs the price lookup on.
  bool _usd = false;

  WalletSession get _s => widget.session;

  /// Saves the wallet when the app loses focus, which on an iPhone comes
  /// before going to the background or being swiped away.
  late final AppLifecycleListener _lifecycle;

  /// True while Import key images is open: a file opened with the app goes
  /// to that screen instead of opening another.
  bool _keyImagesOpen = false;

  @override
  void initState() {
    super.initState();
    _firstSync = !_s.scanned;
    _s.addListener(_onUpdate);
    _lifecycle = AppLifecycleListener(onInactive: _s.save);
    receivedKeyImagesFile.addListener(_onReceived);
    // The file that started the app can come before this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onReceived());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    receivedKeyImagesFile.removeListener(_onReceived);
    _s.removeListener(_onUpdate);
    _s.dispose();
    super.dispose();
  }

  void _onUpdate() {
    // A rescan (Settings → Advanced) starts the first scan over.
    if (!_s.scanned) _firstSync = true;
    if (_firstSync && _s.scanned) {
      _firstSync = false;
      // Not on top of the node screen, if that is open: Home's own row asks.
      if (ModalRoute.of(context)?.isCurrent ?? true) _openKeyImages();
    }
    setState(() {});
  }

  /// A key images file opened with the app, from Files, the share sheet or
  /// AirDrop, goes to Import key images. That screen asks before importing it,
  /// and waits for the first scan to finish.
  void _onReceived() {
    if (mounted && !_keyImagesOpen && receivedKeyImagesFile.value != null) {
      _openKeyImages();
    }
  }

  Future<void> _openKeyImages() async {
    _keyImagesOpen = true;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => KeyImagesScreen(_s)),
    );
    _keyImagesOpen = false;
  }

  /// The header's name is the person's own, kept with the wallet on this
  /// device.
  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(_s.name),
    );
    if (name != null && mounted) await _s.rename(name);
  }

  void _openReceive() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ReceiveScreen(_s)),
  );

  void _openSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        _s,
        onChangeNode: _changeNode,
        onRemoveWallet: _removeWallet,
      ),
    ),
  );

  Future<void> _removeWallet() async {
    final c = context.colors;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Remove this wallet?'),
        content: Text(
          'The app deletes the wallet it saved on this device, with its key '
          "images and history. Your funds aren't touched. To watch the wallet "
          'again, set it up from the Monero GUI.',
          style: context.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: c.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    final navigator = Navigator.of(context);
    // Closing waits for the node's last answer. Nothing can be tapped
    // meanwhile.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    await _s.forget();
    // Settings can't be reached without a wallet, so nothing could turn the
    // price lookup off again. Nor is there anything left to lock.
    usdPrice.on = false;
    appLock.on = false;
    torProxy = null;
    builtInTor.stop();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SetupScreen()),
      (_) => false,
    );
  }

  void _changeNode() {
    final navigator = Navigator.of(context);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => NodeScreen(
          network: _s.wallet.network,
          action: 'Save',
          current: _s.node,
          tor: _s.tor != null,
          added: _s.wallet.addedNodes,
          testAll: _s.testAllNodes,
          onChosen: (node, tor, added) async {
            await _s.changeNode(node, tor: tor, added: added);
            navigator.pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_firstSync) {
      return SyncView(
        session: _s,
        onChangeNode: _changeNode,
        onRemoveWallet: _removeWallet,
      );
    }
    final c = context.colors;
    return Screen(
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: 'Rename this wallet',
                  child: InkWell(
                    onTap: _rename,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_outlined,
                                size: 14,
                                color: c.muted,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  "View only · can't send",
                                  style: context.caption,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (final (tooltip, icon, open) in [
              ('Receive', Icons.download, _openReceive),
              ('Settings', Icons.settings_outlined, _openSettings),
            ])
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  tooltip: tooltip,
                  onPressed: open,
                  style: IconButton.styleFrom(
                    backgroundColor: c.card,
                    foregroundColor: c.text,
                    fixedSize: const Size(44, 44),
                  ),
                  icon: Icon(icon, size: 20),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        ListenableBuilder(listenable: usdPrice, builder: (_, _) => _balance()),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: builtInTor,
          builder: (_, _) => _syncLine(),
        ),
        const SizedBox(height: 16),
        _keyImagesRow(),
        const SectionHeader('Activity'),
        if (_s.transfers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No transactions yet.', style: context.body),
          ),
        for (final t in _s.transfers)
          _ActivityRow(
            t,
            to: [
              for (final (i, label) in paidTo(_s, t))
                label.isNotEmpty
                    ? label
                    : i == 0
                    ? 'primary address'
                    : 'subaddress #$i',
            ].join(', '),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => TransactionScreen(_s, t)),
            ),
          ),
      ],
    );
  }

  /// Asked when the balance is tapped while Show USD value is off: the price
  /// lookup is the one network call besides the node (SECURITY.md rule 5), so
  /// it starts only once the person says yes, here or in Settings.
  Future<bool> _askToShowUsd() async {
    final c = context.colors;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Show the USD value?'),
        content: Text(
          'The app will ask Kraken for the XMR price now and every 10 '
          '${_s.tor != null ? 'minutes, over Tor like your node. Kraken ' : "minutes. Kraken sees your IP address but "}'
          'never sees anything about your wallet. You can turn this off in '
          'Settings → Show USD value.',
          style: context.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Show USD'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  /// The balance in XMR, or in USD once the person tapped it. With the price
  /// lookup off, a tap asks before turning it on.
  Widget _balance() {
    final c = context.colors;
    // Turned off: start from XMR again when it is next turned on.
    if (!usdPrice.on) _usd = false;
    final usd = _usd;
    final price = usdPrice.perXmr;
    final amount = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: !usd
                  ? formatXmr(_s.balance, short: true)
                  : price == null
                  ? '—'
                  : formatUsd(_s.balance / atomicUnitsPerXmr * price),
              style: mono(size: 40, weight: FontWeight.w500),
            ),
            TextSpan(
              text: usd ? ' USD' : ' XMR',
              style: mono(size: 18, color: c.accentText),
            ),
          ],
        ),
      ),
    );
    final Widget below;
    if (!usd) {
      below = Text(_unlockedLine, style: mono(size: 13, color: c.muted));
    } else if (price != null) {
      final asOf = usdPrice.failed ? ' as of ${formatTime(usdPrice.at!)}' : '';
      below = Text(
        '\$${formatUsd(_s.unlocked / atomicUnitsPerXmr * price)} unlocked · '
        'at \$${formatUsd(price)} per XMR$asOf',
        style: mono(size: 13, color: c.muted),
      );
    } else {
      below = Text(
        usdPrice.failed
            ? "Can't reach Kraken for the XMR price."
            : 'Getting the XMR price…',
        style: context.caption,
      );
    }
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () async {
          if (!usdPrice.on) {
            if (!await _askToShowUsd() || !mounted) return;
            // Asks for the price at once. main() remembers the choice, as it
            // does the Settings switch.
            usdPrice.on = true;
            setState(() => _usd = true);
            return;
          }
          setState(() => _usd = !_usd);
          // Try again at once rather than at the next refresh.
          if (_usd && (usdPrice.perXmr == null || usdPrice.failed)) {
            usdPrice.refresh();
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'BALANCE',
                  style: context.caption.copyWith(letterSpacing: 0.52),
                ),
                const SizedBox(width: 6),
                Icon(Icons.swap_horiz, size: 16, color: c.muted),
                const SizedBox(width: 4),
                Text(
                  usd ? 'tap for XMR' : 'tap for USD',
                  style: context.caption,
                ),
              ],
            ),
            const SizedBox(height: 6),
            amount,
            below,
          ],
        ),
      ),
    );
  }

  String get _unlockedLine {
    final unlocked = '${formatXmr(_s.unlocked, short: true)} unlocked';
    if (_s.locking <= 0) return unlocked;
    final blocks = _s.lockingBlocks;
    return '$unlocked · ${formatXmr(_s.locking, short: true)} locking'
        '${blocks > 0 ? ' (${plural(blocks, 'block')})' : ''}';
  }

  Widget _syncLine() {
    final c = context.colors;
    // The node can't be reached until the app's Tor is connected.
    if (_s.tor != null && !builtInTor.ready) {
      final error = builtInTor.error;
      return Row(
        children: [
          StatusDot(error == null ? c.amber : c.red),
          Expanded(
            child: Text(
              error == null
                  ? 'Connecting to Tor… ${builtInTor.progress}%'
                  : "$error Your node can't be reached without Tor.",
              style: error == null
                  ? context.caption
                  : context.caption.copyWith(color: c.red),
            ),
          ),
          TextButton(onPressed: _changeNode, child: const Text('Change node')),
        ],
      );
    }
    if (!_s.reachable) {
      return Row(
        children: [
          StatusDot(c.red),
          Expanded(
            child: Text(
              "Can't reach your node. Balance as of ${_asOf(_s.lastContact)}.",
              style: context.caption.copyWith(color: c.red),
            ),
          ),
          TextButton(onPressed: _changeNode, child: const Text('Change node')),
        ],
      );
    }
    if (_s.catchingUp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(c.amber),
              Expanded(
                child: Text(
                  // A wallet opened from its file hasn't heard from the node
                  // yet.
                  _s.nodeHeight == 0
                      ? 'Connecting to your node…'
                      : 'Catching up · ${plural(_s.blocksToGo, 'block')} to go',
                  style: context.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
      );
    }
    final minutes = DateTime.now().difference(_s.lastBlock).inMinutes;
    return Row(
      children: [
        StatusDot(c.green),
        Expanded(
          child: Text(
            'Synced to block ${_s.height} · '
            '${minutes < 1 ? 'just now' : '$minutes min ago'}',
            style: context.caption,
          ),
        ),
      ],
    );
  }

  /// "09:05" today, "8 Oct 2026, 09:05" for a balance saved on another day.
  String _asOf(DateTime time) => DateUtils.isSameDay(time, DateTime.now())
      ? formatTime(time)
      : '${formatDate(time)}, ${formatTime(time)}';

  Widget _keyImagesRow() {
    final c = context.colors;
    final last = _s.lastImport;
    if (_s.showKeyImagesNotice) {
      final outputs = _s.outputs.withoutKeyImage;
      return Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: c.noteBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: c.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                last == null
                    ? '${plural(outputs, 'output')} without key images. '
                          "Spends of them won't show."
                    : '${plural(outputs, 'new output')} since your key images',
                style: TextStyle(fontSize: 13, color: c.noteText),
              ),
            ),
            TextButton(
              onPressed: _openKeyImages,
              style: TextButton.styleFrom(foregroundColor: c.accentText),
              child: const Text('Import'),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: _s.dismissKeyImagesNotice,
              icon: const Icon(Icons.close, size: 18),
              color: c.noteText,
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: _openKeyImages,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Text(
                last == null
                    ? 'Key images not imported yet'
                    : 'Key images imported ${formatDate(last.at)}',
                style: context.caption,
              ),
            ),
            Icon(Icons.chevron_right, color: c.chev),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.transfer, {required this.to, required this.onTap});

  final Transfer transfer;

  /// Where a payment went ("subaddress #3", or its label), or empty. Shown
  /// once the payment has unlocked; until then the row says how far it is.
  final String to;

  /// Opens the transaction.
  final VoidCallback onTap;

  String get _when {
    final t = transfer;
    if (t.height == 0) return 'Pending';
    if (t.confirmations < unlockBlocks) {
      return '${t.confirmations} of $unlockBlocks confirmations';
    }
    return formatDate(t.time);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final incoming = transfer.incoming;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
              child: Icon(
                incoming ? Icons.south_west : Icons.north_east,
                size: 18,
                color: incoming ? c.green : c.muted,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    incoming ? 'Received' : 'Sent',
                    style: const TextStyle(fontSize: 15),
                  ),
                  Text(
                    !incoming
                        ? '$_when · found via key images'
                        : to.isEmpty ||
                              transfer.height == 0 ||
                              transfer.confirmations < unlockBlocks
                        ? _when
                        : '$_when · $to',
                    style: context.caption,
                  ),
                ],
              ),
            ),
            Text(
              '${incoming ? '+' : '−'}${formatXmr(transfer.amount)}',
              style: mono(color: incoming ? c.text : c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the wallet's name. Empty goes back to the default.
class _NameDialog extends StatefulWidget {
  const _NameDialog(this.name);

  final String name;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.name);

  /// A seed phrase or a private key was just pasted in, and refused.
  bool _refused = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: context.colors.card,
    title: const Text('Name this wallet'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('walletName'),
          controller: _name,
          autofocus: true,
          maxLength: 30,
          // Before maxLength, so a pasted seed isn't cut to fit and kept.
          inputFormatters: [
            RefuseSecrets(() => setState(() => _refused = true)),
          ],
          onChanged: (_) {
            if (_refused) setState(() => _refused = false);
          },
          textCapitalization: TextCapitalization.sentences,
          // Keeps the keyboard from learning the name: no autocorrection or
          // suggestions on iPhone, no personalized learning on Android.
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            errorText: _refused
                ? 'That looks like a seed phrase or a private key, so it was '
                      'left out. $neverEnterSeed'
                : null,
            errorMaxLines: 4,
          ),
          onSubmitted: (name) => Navigator.pop(context, name),
        ),
        Text(
          'Shown at the top of Home. Kept only on this device, inside the '
          'encrypted wallet file.',
          style: context.caption,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _name.text),
        child: const Text('Save'),
      ),
    ],
  );
}
