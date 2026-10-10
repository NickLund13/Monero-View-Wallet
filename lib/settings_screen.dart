import 'dart:io';

import 'package:flutter/material.dart';

import 'advanced_screen.dart';
import 'licenses.dart';
import 'lock.dart';
import 'node_screen.dart';
import 'price.dart';
import 'privacy_policy.dart';
import 'session.dart';
import 'ui.dart';

/// Screen 10 of the design: "Settings", with the parts built so far: the node,
/// the restore height and Advanced, the appearance, the USD value, the lock
/// and removing the wallet.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen(
    this.session, {
    super.key,
    required this.onChangeNode,
    required this.onRemoveWallet,
  });

  final WalletSession session;

  /// Opens Choose a node.
  final VoidCallback onChangeNode;

  /// Asks first, then deletes the saved wallet and goes back to setup.
  final VoidCallback onRemoveWallet;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final c = context.colors;
      final s = session;
      return Screen(
        title: 'Settings',
        children: [
          const SectionHeader('Node'),
          _NodeRow(s, onTap: onChangeNode),
          AppCard(child: SpeedTestSwitch(s)),
          const SectionHeader('Wallet'),
          _WalletCard(s),
          const SectionHeader('Display'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Appearance', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                const AppearancePicker(),
                const SizedBox(height: 12),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 4),
                const UsdSwitch(),
              ],
            ),
          ),
          const SectionHeader('Security'),
          AppCard(child: LockSwitch(session)),
          const SectionHeader('About'),
          const PrivacyPolicyRow(),
          const LicensesRow(),
          Center(
            child: TextButton(
              onPressed: onRemoveWallet,
              style: TextButton.styleFrom(foregroundColor: c.red),
              child: const Text('Remove wallet from this device'),
            ),
          ),
        ],
      );
    },
  );
}

/// The node in use, whether it answers, and how long it took to answer
/// when the screen opened: the one node the app talks to anyway, asked once
/// more, the same way (over Tor when Tor is on).
class _NodeRow extends StatefulWidget {
  const _NodeRow(this.session, {required this.onTap});

  final WalletSession session;
  final VoidCallback onTap;

  @override
  State<_NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends State<_NodeRow> {
  /// The node [_ms] is for.
  String? _timed;
  int? _ms;

  @override
  void initState() {
    super.initState();
    _time();
  }

  /// Settings is drawn again whenever the session changes: after a change of
  /// node, or once the node answers again.
  @override
  void didUpdateWidget(_NodeRow old) {
    super.didUpdateWidget(old);
    _time();
  }

  void _time() {
    final s = widget.session;
    final node = s.node;
    if (_timed == node || !s.reachable) return;
    _timed = node;
    _ms = null;
    askNode(node, tor: s.tor).then((answer) {
      if (!mounted || _timed != node) return;
      setState(() => _ms = answer.height > 0 ? answer.ms : null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.session;
    final kind = isPublicNode(s.wallet.network, s.node, s.wallet.addedNodes)
        ? 'Public node'
        : 'Your own node';
    final tor = s.tor == null ? '' : ' over Tor';
    final ms = _ms == null ? '' : ' · $_ms ms';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.node, style: mono(size: 14)),
                      Text(
                        s.reachable
                            ? '$kind$tor · connected$ms'
                            : "$kind$tor · can't reach it",
                        style: TextStyle(
                          fontSize: 12,
                          color: s.reachable ? c.green : c.red,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.chev),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The restore height, and Advanced: rescan and the subaddress lookahead.
class _WalletCard extends StatelessWidget {
  const _WalletCard(this.session);

  final WalletSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lookahead = session.wallet.lookahead;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Restore height',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  Text(
                    '${session.wallet.restoreHeight}',
                    style: mono(size: 14, color: c.sec),
                  ),
                ],
              ),
            ),
            Divider(height: 1, indent: 16, endIndent: 16, color: c.border),
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AdvancedScreen(session),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Advanced',
                            style: TextStyle(fontSize: 15),
                          ),
                          Text(
                            'Rescan, subaddress lookahead '
                            '(${lookahead.accounts} × ${lookahead.addresses})',
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.chev),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// System / Light / Dark as a segmented control. Each option is the full 44
/// tall; the highlight inside it is 38.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});

  static const _modes = [
    (ThemeMode.system, 'System'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder(
      valueListenable: appearance,
      builder: (context, current, _) => Material(
        color: c.btn2,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Row(
            children: [
              for (final (mode, label) in _modes)
                Expanded(
                  child: Semantics(
                    container: true,
                    button: true,
                    inMutuallyExclusiveGroup: true,
                    selected: mode == current,
                    child: InkWell(
                      onTap: () => appearance.value = mode,
                      borderRadius: BorderRadius.circular(11),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        child: Container(
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: mode == current ? c.seg : null,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: mode == current ? c.text : c.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Show USD value: turns the price lookup on or off. Off by default; while off
/// the app makes no price request at all (SECURITY.md rule 5).
class UsdSwitch extends StatelessWidget {
  const UsdSwitch({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: usdPrice,
    builder: (context, _) => SwitchRow(
      title: 'Show USD value',
      caption:
          'Off by default. Gets the XMR price from Kraken, over Tor when '
          'the node is reached over Tor. Without Tor, Kraken sees your IP '
          'address. It never sees anything about your wallet.',
      value: usdPrice.on,
      onChanged: (on) => usdPrice.on = on,
    ),
  );
}

/// Whether Test speed on Choose a node asks every public node in the list
/// (on, the default) or only the one picked. The owner allowed asking every
/// node on 2026-10-10 (SECURITY.md rule 5), with this switch to stop it.
class SpeedTestSwitch extends StatelessWidget {
  const SpeedTestSwitch(this.session, {super.key});

  final WalletSession session;

  @override
  Widget build(BuildContext context) => SwitchRow(
    title: 'Test speed asks every node',
    caption:
        'Test speed on Choose a node asks every public node in the list how '
        'fast it answers. Each one sees your IP address unless Tor is on. '
        'Off, it asks only the node you picked.',
    value: session.testAllNodes,
    onChanged: session.setTestAllNodes,
  );
}

/// Face ID to open: the lock (lock.dart). Turning it off asks Face ID or the
/// passcode first, so someone handed the unlocked app can't switch it off for
/// later.
class LockSwitch extends StatelessWidget {
  const LockSwitch(this.session, {super.key});

  final WalletSession session;

  Future<void> _turn(bool on) async {
    if (!on && !await appLock.confirm()) return;
    appLock.on = on;
    await session.setLockOn(on);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appLock,
    builder: (context, _) {
      final kind = appLock.kind;
      final String caption;
      if (appLock.canLock) {
        caption =
            'Locks when the app opens and after 1 minute in the '
            'background.';
      } else if (Platform.isIOS) {
        caption = 'Needs a passcode on this iPhone. Set one in its Settings.';
      } else {
        caption = "iPhone only. This test build doesn't lock.";
      }
      return SwitchRow(
        title: '${kind.label} to open',
        caption: caption,
        value: appLock.canLock && appLock.on,
        onChanged: appLock.canLock ? _turn : null,
      );
    },
  );
}
