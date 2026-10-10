/// A view-only Monero wallet on top of monero_c (Monero's own wallet2 code).
///
/// The app keeps one wallet between launches, in wallet2's own two files: the
/// keys file, which holds the view key, and the cache, which holds what the
/// scan found (outputs, key images, history). wallet2 encrypts both with a key
/// made from the wallet's password. That password is 32 random bytes made here
/// and, between launches, kept only in the device's secure storage
/// (secret_store.dart); nobody types or sees it.
///
/// There is no parameter for a spend key or seed, so this code cannot create a
/// wallet that spends.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

// monero_c marks its flat API deprecated; the class API it points to is in src/.
// ignore_for_file: implementation_imports
import 'package:monero/src/monero.dart';
import 'package:monero/src/wallet2.dart';

import 'secret_store.dart';
import 'tor.dart';

/// The Monero networks the app watches wallets on: mainnet for real wallets,
/// stagenet for test wallets, whose coins are worth nothing.
enum Network {
  mainnet(0, '4'),
  stagenet(2, '5');

  const Network(this.id, this.prefix);

  /// wallet2's NetworkType.
  final int id;

  /// What a primary address on this network starts with.
  final String prefix;
}

/// The network of [address], from the character a primary address starts
/// with, or null if it is no primary address of a network the app watches.
/// wallet2 still checks the whole address when the wallet is made.
Network? networkOf(String address) {
  for (final network in Network.values) {
    if (address.startsWith(network.prefix)) return network;
  }
  return null;
}

/// About how high [network]'s chain is at [now], worked out from the time the
/// way wallet2 does (wallet2::get_approximate_blockchain_height): one block
/// every two minutes since a block whose time is known.
int approximateHeight(Network network, [DateTime? now]) {
  final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  return switch (network) {
    Network.mainnet => 1009827 + (seconds - 1458748658) ~/ 120,
    // Less closely: stagenet has been rolled back by about 60000 blocks.
    Network.stagenet => 32000 + (seconds - 1520937818) ~/ 120 - 60000,
  };
}

/// False when a node at [height] can't be on [network], or is too far
/// behind to be of use. Mainnet is about 1.5 million blocks ahead of
/// stagenet, so a node on one is far outside the other's range.
bool onNetwork(Network network, int height, [DateTime? now]) =>
    (height - approximateHeight(network, now)).abs() < 500000;

const atomicUnitsPerXmr = 1000000000000;

/// How far past the highest subaddress paid Receive hands out new ones. The
/// Monero GUI watches 199 past it (a window of 200, [defaultLookahead]), but
/// moves that window on only once a payment confirms, and checks a whole batch
/// of blocks against the window it had when the batch began. So payments to
/// several new subaddresses in one block, or while the GUI was closed, need
/// room to spare: at 200 the GUI could miss one.
const receiveAhead = 50;

/// How far past the last account and the last subaddress in use wallet2 looks
/// for payments: its subaddress lookahead. wallet2 watches the subaddresses up
/// to the highest one it has made or recorded a confirmed payment to, plus
/// [addresses] - 1, and misses payments further out.
typedef Lookahead = ({int accounts, int addresses});

/// wallet2's own default, 50 accounts × 200 subaddresses, which the Monero GUI
/// also uses.
const defaultLookahead = (accounts: 50, addresses: 200);

/// The largest [Lookahead] the app sets: wallet2 works out a key for every
/// subaddress it watches, which takes a few seconds per 100,000 on a phone.
const maxLookahead = 100000;

/// Where the wallet is kept between launches: wallet2's cache file, with its
/// keys file next to it under the same name plus ".keys". Null, as in tests,
/// means nothing is saved and every wallet lives in memory only. main() sets it.
String? walletFile;

/// wallet2's ring database on the iPhone (see the README), which only this
/// app's wallets use, so [ViewWallet.forgetSaved] empties it. Null where the
/// app doesn't own it: the Windows build shares the Monero GUI's. main() sets
/// it.
String? ringDatabase;

/// What the password is filed under in the device's secure storage: the
/// wallet file's path on Windows. An iPhone app's folder moves when the app is
/// updated, so there it is the file's name only.
String _passwordName(String walletFile) =>
    'Monero View Wallet: ${Platform.isIOS ? walletFile.split('/').last : walletFile}';

/// The name the node is remembered under, see [ViewWallet.remembered].
const _nodeNote = 'mvw.node';

/// The name it is remembered under, next to the node, that the node is
/// reached through Tor: empty for a direct connection.
const _torNote = 'mvw.tor';

/// The name the public nodes the person added to the list are remembered
/// under, next to the node, separated by spaces.
const _addedNote = 'mvw.added';

/// The names the restore height of the last rescan, and a lookahead other than
/// [defaultLookahead], are remembered under. wallet2 keeps both in the keys
/// file, which it writes only when the wallet is made; inside the cache they
/// are saved together with what the scan found.
const _restoreHeightNote = 'mvw.restoreHeight';
const _lookaheadNote = 'mvw.lookahead';

/// "1.5000" for 1500000000000 atomic units: 4 decimals, and more only when the
/// amount needs them to be exact. [short] cuts to 4 decimals whatever is left.
String formatXmr(int atomic, {bool short = false}) {
  final decimals = (atomic % atomicUnitsPerXmr).toString().padLeft(12, '0');
  return '${atomic ~/ atomicUnitsPerXmr}.'
      '${short ? decimals.substring(0, 4) : decimals.replaceFirst(RegExp(r'0{0,8}$'), '')}';
}

/// What a key images file starts with (wallet2's KEY_IMAGE_EXPORT_FILE_MAGIC).
const _keyImagesMagic = 'Monero key image export\x03';

/// Far bigger than any wallet's key images file: about 700,000 outputs.
const maxKeyImagesFile = 64 * 1024 * 1024;

/// True if the file at [path] starts like a key images file and isn't too big
/// to be one. Reads only its first few bytes.
bool looksLikeKeyImagesFile(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    if (file.lengthSync() > maxKeyImagesFile) return false;
    return String.fromCharCodes(file.readSync(_keyImagesMagic.length)) ==
        _keyImagesMagic;
  } on FileSystemException {
    return false;
  } finally {
    file?.closeSync();
  }
}

class WalletException implements Exception {
  WalletException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Transfer {
  Transfer({
    required this.incoming,
    required this.amount,
    required this.height,
    required this.confirmations,
    required this.time,
    this.subaddresses = const {},
    this.account = 0,
    this.fee = 0,
    this.hash = '',
  });
  final bool incoming;
  final int amount;

  /// 0 while the transaction is still unconfirmed.
  final int height;
  final int confirmations;
  final DateTime time;

  /// For a payment to the first account: the subaddresses it went to, 0
  /// being the primary address. Empty for spends.
  final Set<int> subaddresses;

  /// The account the payment went to or the spend came from, 0 being the
  /// primary account.
  final int account;

  /// The network fee the transaction paid. For a payment received, the sender
  /// paid it.
  final int fee;

  /// The transaction ID, 64 hex characters.
  final String hash;

  /// True if [other] is this entry in a later read of the history. A
  /// transaction that pays several subaddresses has an entry for each.
  bool sameAs(Transfer other) =>
      other.hash == hash &&
      other.incoming == incoming &&
      other.account == account &&
      other.subaddresses.length == subaddresses.length &&
      other.subaddresses.containsAll(subaddresses);
}

/// How many of the wallet's outputs are spent or still lack a key image.
typedef Outputs = ({int total, int spent, int withoutKeyImage});

// ponytail: the getters below read wallet2 while its sync thread may be
// writing, and the subaddress calls write to it (also while [save] reads it),
// as Cake Wallet and the Monero GUI do. If that ever crashes, route them
// through the same pause that importKeyImages uses.
class ViewWallet {
  ViewWallet._(this._manager, this._wallet, {required this._saved});

  final Wallet2WalletManager _manager;
  final Wallet2Wallet _wallet;

  /// Whether the wallet is kept in [walletFile], or in memory only.
  final bool _saved;
  String? _node;
  String? _tor;
  List<String> _added = const [];

  /// The height the scan starts from: the one given at setup, or the one of
  /// the last [rescan].
  int get restoreHeight => _wallet.getRefreshFromBlockHeight();

  Network get network =>
      Network.values.firstWhere((n) => n.id == _wallet.nettype());

  /// The subaddress lookahead, see [setLookahead].
  Lookahead get lookahead => _lookahead;
  Lookahead _lookahead = defaultLookahead;

  /// The node in use ("host:port"), once [connect] has succeeded.
  String? get node => _node;

  /// The Tor proxy the node is reached through, or null for a direct
  /// connection.
  String? get tor => _tor;

  /// Public nodes the person added to the list on Choose a node.
  List<String> get addedNodes => _added;

  /// Null if [viewKey] is the secret view key of the mainnet or stagenet
  /// address [address], otherwise wallet2's reason: "failed to parse
  /// address", "view key does not match address" or "failed to verify secret
  /// view key".
  ///
  /// Checked by making a wallet in memory and freeing it before returning,
  /// which takes a third of a second when the keys match. Freed at once, not
  /// with [close]: on a helper isolate that ends as soon as this returns,
  /// [close] would never get to run, and the wallet would keep the view key
  /// in memory until the app quits. monero_c's own keyValid can't be used: it
  /// reads every network except mainnet as testnet.
  static String? keysProblem({
    required String address,
    required String viewKey,
  }) {
    final network = networkOf(address);
    if (network == null) return 'failed to parse address';
    final manager = MoneroWalletManagerFactory().getWalletManager();
    final wallet = manager.createWalletFromKeys(
      path: '', // in memory only
      password: '',
      nettype: network.id,
      restoreHeight: 0,
      addressString: address,
      viewKeyString: viewKey,
      spendKeyString: '',
    );
    final problem = wallet.status() == 0 ? null : wallet.errorString();
    // Never connected, so its sync thread has nothing to finish.
    manager.closeWallet(wallet, false);
    return problem;
  }

  /// The height [node] ("host:port") reports, 0 if it can't be reached, and
  /// how many milliseconds it took to connect and answer. Uses the wallet
  /// library's own connection, with no wallet involved, made through the Tor
  /// proxy [tor] if one is given.
  ///
  /// The library has one such connection, so probes run one at a time. They
  /// take turns in the root zone: a caller's zone that stops running, as a
  /// finished widget test's does, must not keep the next probe waiting.
  static Future<({int height, int ms})> probeNode(String node, {String? tor}) =>
      Zone.root.run(() async {
        while (_probing) {
          final turn = Completer<void>();
          _waitingToProbe.add(turn);
          await turn.future;
        }
        _probing = true;
        try {
          final manager = MoneroWalletManagerFactory().getWalletManager();
          final address = manager.ffiAddress();
          return await Isolate.run(() async {
            final manager = MoneroWalletManager(Pointer.fromAddress(address));
            // Always set: the library keeps the proxy of the probe before.
            manager.setProxy(tor ?? '');
            manager.setDaemonAddress(node);
            final watch = Stopwatch()..start();
            final height = await manager.blockchainHeight();
            return (height: height, ms: watch.elapsedMilliseconds);
          });
        } finally {
          _probing = false;
          if (_waitingToProbe.isNotEmpty) {
            _waitingToProbe.removeAt(0).complete();
          }
        }
      });

  static bool _probing = false;
  static final _waitingToProbe = <Completer<void>>[];

  /// Throws [WalletException] if the address is not a mainnet or stagenet
  /// primary address or the view key does not belong to it (wallet2 derives
  /// the public view key and compares it with the address).
  ///
  /// With [save] the wallet is written to [walletFile] under a new random
  /// password, replacing the wallet saved before: the app keeps one. Without
  /// it, or with no [walletFile], the wallet is held in memory only.
  static ViewWallet create({
    required String address,
    required String viewKey,
    required int restoreHeight,
    bool save = false,
  }) {
    final network = networkOf(address);
    if (network == null) throw WalletException('failed to parse address');
    final path = save ? walletFile : null;
    var password = '';
    if (path != null) {
      password = _newPassword();
      try {
        forgetSaved();
        File(path).parent.createSync(recursive: true);
        if (!secretStore.write(
          _passwordName(path),
          '${network.name}:$password',
        )) {
          throw const FileSystemException();
        }
      } on FileSystemException {
        throw WalletException("The wallet can't be saved on this device.");
      }
    }
    final manager = MoneroWalletManagerFactory().getWalletManager();
    final wallet = manager.createWalletFromKeys(
      path: path ?? '', // empty path: wallet2 keeps the wallet in memory
      password: password,
      nettype: network.id,
      restoreHeight: restoreHeight,
      addressString: address,
      viewKeyString: viewKey,
      spendKeyString: '',
    );
    if (wallet.status() != 0) {
      final error = wallet.errorString();
      manager.closeWallet(wallet, false);
      if (path != null) forgetSaved();
      throw WalletException(error);
    }
    // Off mainnet wallet2 also writes the address next to the wallet, as plain
    // text. Nothing reads it.
    if (path != null) _delete('$path.address.txt');
    return ViewWallet._(manager, wallet, saved: path != null);
  }

  /// Opens the wallet saved on this device and starts syncing with the node
  /// it used last, without waiting for that node to answer. Null if no wallet
  /// is saved or it can't be opened; see [savedButUnreadable].
  ///
  /// A wallet whose setup never reached "Start sync" has no node yet. It is
  /// deleted, so setup starts over.
  static ViewWallet? openSaved() {
    final path = walletFile;
    if (path == null || !File('$path.keys').existsSync()) return null;
    final saved = secretStore.read(_passwordName(path));
    if (saved == null) return null;
    // The network is kept with the password. wallet2 has to be told it, and
    // opens that network's ring database (see the README) before it reads the
    // files, so trying one network and then the other would open both. Builds
    // before mainnet kept the password alone, for a stagenet wallet.
    final colon = saved.indexOf(':');
    final network = colon < 0
        ? Network.stagenet
        : Network.values.asNameMap()[saved.substring(0, colon)];
    if (network == null) return null;
    final manager = MoneroWalletManagerFactory().getWalletManager();
    final wallet = manager.openWallet(
      path: path,
      password: saved.substring(colon + 1),
      networkType: network.id,
    );
    if (wallet.status() != 0) {
      manager.closeWallet(wallet, false);
      return null;
    }
    final node = wallet.getCacheAttribute(key: _nodeNote);
    if (node.isEmpty) {
      manager.closeWallet(wallet, false);
      forgetSaved();
      return null;
    }
    // Anything saved there means Tor: the proxy is the app's own Tor, whatever
    // address an earlier build saved.
    final tor = wallet.getCacheAttribute(key: _torNote).isEmpty
        ? null
        : torAddress;
    final restoreHeight = int.tryParse(
      wallet.getCacheAttribute(key: _restoreHeightNote),
    );
    if (restoreHeight != null && restoreHeight >= 0) {
      wallet.setRefreshFromBlockHeight(
        refresh_from_block_height: restoreHeight,
      );
    }
    final lookahead = _readLookahead(
      wallet.getCacheAttribute(key: _lookaheadNote),
    );
    if (lookahead != null) {
      wallet.setSubaddressLookahead(
        major: lookahead.accounts,
        minor: lookahead.addresses,
      );
    }
    // Neither call contacts the node: the sync thread does, once it runs. With
    // a proxy it only ever connects through it, so until Tor is running the
    // node can't be reached; it is never asked directly instead.
    wallet.init(daemonAddress: node, proxyAddress: tor ?? '');
    wallet.startRefresh();
    final added = wallet.getCacheAttribute(key: _addedNote);
    return ViewWallet._(manager, wallet, saved: true)
      .._node = node
      .._tor = torProxy = tor
      .._added = [
        for (final host in added.split(' '))
          if (host.isNotEmpty) host,
      ]
      .._lookahead = lookahead ?? defaultLookahead;
  }

  /// "50:1000" as kept by [setLookahead], or null for anything else.
  static Lookahead? _readLookahead(String note) {
    final parts = note.split(':').map(int.tryParse).toList();
    if (parts case [final int accounts, final int addresses]
        when validLookahead((accounts: accounts, addresses: addresses))) {
      return (accounts: accounts, addresses: addresses);
    }
    return null;
  }

  /// True for a lookahead wallet2 takes without failing: it stops the app
  /// for 0, and for more than it can count.
  static bool validLookahead(Lookahead lookahead) =>
      lookahead.accounts >= 1 &&
      lookahead.addresses >= 1 &&
      lookahead.accounts <= maxLookahead &&
      lookahead.addresses <= maxLookahead &&
      lookahead.accounts * lookahead.addresses <= maxLookahead;

  /// True if a wallet is saved on this device and [openSaved] could not open
  /// it: its password is gone from the secure storage, or a file is damaged.
  static bool get savedButUnreadable =>
      walletFile != null && File('$walletFile.keys').existsSync();

  /// Deletes the saved wallet: its password first, without which the files
  /// can't be read, then the files, and empties [ringDatabase]. Close the
  /// wallet before calling this: Windows won't delete a keys file that is
  /// open. A file that can't be deleted stays behind unreadable, until the
  /// next [create] tries again.
  static void forgetSaved() {
    final path = walletFile;
    if (path == null) return;
    secretStore.delete(_passwordName(path));
    // The cache, the keys file, what wallet2 leaves if it is stopped in the
    // middle of writing either, and the address file (see [create]).
    for (final suffix in ['', '.new', '.keys', '.keys.new', '.address.txt']) {
      _delete('$path$suffix');
    }
    // The rings it saw, for each network. The folder stays, so it stays out
    // of backups.
    final rings = ringDatabase;
    if (rings == null) return;
    try {
      for (final entry in Directory(rings).listSync()) {
        try {
          entry.deleteSync(recursive: true);
        } on FileSystemException {
          // Encrypted with a key made from the view key, which is gone now.
        }
      }
    } on FileSystemException {
      // wallet2 never made it.
    }
  }

  static void _delete(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // See [forgetSaved].
    }
  }

  /// 32 random bytes as 64 hex characters.
  static String _newPassword() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  String get address => _wallet.address();
  bool get isViewOnly => _wallet.watchOnly();

  /// The first account's subaddresses that wallet2 knows of: the ones made
  /// with [addSubaddress] and the ones it found a payment to. Index 0 is the
  /// primary address.
  int get subaddressCount => _wallet.numSubaddresses(accountIndex: 0);

  /// Worked out from the keys, so the Monero GUI has the same address under
  /// the same number.
  String subaddress(int index) =>
      _wallet.address(accountIndex: 0, addressIndex: index);

  /// Makes the first account's next subaddress and returns its index.
  int addSubaddress() {
    _wallet.addSubaddress(accountIndex: 0);
    return subaddressCount - 1;
  }

  /// The user's own name for subaddress [index]. wallet2 keeps labels with the
  /// wallet (in its cache, written by [save]) and never sends them to the
  /// node.
  String label(int index) =>
      _wallet.getSubaddressLabel(accountIndex: 0, addressIndex: index);

  void setLabel(int index, String label) => _wallet.setSubaddressLabel(
    accountIndex: 0,
    addressIndex: index,
    label: label,
  );

  /// Height scanned so far.
  int get height => _wallet.blockChainHeight();

  /// True once the wallet has scanned up to the node's height.
  bool get isSynced => _wallet.synchronized();

  int get balance => _sumAccounts((i) => _wallet.balance(accountIndex: i));
  int get unlockedBalance =>
      _sumAccounts((i) => _wallet.unlockedBalance(accountIndex: i));

  int _sumAccounts(int Function(int account) amount) {
    var total = 0;
    for (var i = 0; i < _wallet.numSubaddressAccounts(); i++) {
      total += amount(i);
    }
    return total;
  }

  /// [Outputs.withoutKeyImage] counts unspent outputs with no key image yet.
  /// If one of those is spent, the balance stays too high until key images are
  /// imported again.
  Outputs get outputs {
    final coins = _wallet.coins()..refresh();
    var spent = 0, withoutKeyImage = 0;
    for (var i = 0; i < coins.count(); i++) {
      final coin = coins.coin(i);
      if (coin.spent()) {
        spent++;
      } else if (!coin.keyImageKnown()) {
        withoutKeyImage++;
      }
    }
    return (
      total: coins.count(),
      spent: spent,
      withoutKeyImage: withoutKeyImage,
    );
  }

  /// Newest first.
  List<Transfer> get transfers {
    final history = _wallet.history()..refresh();
    final all = [
      for (var i = 0; i < history.count(); i++) history.transaction(i),
    ]..sort((a, b) => b.timestamp().compareTo(a.timestamp()));
    return [
      for (final tx in all.where((tx) => !tx.isFailed()))
        Transfer(
          incoming: tx.direction() == 0,
          amount: tx.amount(),
          height: tx.isPending() ? 0 : tx.blockHeight(),
          confirmations: tx.confirmations(),
          time: DateTime.fromMillisecondsSinceEpoch(tx.timestamp() * 1000),
          subaddresses: tx.direction() == 0 && tx.subaddrAccount() == 0
              ? {for (final i in tx.subaddrIndex().split('|')) ?int.tryParse(i)}
              : const {},
          account: tx.subaddrAccount(),
          fee: tx.fee(),
          hash: tx.hash(),
        ),
    ];
  }

  /// Points the wallet at [node] ("host:port") and starts wallet2's sync
  /// thread, which scans to the tip and then follows the chain until [close].
  /// Poll [height] and [isSynced] for progress. Returns the node's height.
  /// Call it again to change node; if the new one can't be reached, the wallet
  /// stays on the node it had.
  ///
  /// wallet2 uses TLS when the node offers it, without checking the
  /// certificate (most nodes use a self-signed one), and plain HTTP otherwise.
  ///
  /// With [tor], the address of Tor's SOCKS proxy ([torAddress]), every
  /// connection to the node is made by that Tor, which also looks up the
  /// node's name. wallet2 has no direct connection to fall back to.
  ///
  /// A node whose height doesn't fit the wallet's network (see [onNetwork])
  /// is refused like one that can't be reached: scanning another network's
  /// blocks would find nothing.
  ///
  /// A saved wallet remembers the node and the proxy for [openSaved], and
  /// [added] as [addedNodes] when it is given.
  Future<int> connect(String node, {String? tor, List<String>? added}) async {
    final previous = _node;
    final previousTor = _tor;
    final saved = _saved;
    final tip = await _inTurn((w) {
      Never refuse(String problem) {
        if (previous != null) {
          w.init(daemonAddress: previous, proxyAddress: previousTor ?? '');
          w.connected(); // wallet2 only notices it is back when asked
        }
        throw WalletException(problem);
      }

      if (!w.init(daemonAddress: node, proxyAddress: tor ?? '')) {
        throw WalletException(w.errorString());
      }
      if (w.connected() != 1) {
        refuse(
          tor == null
              ? "Can't reach the node."
              : "Can't reach the node over Tor.",
        );
      }
      final tip = w.daemonBlockChainHeight();
      final network = Network.values.firstWhere((n) => n.id == w.nettype());
      if (!onNetwork(network, tip)) {
        refuse("That isn't a ${network.name} node, or it is far from synced.");
      }
      if (saved) {
        w.setCacheAttribute(key: _nodeNote, value: node);
        w.setCacheAttribute(key: _torNote, value: tor ?? '');
        if (added != null) {
          w.setCacheAttribute(key: _addedNote, value: added.join(' '));
        }
        w.store();
      }
      w.startRefresh();
      return tip;
    });
    _node = node;
    _tor = torProxy = tor;
    if (added != null) _added = List.unmodifiable(added);
    return tip;
  }

  /// A small value kept under [name] inside the wallet's encrypted cache file
  /// by [save], or null if there is none. Read it only while nothing else is
  /// using the wallet, as when it has just been opened.
  String? remembered(String name) {
    final value = _wallet.getCacheAttribute(key: name);
    return value.isEmpty ? null : value;
  }

  /// Writes the wallet's cache to [walletFile], with [notes] for [remembered]
  /// inside it. A wallet held in memory only takes the notes and saves nothing.
  ///
  /// monero_c's store() stops the sync thread between two batches of blocks,
  /// writes, and lets the thread carry on, so this is safe during a scan.
  Future<void> save([Map<String, String> notes = const {}]) {
    final saved = _saved;
    return _inTurn((w) {
      notes.forEach((name, value) {
        w.setCacheAttribute(key: name, value: value);
      });
      if (saved) w.store();
    });
  }

  /// The node's height, or 0 if it can't be reached. wallet2 asks the node at
  /// most every 30 seconds.
  Future<int> nodeHeight() => _blocking((w) => w.daemonBlockChainHeight());

  /// Imports a key images file exported by the Monero GUI or CLI, so spends of
  /// those outputs are subtracted from the balance.
  ///
  /// wallet2 asks the node which of the key images are spent, and refuses to
  /// do that unless the node is marked trusted: the node learns that these key
  /// images belong to one wallet. The mark is kept only for this call.
  ///
  /// Any file can be opened with the app, so one that doesn't start like a
  /// key images file, or is far too big to be one, is refused before wallet2
  /// reads all of it into memory.
  Future<void> importKeyImages(String path) {
    if (!looksLikeKeyImagesFile(path)) {
      return Future.error(
        WalletException('Bad key image export file magic: not read'),
      );
    }
    final syncing = _node != null;
    return _inTurn((w) {
      if (syncing) {
        // Keep the sync thread out of the wallet during the import. refresh()
        // shares a lock with it, so it returns once the thread has let go.
        w.pauseRefresh();
        w.refresh();
      }
      final wasTrusted = w.trustedDaemon();
      w.setTrustedDaemon(arg: true);
      try {
        if (!w.importKeyImages(path)) throw WalletException(w.errorString());
      } finally {
        w.setTrustedDaemon(arg: wasTrusted);
        if (syncing) w.startRefresh();
      }
    });
  }

  /// Forgets what the scan found (outputs, history, imported key images) and
  /// scans the blockchain again from [from], which becomes the restore height.
  /// Subaddresses and their labels stay. Returns once the wallet is emptied;
  /// wallet2's sync thread then scans, as on the first sync, and [isSynced] is
  /// false until it has caught up. Throws [WalletException], and changes
  /// nothing, if the node can't be reached.
  ///
  /// Saving the wallet afterwards keeps the new restore height (see
  /// [openSaved]) with the emptied wallet.
  Future<void> rescan(int from) async {
    if (_node == null) throw WalletException("Can't reach the node.");
    return _inTurn((w) {
      // Keep the sync thread out of the wallet; see importKeyImages.
      w.pauseRefresh();
      w.refresh();
      final before = w.getRefreshFromBlockHeight();
      // An empty wallet holds only the genesis block. One that hasn't listed
      // any block yet only needs the new height.
      var emptied = w.blockChainHeight() <= 1;
      if (!emptied) {
        // wallet2's rescan empties the wallet, then refreshes it, which does
        // nothing while the sync thread is paused except fetch the block ids
        // up to the restore height: with that at 0 for a moment it returns at
        // once. It does neither if the node isn't answering.
        w.setRefreshFromBlockHeight(refresh_from_block_height: 0);
        w.rescanBlockchain();
        emptied = w.blockChainHeight() <= 1;
      }
      w.setRefreshFromBlockHeight(
        refresh_from_block_height: emptied ? from : before,
      );
      if (emptied) {
        w.setCacheAttribute(key: _restoreHeightNote, value: '$from');
      }
      w.startRefresh();
      if (!emptied) throw WalletException("Can't reach the node.");
    });
  }

  /// Sets the subaddress lookahead. wallet2 starts watching a larger one at
  /// once; payments it missed before show after a [rescan]. A smaller one
  /// applies only past the subaddresses it watches already. Kept in the
  /// wallet's file by the next save.
  Future<void> setLookahead(Lookahead lookahead) {
    if (!validLookahead(lookahead)) {
      throw ArgumentError.value(lookahead, 'lookahead');
    }
    final syncing = _node != null;
    _lookahead = lookahead;
    return _inTurn((w) {
      // wallet2 adds the new subaddresses to the table its sync thread reads.
      if (syncing) {
        w.pauseRefresh();
        w.refresh();
      }
      w.setSubaddressLookahead(
        major: lookahead.accounts,
        minor: lookahead.addresses,
      );
      w.setCacheAttribute(
        key: _lookaheadNote,
        value: lookahead == defaultLookahead
            ? ''
            : '${lookahead.accounts}:${lookahead.addresses}',
      );
      if (syncing) w.startRefresh();
    });
  }

  /// Frees the wallet, after any call still running on a helper isolate has
  /// finished with it. What was scanned since the last [save] is scanned again
  /// next time. Safe to call twice.
  Future<void> close() => _closing ??= _close();

  Future<void>? _closing;

  Future<void> _close() async {
    await _turn;
    await Future.wait(_calls);
    // wallet2 first waits for its sync thread to let go, which can take
    // minutes when the node is slow to answer, over Tor especially: not on
    // the UI isolate, or the app would freeze until then.
    final manager = _manager.ffiAddress();
    final wallet = _wallet.ffiAddress();
    await Isolate.run(
      () =>
          MoneroWalletManager(Pointer.fromAddress(manager))
              .closeWallet(MoneroWallet(Pointer.fromAddress(wallet)), false),
    );
  }

  /// Closes the wallet and deletes it from this device, see [forgetSaved].
  Future<void> forget() async {
    await close();
    if (_saved) forgetSaved();
  }

  final _calls = <Future<void>>{};
  Future<void> _turn = Future.value();

  /// [_blocking] for the calls that change or save the wallet: they run one at
  /// a time, in the order they were asked for.
  Future<T> _inTurn<T>(T Function(Wallet2Wallet wallet) call) {
    final result = _turn.then((_) => _blocking(call));
    _turn = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Runs a blocking wallet call off the UI isolate.
  Future<T> _blocking<T>(T Function(Wallet2Wallet wallet) call) {
    final result = _onIsolate(_wallet.ffiAddress(), call);
    final done = result.then<void>((_) {}, onError: (_) {});
    _calls.add(done);
    done.whenComplete(() => _calls.remove(done));
    return result;
  }

  /// Only the wallet's address crosses over, because pointers can't be sent
  /// between isolates. Static so the closure can't capture anything else.
  static Future<T> _onIsolate<T>(
    int address,
    T Function(Wallet2Wallet wallet) call,
  ) => Isolate.run(() => call(MoneroWallet(Pointer.fromAddress(address))));
}
