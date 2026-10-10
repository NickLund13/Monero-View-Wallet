import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'lock.dart';
import 'node_screen.dart';
import 'pick_file.dart';
import 'privacy_policy.dart';
import 'scan_screen.dart';
import 'session.dart';
import 'ui.dart';
import 'wallet.dart';
import 'wallet_qr.dart';

const _neverEnterSeed =
    'Never enter your 25-word seed or spend key. '
    "This app only watches; it can't send funds.";

final _whitespace = RegExp(r'\s');

/// What a secret view key looks like: 64 hex characters.
final _viewKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// Null if [input] can be a view key, otherwise why it was refused. Anything
/// with spaces is treated as a seed phrase and never handed to the wallet.
String? viewKeyProblem(String input) {
  if (_viewKeyPattern.hasMatch(input)) return null;
  if (input.contains(_whitespace)) {
    return 'That looks like a seed phrase. $_neverEnterSeed';
  }
  return 'The secret view key is 64 characters, 0-9 and a-f.';
}

/// What a primary address looks like: 95 base58 characters.
final _addressPattern = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{95}$');

/// Null if [input] can be a primary address, otherwise why it was refused. A
/// seed phrase or key pasted into the wrong field never reaches the wallet.
String? addressProblem(String input) {
  if (input.contains(_whitespace) || _viewKeyPattern.hasMatch(input)) {
    return 'That looks like a seed phrase or a private key, not an address. '
        '$_neverEnterSeed';
  }
  if (!_addressPattern.hasMatch(input)) {
    return 'The primary address is 95 characters and starts with 4.';
  }
  // Subaddresses start with 8 on mainnet and 7 on stagenet.
  if (input.startsWith('8') || input.startsWith('7')) {
    return "That's a subaddress. Use the wallet's primary address, which "
        'starts with 4 (5 for a stagenet test wallet).';
  }
  final network = networkOf(input);
  if (network == null) {
    return "That isn't a primary address. It starts with 4 (5 for a "
        'stagenet test wallet).';
  }
  return null;
}

/// Screen 1 of the design: "Watch a wallet".
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.lostSaved = false});

  /// True when a wallet is saved on this device but could not be opened, so
  /// the screen says why it is asking again.
  final bool lostSaved;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _address = TextEditingController();
  final _viewKey = TextEditingController();
  final _restoreHeight = TextEditingController();

  String? _addressError;
  String? _viewKeyError;

  /// Whether the view key belongs to the address; null until both are filled.
  bool? _matches;

  /// True while the address and view key are the ones a scanned wallet QR
  /// code filled in.
  bool _fromQr = false;

  @override
  void initState() {
    super.initState();
    receivedKeyImagesFile.addListener(_turnAwayKeyImages);
    // The file that started the app can come before this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _turnAwayKeyImages());
  }

  /// A key images file opened with the app before there is a wallet to import
  /// it into is deleted at once.
  void _turnAwayKeyImages() {
    if (!mounted) return;
    final file = takeKeyImagesFile();
    if (file == null) return;
    file.discard();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Set up the wallet first. Then open the key images file with this '
          'app again.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    receivedKeyImagesFile.removeListener(_turnAwayKeyImages);
    _address.dispose();
    _viewKey.dispose();
    _restoreHeight.dispose();
    super.dispose();
  }

  int? get _height => int.tryParse(_restoreHeight.text);

  bool get _stagenet {
    final address = _address.text.trim();
    return address.isNotEmpty &&
        addressProblem(address) == null &&
        networkOf(address) == Network.stagenet;
  }

  void _check() {
    var address = _address.text.trim();
    var viewKey = _viewKey.text.trim();
    _addressError = address.isEmpty ? null : addressProblem(address);
    _viewKeyError = viewKey.isEmpty ? null : viewKeyProblem(viewKey);
    // A seed phrase or a private key in the wrong field is wiped at once
    // rather than left on screen.
    if (address.contains(_whitespace) || _viewKeyPattern.hasMatch(address)) {
      _address.clear();
      address = '';
    }
    // Longer than a view key: a seed phrase whose line breaks the field ate.
    if (viewKey.contains(_whitespace) || viewKey.length > 64) {
      _viewKey.clear();
      viewKey = '';
    }
    _matches = null;
    if (address.isNotEmpty &&
        viewKey.isNotEmpty &&
        _addressError == null &&
        _viewKeyError == null) {
      final problem = ViewWallet.keysProblem(
        address: address,
        viewKey: viewKey,
      );
      if (problem == 'failed to parse address') {
        _addressError =
            "That isn't a valid address. Check it was copied in full.";
      } else {
        _matches = problem == null;
        // A key that isn't this address's view key may be the spend key:
        // don't leave it in the field.
        if (problem != null) _viewKey.clear();
      }
    }
    setState(() {});
  }

  Future<void> _continue() async {
    final ViewWallet wallet;
    try {
      wallet = ViewWallet.create(
        address: _address.text.trim(),
        viewKey: _viewKey.text.trim(),
        restoreHeight: _height!,
        save: true,
      );
    } on WalletException catch (e) {
      setState(() => _viewKeyError = e.message);
      return;
    }
    // From here the key exists only inside the wallet library's memory and in
    // the wallet's encrypted keys file.
    _viewKey.clear();
    setState(() {
      _matches = null;
      _fromQr = false;
    });

    final navigator = Navigator.of(context);
    var started = false;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => NodeScreen(
          network: wallet.network,
          action: 'Start sync',
          onChosen: (node, tor, added) async {
            await wallet.connect(node, tor: tor, added: added);
            started = true;
            final session = WalletSession(wallet)..startPolling();
            // From now on, coming back after a minute away locks the app.
            appLock.on = session.lockOn;
            navigator.pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => HomeScreen(session)),
              (_) => false,
            );
          },
        ),
      ),
    );
    // Back from the node screen: forget the wallet and delete its file, the
    // key has to be entered again.
    if (!started) await wallet.forget();
  }

  /// Scan wallet QR, which comes back with a code that passed every check, or
  /// with nothing.
  Future<void> _scan(QrCamera camera) async {
    final wallet = await Navigator.push<WalletQr>(
      context,
      MaterialPageRoute(builder: (_) => ScanWalletScreen(camera: camera)),
    );
    if (wallet == null || !mounted) return;
    _address.text = wallet.address;
    _viewKey.text = wallet.viewKey;
    _restoreHeight.text = '${wallet.restoreHeight}';
    _check();
    setState(() => _fromQr = _matches == true);
  }

  /// A typed change to the address or view key: they are no longer the
  /// scanned ones.
  void _typed(String _) {
    _fromQr = false;
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final camera = qrCamera;
    return Screen(
      title: 'Watch a wallet',
      bottom: FilledButton(
        onPressed: _matches == true && _height != null ? _continue : null,
        child: const Text('Continue'),
      ),
      children: [
        if (widget.lostSaved)
          const Note(
            "The wallet saved on this device couldn't be opened. Set it up "
            'again to keep watching it.',
          ),
        Text(
          camera == null
              ? 'Copy three values from the Monero GUI on your computer.'
              : 'Scan the view-only wallet QR from the Monero GUI, or paste '
                    'three values from Settings → Wallet → Show seed & keys.',
          style: context.body,
        ),
        const SizedBox(height: 16),
        if (camera != null)
          _ScanRow(fromQr: _fromQr, onTap: () => _scan(camera)),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Primary address', 'Settings → Wallet'),
              TextField(
                key: const Key('address'),
                controller: _address,
                onChanged: _typed,
                minLines: 2,
                maxLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                style: mono(size: 13),
              ),
              if (_addressError != null) _Problem(_addressError!),
              if (_stagenet)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'A stagenet test wallet, whose coins are worth nothing.',
                    style: context.caption,
                  ),
                ),
              const SizedBox(height: 16),
              const _Label('Secret view key', 'Settings → Wallet'),
              TextField(
                key: const Key('viewKey'),
                controller: _viewKey,
                onChanged: _typed,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: mono(size: 13),
              ),
              if (_viewKeyError != null) _Problem(_viewKeyError!),
              if (_matches == true)
                _Result(
                  Icons.check_circle_outline,
                  c.green,
                  'Matches this address',
                ),
              if (_matches == false)
                _Result(
                  Icons.error_outline,
                  c.red,
                  "That key doesn't belong to this address, so it was "
                  'cleared. Copy the secret view key, never the spend key.',
                ),
              const SizedBox(height: 16),
              const _Label('Restore height', 'Settings → Info'),
              TextField(
                key: const Key('restoreHeight'),
                controller: _restoreHeight,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: mono(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Use the GUI's height or an earlier one. "
                  'A later height can miss payments.',
                  style: context.caption,
                ),
              ),
            ],
          ),
        ),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: c.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(_neverEnterSeed, style: context.body)),
            ],
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => showPrivacyPolicy(context),
            child: const Text('Privacy policy'),
          ),
        ),
      ],
    );
  }
}

/// Setup's way to Scan wallet QR, which says once the fields came from a
/// code.
class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.fromQr, required this.onTap});

  final bool fromQr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.btn2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.qr_code_2, size: 20, color: c.accentText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan QR code',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (fromQr)
                        Row(
                          children: [
                            Icon(Icons.check, size: 14, color: c.green),
                            const SizedBox(width: 4),
                            Text(
                              'Filled from QR code',
                              style: context.caption.copyWith(color: c.green),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Fills all three from the Monero GUI',
                          style: context.caption,
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

class _Label extends StatelessWidget {
  const _Label(this.name, this.where);

  final String name;
  final String where;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(name, style: context.body)),
        Text(where, style: context.caption),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: context.caption.copyWith(color: context.colors.red),
    ),
  );
}

class _Result extends StatelessWidget {
  const _Result(this.icon, this.color, this.text);

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: context.caption.copyWith(color: color)),
        ),
      ],
    ),
  );
}
