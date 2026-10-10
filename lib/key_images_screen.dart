import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'advanced_screen.dart';
import 'pick_file.dart';
import 'session.dart';
import 'tor.dart';
import 'ui.dart';
import 'wallet.dart';

/// Why a key images file wasn't imported: screen 6 of the design, "Import
/// problem".
enum ImportProblem {
  otherWallet('This file is from another wallet'),
  notKeyImages("This isn't a key images file"),
  missingOutputs('Some outputs are missing'),

  /// Not an error: the file waits until this device has scanned as far as the
  /// node, and is then imported by itself.
  notSynced('Finishing sync first'),
  noNode("Your node didn't answer"),
  failed("The key images weren't imported");

  const ImportProblem(this.title);

  final String title;

  /// Worked out from the wallet library's error message. A file that lists
  /// outputs this device hasn't found reads as [missingOutputs], which is
  /// [notSynced] while the scan hasn't caught up.
  static ImportProblem from(String error) {
    if (error.contains('Failed to decrypt') ||
        error.contains('different account')) {
      return otherWallet;
    }
    if (error.contains('out of date') || error.contains('Offset larger')) {
      return missingOutputs;
    }
    if (error.contains('file magic') ||
        error.contains('Bad data size') ||
        error.contains('failed to read file')) {
      return notKeyImages;
    }
    // Importing asks the node which key images are spent.
    if (error.contains('daemon') || error.contains('is_key_image_spent')) {
      return noNode;
    }
    return failed;
  }
}

/// How many key images a file of [size] bytes holds if it is a Monero key
/// images file, or null if it can't be one. The file is the header "Monero key
/// image export\003" (24 bytes), an 8-byte nonce, then encrypted: where the
/// outputs start (4 bytes) and the wallet's two public keys (64), 96 bytes per
/// key image with its signature, and a 64-byte signature at the end. The
/// Monero GUI exports every output's key image, starting from the first.
int? keyImagesInFile(int size) {
  const fixed = 24 + 8 + 4 + 64 + 64;
  if (size < fixed || (size - fixed) % 96 != 0) return null;
  return (size - fixed) ~/ 96;
}

/// "1.3 KB" for 1316 bytes, as the iPhone's Files app counts.
String formatSize(int bytes) {
  if (bytes < 1000) return plural(bytes, 'byte');
  if (bytes < 1000000) {
    return '${(bytes / 1000).toStringAsFixed(bytes < 10000 ? 1 : 0)} KB';
  }
  return '${(bytes / 1000000).toStringAsFixed(1)} MB';
}

/// "5Abc12…9xYz34": enough of an address to tell it from another.
String shortAddress(String address) => address.length <= 14
    ? address
    : '${address.substring(0, 6)}…${address.substring(address.length - 6)}';

/// True once a file can be imported: the node answers, and this device has
/// scanned as far as it, and at least to [height].
bool readyToImport(WalletSession s, {int height = 0}) =>
    s.reachable &&
    s.scanned &&
    !s.catchingUp &&
    !s.importing &&
    !s.rescanning &&
    s.height >= height;

/// What the Import problem screen asks the screen below it to do.
enum _Next {
  /// Import the same file again: sync caught up, or the node may answer now.
  again,

  /// Choose another file.
  another,
}

/// Screen 4 of the design: "Import key images", from a file the GUI exported.
class KeyImagesScreen extends StatefulWidget {
  const KeyImagesScreen(this.session, {super.key});

  final WalletSession session;

  @override
  State<KeyImagesScreen> createState() => _KeyImagesScreenState();
}

class _KeyImagesScreenState extends State<KeyImagesScreen> {
  bool _choosing = false;

  /// A file opened with the app from elsewhere, waiting for Import.
  KeyImagesFile? _received;

  /// The file being imported, or waiting on the Import problem screen. The app
  /// deletes its copy once the file is imported or given up.
  KeyImagesFile? _file;

  /// True while the wallet reads [_file].
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _received = takeKeyImagesFile();
    receivedKeyImagesFile.addListener(_onReceived);
  }

  @override
  void dispose() {
    receivedKeyImagesFile.removeListener(_onReceived);
    // Left without importing it: the app keeps no copy.
    _received?.discard();
    if (!_importing) _file?.discard();
    super.dispose();
  }

  void _onReceived() {
    final file = takeKeyImagesFile();
    if (file == null) return;
    _received?.discard();
    setState(() => _received = file);
  }

  /// Asks for a file; null if the picker was cancelled.
  Future<KeyImagesFile?> _pick() async {
    setState(() => _choosing = true);
    try {
      final file = await pickKeyImagesFile();
      if (!mounted) file?.discard();
      return mounted ? file : null;
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _choose() async {
    final file = await _pick();
    if (file != null) await _import(file);
  }

  void _importReceived() {
    final file = _received!;
    setState(() => _received = null);
    _import(file);
  }

  /// Imports [file], or explains on the Import problem screen why not, until
  /// it is imported or given up. Then deletes the app's copy of each file.
  Future<void> _import(KeyImagesFile file) async {
    final s = widget.session;
    var waitFor = 0;
    var waited = false;
    setState(() => _file = file);
    try {
      while (mounted) {
        ImportProblem problem;
        if (!readyToImport(s, height: waitFor)) {
          problem = ImportProblem.notSynced;
          waitFor = s.nodeHeight;
        } else {
          try {
            setState(() => _importing = true);
            await s.importKeyImages(file.path);
            return;
          } on WalletException catch (e) {
            problem = ImportProblem.from(e.message);
          } finally {
            _importing = false;
            if (mounted) setState(() {});
          }
          // A file can list a payment this device hasn't scanned yet: wait for
          // the next blocks once, and only then call outputs missing.
          if (problem == ImportProblem.missingOutputs &&
              !waited &&
              (s.blocksToGo > 0 || !readyToImport(s))) {
            problem = ImportProblem.notSynced;
            waitFor = s.nodeHeight;
          }
        }
        if (!mounted) return;
        waited = waited || problem == ImportProblem.notSynced;
        final next = await Navigator.push<_Next>(
          context,
          MaterialPageRoute(
            builder: (_) => ImportProblemScreen(
              problem: problem,
              session: s,
              file: file,
              waitFor: waitFor,
            ),
          ),
        );
        if (next == null || !mounted) return;
        if (next == _Next.another) {
          file.discard();
          final another = await _pick();
          if (another == null) return;
          setState(() => _file = file = another);
          waitFor = 0;
          waited = false;
        }
      }
    } finally {
      file.discard();
      if (identical(_file, file)) _file = null;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final s = widget.session;
      final last = s.lastImport;
      final busy = _choosing || _file != null || s.importing;
      final received = _received;
      final howToMove = defaultTargetPlatform == TargetPlatform.iOS
          ? '2. Get the file onto this iPhone, for example by AirDrop or '
                'iCloud Drive.\n'
                '3. Choose it here, or open it with this app from Files or '
                'the share sheet.'
          : '2. Save the file where this device can reach it.\n'
                '3. Choose it here.';
      return PopScope(
        canPop: !busy,
        child: Screen(
          title: 'Import key images',
          canGoBack: !busy,
          bottom: last == null
              ? null
              : FilledButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
          children: [
            Text(
              "Key images let this app see what you've spent. Without them "
              'it only sees money coming in, so the balance can be too high.',
              style: context.body,
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'From the Monero GUI, as a file',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. In the GUI (Advanced mode) open Send → Advanced '
                    'options → Key images and press Export.\n$howToMove',
                    style: context.body,
                  ),
                  const SizedBox(height: 12),
                  if (received != null) ...[
                    Text('Received', style: context.caption),
                    Text(
                      received.name,
                      style: mono(),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: busy ? null : _importReceived,
                      child: Text(
                        s.importing ? 'Importing…' : 'Import this file',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : _choose,
                      child: const Text('Choose another file'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: busy ? null : _choose,
                      child: Text(s.importing ? 'Importing…' : 'Choose file'),
                    ),
                  if (!s.reachable || !readyToImport(s))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        !s.reachable
                            ? "Can't reach your node. An import waits until "
                                  'it answers.'
                            : s.catchingUp
                            ? 'Still syncing · '
                                  '${plural(s.blocksToGo, 'block')} to go. An '
                                  'import waits for it.'
                            : 'Still syncing. An import waits for it.',
                        style: context.caption,
                      ),
                    ),
                ],
              ),
            ),
            Note(
              'Importing asks your node (${s.node}) which of these key '
              "images are spent. A node you don't run then knows those "
              'spends come from one wallet. Import through your own node to '
              'keep that private.',
            ),
            if (last != null) ...[
              const SectionHeader('Last import'),
              FactsCard([
                (
                  'When',
                  Text(
                    '${formatDate(last.at)}, ${formatTime(last.at)}',
                    style: context.body,
                  ),
                ),
                (
                  'From',
                  Text(
                    last.fileName,
                    style: context.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                (
                  'Key images',
                  Text(
                    '${last.outputs.total - last.outputs.withoutKeyImage}',
                    style: mono(),
                  ),
                ),
                ('Newly spent', Text('${last.newlySpent}', style: mono())),
                (
                  'Outputs without one',
                  Text('${last.outputs.withoutKeyImage}', style: mono()),
                ),
              ]),
            ],
            if (last == null)
              Center(
                child: TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Not now'),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Screen 6 of the design: why [file] wasn't imported, two facts about it, and
/// the fix. For [ImportProblem.notSynced] it shows the sync and goes back to
/// import the file by itself once [readyToImport]. Going back without a fix
/// gives the file up.
class ImportProblemScreen extends StatefulWidget {
  const ImportProblemScreen({
    super.key,
    required this.problem,
    required this.session,
    required this.file,
    this.waitFor = 0,
  });

  final ImportProblem problem;
  final WalletSession session;
  final KeyImagesFile file;

  /// For [ImportProblem.notSynced]: the height to scan to first.
  final int waitFor;

  @override
  State<ImportProblemScreen> createState() => _ImportProblemScreenState();
}

class _ImportProblemScreenState extends State<ImportProblemScreen> {
  late final int _size = widget.file.size;
  late final int _startHeight = widget.session.height;
  bool _leaving = false;

  WalletSession get _s => widget.session;

  void _leave(_Next? next) {
    _leaving = true;
    Navigator.pop(context, next);
  }

  /// Goes back to import once sync has caught up, if this screen is on top.
  void _importWhenReady() {
    if (_leaving || !readyToImport(_s, height: widget.waitFor)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _leaving) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) _leave(_Next.again);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_s, builtInTor]),
    builder: (context, _) {
      final c = context.colors;
      final problem = widget.problem;
      if (problem == ImportProblem.notSynced) _importWhenReady();
      final file = '${widget.file.name} (${formatSize(_size)})';
      final inFile = keyImagesInFile(_size);
      final found = _s.outputs.total;
      final (String body, List<(String, Widget)> facts) = switch (problem) {
        ImportProblem.otherWallet => (
          "It can't be opened with this wallet's view key. Export the key "
              'images again from the GUI wallet that matches this address, '
              'and choose the new file.',
          [
            (
              'Wallet on this $thisDevice',
              _Fact(shortAddress(_s.wallet.address)),
            ),
            ('File', _Fact(file)),
          ],
        ),
        ImportProblem.notKeyImages => (
          'Choose the file the Monero GUI saved from Send → Advanced '
              'options → Key images → Export.',
          [
            ('File', _Fact(widget.file.name)),
            ('Size', _Fact(formatSize(_size))),
          ],
        ),
        ImportProblem.missingOutputs => (
          'The file mentions '
              '${inFile != null && inFile > found ? plural(inFile - found, 'output') : 'outputs'} '
              'this $thisDevice never found, because it started scanning '
              "after they arrived. Rescan from the GUI's restore height, then "
              'import again.',
          [
            ('Restore height here', _Fact('${_s.wallet.restoreHeight}')),
            if (inFile != null && inFile > found)
              ('Outputs not found', _Fact('${inFile - found} of $inFile'))
            else
              ('Outputs found here', _Fact('$found')),
          ],
        ),
        ImportProblem.notSynced => (
          'The file includes outputs newer than this $thisDevice has '
              'scanned. The import runs by itself once sync catches up. Keep '
              'the app open.',
          [
            ('Scanned to', _Fact('${_s.height}')),
            (
              'Node is at',
              _Fact(_s.nodeHeight == 0 ? '…' : '${_s.nodeHeight}'),
            ),
          ],
        ),
        ImportProblem.noNode => (
          'Importing asks your node which of these key images are spent, '
              "and it didn't answer. Try again, or change the node in "
              'Settings.',
          [('Node', _Fact(_s.node)), ('File', _Fact(file))],
        ),
        ImportProblem.failed => (
          'The wallet library refused the file. Export it again from the '
              'Monero GUI and try once more.',
          [
            ('File', _Fact(widget.file.name)),
            ('Size', _Fact(formatSize(_size))),
          ],
        ),
      };
      final (String? fix, _Next? next) = switch (problem) {
        ImportProblem.otherWallet ||
        ImportProblem.notKeyImages ||
        ImportProblem.failed => ('Choose another file', _Next.another),
        ImportProblem.noNode => ('Try again', _Next.again),
        ImportProblem.missingOutputs => ('Rescan from an earlier height', null),
        ImportProblem.notSynced => (null, null),
      };
      final red = switch (problem) {
        ImportProblem.otherWallet ||
        ImportProblem.notKeyImages ||
        ImportProblem.failed => true,
        _ => false,
      };
      return Screen(
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fix != null) ...[
              FilledButton(
                onPressed: next != null
                    ? () => _leave(next)
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AdvancedScreen(_s),
                        ),
                      ),
                child: Text(fix),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton(
              onPressed: () => _leave(null),
              style: context.secondaryButton,
              child: Text(
                problem == ImportProblem.notSynced ? 'Cancel import' : 'Cancel',
              ),
            ),
          ],
        ),
        children: [
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 28,
                color: red ? c.red : c.amber,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            problem.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(body, style: context.body.copyWith(height: 1.5)),
          const SizedBox(height: 18),
          FactsCard(facts),
          if (problem == ImportProblem.notSynced) _progress(),
        ],
      );
    },
  );

  /// How far the scan is towards the node, live.
  Widget _progress() {
    final c = context.colors;
    final s = _s;
    final target = s.nodeHeight > widget.waitFor
        ? s.nodeHeight
        : widget.waitFor;
    final String line;
    var problem = false;
    if (s.tor != null && !builtInTor.ready) {
      problem = builtInTor.error != null;
      line = problem
          ? "${builtInTor.error} Your node can't be reached without Tor."
          : 'Connecting to Tor… ${builtInTor.progress}%';
    } else if (!s.reachable) {
      problem = true;
      line = "Can't reach your node. The import waits until it answers.";
    } else if (s.nodeHeight == 0) {
      line = 'Connecting to your node…';
    } else if (s.height < s.wallet.restoreHeight) {
      line = 'Getting ready to scan';
    } else {
      line = 'Syncing · ${plural(s.blocksToGo, 'block')} to go';
    }
    // Counted from where the scan stood when this screen opened.
    final known =
        !problem &&
        s.nodeHeight > 0 &&
        s.height >= s.wallet.restoreHeight &&
        target > _startHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: known
                ? ((s.height - _startHeight) / (target - _startHeight)).clamp(
                    0.0,
                    1.0,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          line,
          style: problem
              ? context.caption.copyWith(color: c.red)
              : mono(size: 13, color: c.muted),
        ),
      ],
    );
  }
}

/// A value in the facts card, in mono like the numbers and addresses.
class _Fact extends StatelessWidget {
  const _Fact(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.right,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: mono(size: 13, color: context.colors.text),
  );
}
