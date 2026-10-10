import 'dart:async';

import 'package:flutter/material.dart';

import 'secret_guard.dart';
import 'tor.dart';
import 'ui.dart';
import 'wallet.dart';

/// The public nodes offered on Choose a node, for each network, with who runs
/// them. Checked on 2026-10-09: each answered over TLS (an onion node over
/// Tor, which encrypts it end to end), was on its network and synced to the
/// chain tip. The Stagenet tests workflow checks them again
/// (test/public_nodes_test.dart). The onion nodes are from Feather Wallet's
/// node list, named after who runs them.
const publicNodes = {
  Network.mainnet: [
    (host: 'node.monerodevs.org:18089', operator: 'monerodevs.org'),
    (host: 'xmr-node.cakewallet.com:18081', operator: 'Cake Wallet'),
    (host: 'node.sethforprivacy.com:18089', operator: 'Seth For Privacy'),
    (host: 'rucknium.me:18081', operator: 'Rucknium'),
    (host: 'xmr.stormycloud.org:18089', operator: 'StormyCloud'),
    (host: 'nodes.hashvault.pro:18081', operator: 'HashVault'),
    (
      host: 'plowsof3t5hogddwabaeiyrno25efmzfxyro2vligremt7sxpsclfaid.onion:18089',
      operator: 'plowsof',
    ),
    (
      host: 'rucknium757bokwv3ss35ftgc3gzb7hgbvvglbg3hisp7tsj2fkd2nyd.onion:18081',
      operator: 'Rucknium',
    ),
  ],
  Network.stagenet: [
    (host: 'node.monerodevs.org:38089', operator: 'monerodevs.org'),
    (host: 'node2.monerodevs.org:38089', operator: 'monerodevs.org'),
    (host: 'xmr-lux.boldsuck.org:38081', operator: 'boldsuck.org'),
  ],
};

/// True if [node] is one of [network]'s [publicNodes] or one the person added
/// to that list.
bool isPublicNode(Network network, String node, List<String> added) =>
    added.contains(node) || publicNodes[network]!.any((n) => n.host == node);

final _hostAndPort = RegExp(r'^([A-Za-z0-9.-]+):(\d{1,5})$');

/// Null if [input] is a node this build can use, otherwise why not. A name
/// ending in a dot is refused: "x.onion." is an onion address that [isOnion]
/// would have to know to send over Tor, and nothing needs the dot.
String? nodeProblem(String input) {
  final match = _hostAndPort.firstMatch(input);
  final host = match?[1] ?? '';
  final port = match == null ? 0 : int.parse(match[2]!);
  if (port < 1 ||
      port > 65535 ||
      host.startsWith('.') ||
      host.endsWith('.') ||
      host.contains('..')) {
    return 'Enter the node as host:port, for example 192.168.1.20:18081.';
  }
  return null;
}

/// How Test and Test speed ask a node for its height. Tests replace it.
Future<({int height, int ms})> Function(String node, {String? tor}) askNode =
    ViewWallet.probeNode;

/// What a node's answer to [askNode] says about it, for a wallet on
/// [network]: null if it is of use, otherwise why not.
String? answerProblem(Network network, ({int height, int ms}) answer) {
  if (answer.height == 0) return "can't reach it";
  if (!onNetwork(network, answer.height)) {
    return "not a ${network.name} node, or far from synced";
  }
  return null;
}

/// Screen 2 of the design: "Choose a node". Used in setup and to change node.
/// Nothing is contacted until Test, Test speed or the button at the bottom is
/// pressed.
class NodeScreen extends StatefulWidget {
  const NodeScreen({
    super.key,
    required this.network,
    required this.action,
    required this.onChosen,
    this.current,
    this.tor = false,
    this.added = const [],
    this.testAll = true,
  });

  /// The wallet's network: which public nodes are offered, and which network
  /// a node has to be on.
  final Network network;

  /// The bottom button: "Start sync" in setup, "Save" afterwards.
  final String action;

  /// Connects the wallet to the node, through the Tor proxy [tor] unless it
  /// is null, and keeps [added], the public nodes the person added to the
  /// list. A [WalletException] is shown and the screen stays open.
  final Future<void> Function(String node, String? tor, List<String> added)
  onChosen;

  /// The node in use, when changing it.
  final String? current;

  /// Whether that node is reached over Tor.
  final bool tor;

  /// The public nodes added to the list before.
  final List<String> added;

  /// Whether Test speed asks every public node in the list, as it does unless
  /// Settings says otherwise, or only the one picked.
  final bool testAll;

  @override
  State<NodeScreen> createState() => _NodeScreenState();
}

class _NodeScreenState extends State<NodeScreen> {
  final _own = TextEditingController();
  final _adding = TextEditingController();

  /// The public node picked, or null for "My own node".
  String? _public;
  late final _added = [...widget.added];

  /// Whether the field for adding a node is open.
  bool _addOpen = false;
  bool _testing = false;
  bool _connecting = false;
  bool _speedTesting = false;
  String? _test;
  bool _testOk = false;
  String? _error;

  /// What Test speed found for each public node tested, null while it is
  /// asked.
  final _speeds = <String, ({int height, int ms})?>{};
  String? _speedError;

  /// The Connect over Tor switch.
  late bool _tor = widget.tor;

  bool get _busy => _testing || _connecting || _speedTesting;

  List<String> get _listed => [
    for (final n in publicNodes[widget.network]!) n.host,
    ..._added,
  ];

  /// An onion node can't be reached any other way.
  bool get _onion => isOnion(_node ?? '');
  bool get _useTor => _tor || _onion;

  /// Starts the app's Tor and waits for it to connect to the Tor network.
  /// Throws [WalletException] with what to tell the person if it doesn't.
  Future<String> _startTor() async {
    try {
      return await builtInTor.start().timeout(const Duration(minutes: 2));
    } on TorException catch (e) {
      throw WalletException(e.message);
    } on TimeoutException {
      // Tor carries on in the background, so trying again picks up from here.
      throw WalletException(
        "Tor hasn't connected to the Tor network yet. Check the internet "
        'connection and try again.',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    if (current != null && _listed.contains(current)) {
      _public = current;
    } else {
      _own.text = current ?? '';
    }
  }

  @override
  void dispose() {
    _own.dispose();
    _adding.dispose();
    // Started for a test, or for a node that is no longer reached over Tor.
    // After this frame: stopping it redraws Home, which can't happen while
    // this screen is being taken away.
    scheduleMicrotask(() {
      if (torProxy == null) builtInTor.stop();
    });
    super.dispose();
  }

  String get _ownNode => _own.text.trim();
  String? get _ownProblem => _ownNode.isEmpty ? null : nodeProblem(_ownNode);
  String? get _node =>
      _public ?? (nodeProblem(_ownNode) == null ? _ownNode : null);

  String get _addingNode => _adding.text.trim();

  /// Keeps a seed phrase or a private key pasted into a node field out of it.
  late final _refuseSecrets = RefuseSecrets(
    () => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'That looks like a seed phrase or a private key, so it was left '
          'out. $neverEnterSeed',
        ),
      ),
    ),
  );

  Future<void> _runTest() async {
    final node = _ownNode;
    setState(() {
      _testing = true;
      _test = 'Testing…';
      _testOk = false;
    });
    // Over Tor whenever the switch shows Tor on (also when an onion public
    // node is picked), and always for an onion node in the field, even while
    // a clearnet public node is picked.
    final useTor = _useTor || isOnion(node);
    String? tor, noTor;
    try {
      if (useTor) tor = await _startTor();
    } on WalletException catch (e) {
      noTor = e.message;
    }
    // With Tor wanted and not running, the node is not asked at all.
    final answer = noTor != null
        ? (height: 0, ms: 0)
        : await askNode(node, tor: tor);
    if (!mounted) return;
    final over = useTor ? ' over Tor' : '';
    final problem = answerProblem(widget.network, answer);
    setState(() {
      _testing = false;
      _testOk = problem == null;
      _test = _testOk
          ? 'Reachable$over · block ${answer.height} · ${answer.ms} ms'
          : noTor ??
                (answer.height == 0
                    ? "Can't reach this node$over."
                    : 'Reachable$over, but ${problem!}.');
    });
  }

  /// Asks the public nodes for their height and times the answers, one after
  /// the other, over Tor when Tor is on: every node in the list (an onion
  /// node only over Tor), or with [NodeScreen.testAll] off only the node
  /// picked. Only when pressed, and never with any wallet data (SECURITY.md
  /// rule 5). Answers stay on their rows until the next test.
  Future<void> _testSpeed() async {
    final useTor = _useTor;
    final nodes = widget.testAll
        ? [
            for (final node in _listed)
              if (useTor || !isOnion(node)) node,
          ]
        : [_public!];
    setState(() {
      _speedTesting = true;
      _speedError = null;
      if (widget.testAll) _speeds.clear();
      for (final node in nodes) {
        _speeds[node] = null;
      }
    });
    try {
      final tor = useTor ? await _startTor() : null;
      for (final node in nodes) {
        final answer = await askNode(node, tor: tor);
        if (!mounted) return;
        setState(() => _speeds[node] = answer);
      }
    } on WalletException catch (e) {
      _speedError = e.message;
      nodes.forEach(_speeds.remove);
    } finally {
      if (mounted) setState(() => _speedTesting = false);
    }
  }

  void _addNode() {
    final node = _addingNode;
    if (nodeProblem(node) != null) return;
    setState(() {
      if (!_listed.contains(node)) _added.add(node);
      _public = node;
      _addOpen = false;
      _adding.clear();
    });
  }

  void _removeNode(String node) => setState(() {
    _added.remove(node);
    _speeds.remove(node);
    if (_public == node) _public = null;
  });

  Future<void> _choose() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final node = _node!;
      final tor = _useTor ? await _startTor() : null;
      await widget.onChosen(node, tor, List.unmodifiable(_added));
    } on WalletException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// What Test speed found for [node], for the line under it.
  (String, Color)? _speed(String node) {
    final c = context.colors;
    if (!_speeds.containsKey(node)) return null;
    final answer = _speeds[node];
    if (answer == null) return ('testing…', c.muted);
    final problem = answerProblem(widget.network, answer);
    if (problem != null) return (problem, c.red);
    final tip = _speeds.values.fold(0, (tip, a) {
      final height = a?.height ?? 0;
      return onNetwork(widget.network, height) && height > tip ? height : tip;
    });
    // A node a block or two behind is normal for a few seconds after a new
    // block.
    final behind = tip - answer.height;
    if (behind > 2) return ('$behind blocks behind', c.amber);
    return ('${answer.ms} ms', c.green);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mainnet = widget.network == Network.mainnet;
    return PopScope(
      // Leaving mid-connection would close a wallet that is still in use.
      canPop: !_busy,
      child: Screen(
        title: 'Choose a node',
        canGoBack: !_busy,
        bottom: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: context.caption.copyWith(color: c.red),
                ),
              ),
            FilledButton(
              onPressed: _busy || _node == null ? null : _choose,
              child: Text(_connecting ? 'Connecting…' : widget.action),
            ),
          ],
        ),
        children: [
          Text(
            'The node sends this app the blockchain. It sees your IP address '
            'and which blocks you download, never your view key or balance.',
            style: context.body,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Choice(
                  selected: _public == null,
                  onTap: () => setState(() => _public = null),
                  title: const Text(
                    'My own node',
                    style: TextStyle(fontSize: 15),
                  ),
                  trailing: const _Tag('Most private'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('ownNode'),
                  controller: _own,
                  inputFormatters: [_refuseSecrets],
                  onTap: () => setState(() => _public = null),
                  onChanged: (_) => setState(() {
                    _public = null;
                    _test = null;
                  }),
                  // Keeps the node out of the keyboard's memory (Android).
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  style: mono(),
                  decoration: InputDecoration(
                    hintText: '192.168.1.20:${mainnet ? 18081 : 38081}',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The address and port of a node on your network or '
                    'Tailscale, or its .onion address.',
                    style: context.caption,
                  ),
                ),
                if (_ownProblem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _ownProblem!,
                      style: context.caption.copyWith(color: c.red),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SecondButton(
                      'Test',
                      onPressed: _busy || nodeProblem(_ownNode) != null
                          ? null
                          : _runTest,
                    ),
                    const SizedBox(width: 12),
                    if (_test != null)
                      Expanded(
                        child: Row(
                          children: [
                            StatusDot(
                              _testOk
                                  ? c.green
                                  : _testing
                                  ? c.amber
                                  : c.red,
                            ),
                            Expanded(
                              child: Text(_test!, style: context.caption),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SectionHeader(mainnet ? 'Public nodes' : 'Public nodes (stagenet)'),
          const Note(
            'A public node learns more than your own would. When you import '
            'key images, the app asks the node which of them are spent, so '
            'the node can tell those spends all come from one wallet and '
            'link them to your IP address. Your own node keeps that to '
            'yourself.',
          ),
          if (_tor)
            const Note(
              'Over Tor, an onion node is best. With any other node the last '
              "Tor relay sits in between, and because the app can't check "
              "most nodes' certificates, that relay could read the key images "
              'you import and change what the node tells the app.',
            ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (node, who, added) in _rows)
                  _publicRow(
                    node,
                    who,
                    trailing: added
                        ? IconButton(
                            tooltip: 'Remove from the list',
                            onPressed: _busy ? null : () => _removeNode(node),
                            icon: Icon(Icons.close, color: c.muted),
                          )
                        : null,
                  ),
                if (_addOpen) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('addNode'),
                    controller: _adding,
                    inputFormatters: [_refuseSecrets],
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _addNode(),
                    // Keeps the node out of the keyboard's memory (Android).
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    style: mono(),
                    decoration: InputDecoration(
                      hintText: 'node.example.org:${mainnet ? 18089 : 38089}',
                    ),
                  ),
                  if (_addingNode.isNotEmpty &&
                      nodeProblem(_addingNode) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        nodeProblem(_addingNode)!,
                        style: context.caption.copyWith(color: c.red),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _SecondButton(
                        'Add',
                        onPressed: nodeProblem(_addingNode) == null
                            ? _addNode
                            : null,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() {
                          _addOpen = false;
                          _adding.clear();
                        }),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ] else
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _addOpen = true),
                    icon: const Icon(Icons.add),
                    label: const Text('Add another node'),
                  ),
                Divider(height: 24, color: c.border),
                Row(
                  children: [
                    _SecondButton(
                      _speedTesting ? 'Testing…' : 'Test speed',
                      onPressed: _busy || (!widget.testAll && _public == null)
                          ? null
                          : _testSpeed,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _speedError ??
                            (widget.testAll
                                ? _useTor
                                      ? 'Asks each node for its height, over '
                                            'Tor.'
                                      : 'Asks each node for its height. Each '
                                            'one sees your IP address. Onion '
                                            'nodes are tested with Tor on.'
                                : _public == null
                                ? 'Pick a node, then test how fast it '
                                      'answers.'
                                : _useTor
                                ? 'Asks the node you picked for its height, '
                                      'over Tor.'
                                : 'Asks the node you picked for its height. '
                                      'It sees your IP address.'),
                        style: _speedError == null
                            ? context.caption
                            : context.caption.copyWith(color: c.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Tor (experimental)'),
          AppCard(
            child: ListenableBuilder(
              listenable: builtInTor,
              builder: (context, _) => SwitchRow(
                title: 'Connect over Tor',
                caption: !hasTor
                    ? 'This build has no Tor yet.'
                    : _useTor && _busy && !builtInTor.ready
                    ? 'Connecting to Tor… ${builtInTor.progress}%'
                    : '${_onion ? 'An onion node is always reached over Tor. '
                                    'The' : 'Hides your IP address from the node, '
                                    'and from Kraken if Show USD value is on. The'} '
                          'app runs its own Tor for this. It is new and '
                          "little tested, so don't rely on it yet. Starting "
                          'it can take a minute, and syncing is slower.',
                value: _useTor,
                onChanged: _busy || _onion || !hasTor
                    ? null
                    : (on) => setState(() {
                        _tor = on;
                        _test = null;
                        _speeds.clear();
                      }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The public nodes' rows: the app's list, then the ones added, each with
  /// who runs it and whether the person added it. With Tor on, onion nodes
  /// come first: only they keep Tor's last relay out of the traffic.
  List<(String, String, bool)> get _rows {
    final rows = [
      for (final n in publicNodes[widget.network]!)
        (n.host, 'Run by ${n.operator}', false),
      for (final node in _added) (node, 'Added by you', true),
    ];
    if (!_tor) return rows;
    return [
      ...rows.where((row) => isOnion(row.$1)),
      ...rows.where((row) => !isOnion(row.$1)),
    ];
  }

  Widget _publicRow(String node, String who, {Widget? trailing}) {
    final speed = _speed(node);
    return _Choice(
      selected: _public == node,
      onTap: () => setState(() => _public = node),
      title: Text(node, style: mono(size: 14)),
      subtitle: Text.rich(
        TextSpan(
          text: who,
          children: [
            if (_tor && !isOnion(node))
              TextSpan(
                text: ' · a Tor relay can read it',
                style: TextStyle(color: context.colors.amber),
              ),
            if (speed != null)
              TextSpan(
                text: ' · ${speed.$1}',
                style: TextStyle(color: speed.$2),
              ),
          ],
        ),
        style: context.caption,
      ),
      trailing: trailing,
    );
  }
}

/// The grey button next to a field or a list: Test, Add, Test speed.
class _SecondButton extends StatelessWidget {
  const _SecondButton(this.label, {required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: context.colors.btn2,
      foregroundColor: context.colors.text,
      minimumSize: const Size(88, 44),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// A radio row. Hand-drawn because the design's ring is not Material's.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onTap,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        // Room between rows whose onion address takes two lines.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.accent : context.colors.ring,
                    width: selected ? 6 : 2,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [title, ?subtitle],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.colors.btn2,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: context.colors.green),
    ),
  );
}
