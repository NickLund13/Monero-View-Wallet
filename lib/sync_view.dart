import 'package:flutter/material.dart';

import 'session.dart';
import 'tor.dart';
import 'ui.dart';
import 'wallet.dart';

/// Screen 3 of the design: "Scanning the blockchain", shown until the first
/// scan reaches the node's height.
class SyncView extends StatefulWidget {
  const SyncView({
    super.key,
    required this.session,
    required this.onChangeNode,
    required this.onRemoveWallet,
  });

  final WalletSession session;
  final VoidCallback onChangeNode;

  /// Settings can't be reached until the first scan is done, so the way out of
  /// a wrong restore height is here too.
  final VoidCallback onRemoveWallet;

  @override
  State<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<SyncView> {
  final _gettingReady = _Pace();
  final _scanning = _Pace();

  /// The height wallet2's list of blocks stood at when this screen first saw
  /// it grow, for the progress while it is getting ready.
  int? _listedFrom;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final c = context.colors;
    final from = s.wallet.restoreHeight;
    // Before it scans, wallet2 gets the ids of the blocks below the restore
    // height from the node, from where its built-in list ends. Its height
    // climbs towards [from] meanwhile, though no block is scanned yet. That
    // takes a minute or two, longer over Tor.
    final gettingReady = s.height < from;
    if (gettingReady && s.height > 1) _listedFrom ??= s.height;
    final listFrom = _listedFrom ?? from;
    final listTotal = from - listFrom;
    final listed = (s.height - listFrom).clamp(0, listTotal);
    final total = s.nodeHeight > from ? s.nodeHeight - from : 0;
    final scanned = (s.height - from).clamp(0, total);
    final fraction = gettingReady
        ? (listTotal == 0 ? 0.0 : listed / listTotal)
        : (total == 0 ? 0.0 : scanned / total);
    final timeLeft = gettingReady
        ? _gettingReady.left(listed, listTotal)
        : _scanning.left(scanned, total);

    return Screen(
      title: 'Scanning the blockchain',
      bottom: Column(
        children: [
          Text(
            'Keep the app open for the fastest scan.',
            textAlign: TextAlign.center,
            style: context.caption,
          ),
          TextButton(
            onPressed: widget.onRemoveWallet,
            style: TextButton.styleFrom(foregroundColor: c.red),
            child: const Text('Remove wallet'),
          ),
        ],
      ),
      children: [
        Text(
          '${(fraction * 100).floor()}%',
          style: mono(size: 40, weight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: fraction, minHeight: 6),
        ),
        const SizedBox(height: 12),
        Text(
          gettingReady
              ? 'Getting ready: listing the blocks before height $from'
              : '$scanned of $total blocks · from height $from',
          style: context.caption,
        ),
        if (timeLeft != null) Text(timeLeft, style: context.caption),
        const SizedBox(height: 20),
        FactsCard([
          (
            'Received so far',
            Text('${formatXmr(s.balance)} XMR', style: mono()),
          ),
          ('Outputs found', Text('${s.outputs.total}', style: mono())),
          (
            'Node',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusDot(s.reachable ? c.green : c.red),
                Flexible(
                  child: Text(
                    s.node,
                    style: mono(size: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Only when the node is reached over the app's Tor.
          if (s.tor != null)
            (
              'Tor',
              ListenableBuilder(
                listenable: builtInTor,
                builder: (context, _) => Text(
                  builtInTor.ready
                      ? 'Connected'
                      : builtInTor.error != null
                      ? 'Not running'
                      : 'Connecting… ${builtInTor.progress}%',
                  style: mono(size: 13),
                ),
              ),
            ),
        ]),
        if (!s.reachable)
          Row(
            children: [
              Expanded(
                child: Text(
                  "Can't reach your node. The scan continues when it answers.",
                  style: context.caption.copyWith(color: c.red),
                ),
              ),
              TextButton(
                onPressed: widget.onChangeNode,
                child: const Text('Change node'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          "Spends don't show yet: the app can only see them once you import "
          'key images. It asks for them when the scan finishes.',
          style: context.body,
        ),
      ],
    );
  }
}

/// Estimates the time left from how fast a count has been rising since this
/// screen first saw it move.
class _Pace {
  final _watch = Stopwatch();
  int _first = 0;

  /// "About 4 min left", or null until there are five seconds to judge by.
  String? left(int done, int total) {
    if (done == 0) return null;
    if (!_watch.isRunning) {
      _watch.start();
      _first = done;
    }
    final seconds = _watch.elapsed.inSeconds;
    final gained = done - _first;
    if (seconds < 5 || gained <= 0) return null;
    final left = (total - done) * seconds ~/ gained;
    return left < 60
        ? 'Less than a minute left'
        : 'About ${(left / 60).ceil()} min left';
  }
}
