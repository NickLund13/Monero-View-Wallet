/// What the screens show about the wallet being watched, refreshed every two
/// seconds. What has to outlive the app is saved inside the wallet's encrypted
/// file, see [ViewWallet.save].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'tor.dart';
import 'wallet.dart';

/// Blocks before a received output can be spent.
const unlockBlocks = 10;

/// While blocks are being scanned, the wallet is saved this often, and Home
/// saves it whenever the app loses focus: on a phone the system can end an app
/// in the background without warning. Closing the Windows app loses up to
/// this much scanning, which is redone on the next launch.
const saveEvery = Duration(minutes: 2);

// The names of the notes kept in the wallet's file, see [ViewWallet.save].
const _scannedNote = 'mvw.scanned';
const _contactNote = 'mvw.lastContact';
const _importNote = 'mvw.lastImport';
const _lockNote = 'mvw.lock';
const _nameNote = 'mvw.name';
const _speedNote = 'mvw.speedTest';

class KeyImageImport {
  KeyImageImport({
    required this.at,
    required this.fileName,
    required this.newlySpent,
    required this.outputs,
  });
  final DateTime at;
  final String fileName;
  final int newlySpent;

  /// The wallet's outputs right after the import.
  final Outputs outputs;

  /// As kept in the wallet's file between launches.
  String toNote() => jsonEncode({
    'at': at.millisecondsSinceEpoch,
    'fileName': fileName,
    'newlySpent': newlySpent,
    'total': outputs.total,
    'spent': outputs.spent,
    'withoutKeyImage': outputs.withoutKeyImage,
  });

  /// Null for no note, and for one that can't be read: the app then shows no
  /// import instead of failing to start.
  static KeyImageImport? fromNote(String? note) {
    if (note == null) return null;
    try {
      if (jsonDecode(note) case {
        'at': final int at,
        'fileName': final String fileName,
        'newlySpent': final int newlySpent,
        'total': final int total,
        'spent': final int spent,
        'withoutKeyImage': final int withoutKeyImage,
      }) {
        return KeyImageImport(
          at: DateTime.fromMillisecondsSinceEpoch(at),
          fileName: fileName,
          newlySpent: newlySpent,
          outputs: (
            total: total,
            spent: spent,
            withoutKeyImage: withoutKeyImage,
          ),
        );
      }
    } on FormatException {
      // Not JSON.
    }
    return null;
  }
}

class WalletSession extends ChangeNotifier {
  /// [wallet] must already be connected to a node. A wallet opened from its
  /// file shows what it knew when it was last saved until the node answers.
  WalletSession(this.wallet)
    : scanned = wallet.remembered(_scannedNote) != null,
      lastImport = KeyImageImport.fromNote(wallet.remembered(_importNote)),
      lockOn = wallet.remembered(_lockNote) != 'off',
      testAllNodes = wallet.remembered(_speedNote) != 'picked',
      _name = wallet.remembered(_nameNote) {
    final contact = int.tryParse(wallet.remembered(_contactNote) ?? '');
    if (contact != null) {
      lastContact = lastBlock = DateTime.fromMillisecondsSinceEpoch(contact);
    }
    _readWallet();
    _savedHeight = height;
  }

  final ViewWallet wallet;
  Timer? _poll;
  bool _refreshing = false;
  int _polls = 0;
  bool _closed = false;
  int _savedHeight = 0;
  DateTime _savedAt = DateTime.now();

  /// Height scanned so far, and the node's height when it last answered.
  int height = 0;
  int nodeHeight = 0;
  bool reachable = true;

  /// True once the wallet has caught up with the node since it was opened.
  bool synced = false;

  /// True once the first scan has reached the node's height, on this launch or
  /// an earlier one.
  bool scanned;
  int balance = 0;
  int unlocked = 0;
  Outputs outputs = (total: 0, spent: 0, withoutKeyImage: 0);
  List<Transfer> transfers = const [];

  /// When the node last answered, and when a new block was last scanned.
  DateTime lastContact = DateTime.now();
  DateTime lastBlock = DateTime.now();

  /// Settings → Face ID to open: on unless the person turned it off. Kept
  /// inside the wallet's encrypted file rather than as plain text, so it
  /// can't be turned off by editing a file. lock.dart does the locking.
  bool lockOn;

  /// Settings → Test speed asks every node: on unless the person turned it
  /// off, when Test speed on Choose a node asks only the node picked. Kept
  /// inside the wallet's encrypted file, like [lockOn].
  bool testAllNodes;

  /// The person's own name for the wallet, shown on Home. Kept inside the
  /// wallet's encrypted file and never sent anywhere.
  String get name => _name ?? 'Monero wallet';
  String? _name;

  bool importing = false;

  /// True while [rescan] empties the wallet.
  bool rescanning = false;
  KeyImageImport? lastImport;
  int _noticeDismissedAt = 0;

  void _readWallet() {
    height = wallet.height;
    synced = wallet.isSynced;
    balance = wallet.balance;
    unlocked = wallet.unlockedBalance;
    outputs = wallet.outputs;
    transfers = wallet.transfers;
  }

  /// Saves the wallet with what the next launch has to know.
  Future<void> _save() {
    _savedHeight = height;
    _savedAt = DateTime.now();
    // An empty note is no note: a rescan takes back the other two.
    return wallet.save({
      _scannedNote: scanned ? '1' : '',
      _contactNote: '${lastContact.millisecondsSinceEpoch}',
      _importNote: lastImport?.toNote() ?? '',
      _lockNote: lockOn ? 'on' : 'off',
      _speedNote: testAllNodes ? 'all' : 'picked',
      _nameNote: _name ?? '',
    });
  }

  String get node => wallet.node!;

  /// The Tor proxy the node is reached through, or null if Tor is off.
  String? get tor => wallet.tor;

  int get blocksToGo => nodeHeight > height ? nodeHeight - height : 0;

  /// One block behind is normal for a few seconds each time a block arrives.
  bool get catchingUp => !synced || blocksToGo > 1;

  int get locking => balance - unlocked;

  /// Blocks until the newest payment (or the change from a spend) unlocks, 0
  /// if nothing recent explains the locked amount.
  int get lockingBlocks {
    var blocks = 0;
    for (final t in transfers) {
      final left = unlockBlocks - (t.height == 0 ? 0 : t.confirmations);
      if (left > blocks) blocks = left;
    }
    return blocks;
  }

  /// True while outputs without a key image have arrived since the notice was
  /// last dismissed.
  bool get showKeyImagesNotice => outputs.withoutKeyImage > _noticeDismissedAt;

  /// The first account's subaddresses that have had a payment, 0 being the
  /// primary address.
  Set<int> get paidSubaddresses => {
    for (final t in transfers) ...t.subaddresses,
  };

  /// The newest subaddress if nothing has been paid to it yet, otherwise a
  /// new one.
  int freshSubaddress() {
    final newest = wallet.subaddressCount - 1;
    return newest > 0 && !paidSubaddresses.contains(newest)
        ? newest
        : wallet.addSubaddress();
  }

  /// False when one more subaddress would be further than [receiveAhead] past
  /// the highest one paid, where the Monero GUI might not see payments to it.
  bool get canAddSubaddress =>
      wallet.subaddressCount - paidSubaddresses.fold(0, max) < receiveAhead;

  void dismissKeyImagesNotice() {
    _noticeDismissedAt = outputs.withoutKeyImage;
    notifyListeners();
  }

  void startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    refresh();
  }

  Future<void> refresh() async {
    if (_refreshing || importing || rescanning || _closed) return;
    _refreshing = true;
    // Starts the app's Tor at launch, and again if it ever stops. A start
    // that fails is tried again every eighth poll, not at each one.
    if (tor != null && _polls++ % 8 == 0) builtInTor.start().ignore();
    try {
      final tip = await wallet.nodeHeight();
      // Don't read the wallet while an import or a rescan is changing it.
      if (importing || rescanning || _closed) return;
      final now = DateTime.now();
      reachable = tip > 0;
      if (reachable) {
        nodeHeight = tip;
        lastContact = now;
      }
      final before = height;
      _readWallet();
      if (height != before) lastBlock = now;
      final firstScanDone = synced && !scanned;
      if (firstScanDone) scanned = true;
      notifyListeners();
      if (firstScanDone ||
          (height != _savedHeight && now.difference(_savedAt) >= saveEvery)) {
        await _save();
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Throws [WalletException] and keeps the current node if [node] can't be
  /// reached. [added] is kept as the public nodes added to the list.
  Future<void> changeNode(
    String node, {
    String? tor,
    List<String>? added,
  }) async {
    await wallet.connect(node, tor: tor, added: added);
    await refresh();
  }

  /// Throws [WalletException] if the wallet refuses the file.
  Future<void> importKeyImages(String path) async {
    importing = true;
    notifyListeners();
    try {
      final before = wallet.outputs;
      await wallet.importKeyImages(path);
      final after = wallet.outputs;
      lastImport = KeyImageImport(
        at: DateTime.now(),
        fileName: path.split(RegExp(r'[/\\]')).last,
        newlySpent: after.spent - before.spent,
        outputs: after,
      );
      _noticeDismissedAt = 0;
      await _save();
    } finally {
      importing = false;
      if (!_closed) notifyListeners();
    }
    await refresh();
  }

  /// Scans the blockchain again from [from], for payments a later restore
  /// height missed. Like the first sync: Home shows the scan and then asks for
  /// key images, which the rescan forgets. Throws [WalletException], and
  /// changes nothing, if the node can't be reached.
  Future<void> rescan(int from) async {
    rescanning = true;
    notifyListeners();
    try {
      await wallet.rescan(from);
      scanned = synced = false;
      lastImport = null;
      _noticeDismissedAt = 0;
      _readWallet();
      // Keeps the emptied wallet with its new restore height, so a launch
      // after this carries on with the rescan.
      await _save();
    } finally {
      rescanning = false;
      if (!_closed) notifyListeners();
    }
    await refresh();
  }

  /// Settings → Advanced → Subaddress lookahead, kept in the wallet's file.
  Future<void> setLookahead(Lookahead lookahead) async {
    await wallet.setLookahead(lookahead);
    notifyListeners();
    await save();
  }

  /// Saves the wallet now, for a change that no new block will bring a save
  /// for: a subaddress made on Receive, or its label.
  Future<void> save() => _closed ? Future.value() : _save();

  /// An empty [name] goes back to the default.
  Future<void> rename(String name) {
    _name = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
    return save();
  }

  Future<void> setLockOn(bool on) {
    lockOn = on;
    notifyListeners();
    return save();
  }

  Future<void> setTestAllNodes(bool on) {
    testAllNodes = on;
    notifyListeners();
    return save();
  }

  /// Stops watching the wallet and deletes it from this device.
  Future<void> forget() {
    _closed = true;
    _poll?.cancel();
    return wallet.forget();
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    wallet.close();
    super.dispose();
  }
}
