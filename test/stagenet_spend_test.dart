// End-to-end proof on stagenet that imported key images make a view-only
// wallet follow spends. It needs free test coins and about an hour (two
// 10-block unlock waits), so it only runs when both variables are set:
//
//   $env:MVW_STAGENET_NODE = "node.monerodevs.org:38089"
//   $env:MVW_STAGENET_FAUCET = "https://stagenet-faucet.xmr-tw.org/send_tx/"
//   flutter test test/stagenet_spend_test.dart
//
// Needs the native library: run `sh tool/fetch_monero_c.sh` first.
// Every wallet is a random throwaway held in memory. Only step names and block
// heights are printed: no keys, addresses, amounts or transaction ids.

// ignore_for_file: implementation_imports, avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero/src/monero.dart';
import 'package:monero_view_wallet/wallet.dart';

void main() {
  final node = Platform.environment['MVW_STAGENET_NODE'];
  final faucet = Platform.environment['MVW_STAGENET_FAUCET'];

  test(
    'a view-only wallet with key images follows spends',
    () async {
      // Windows looks for DLLs in the current directory.
      Directory.current = 'windows/monero_c';
      final manager = MoneroWalletManagerFactory().getWalletManager();
      final dir = Directory.systemTemp.createTempSync('mvw_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      Future<void> until(String what, bool Function() done) async {
        print('waiting: $what');
        while (!done()) {
          await Future<void>.delayed(const Duration(seconds: 10));
        }
      }

      // The wallet that can spend, standing in for the Monero GUI wallet.
      final full = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.stagenet.id,
      );
      final recipient = manager.createWallet(
        path: '',
        password: '',
        networkType: Network.stagenet.id,
      );
      expect(full.init(daemonAddress: node!), isTrue);
      full.startRefresh();
      await until('spending wallet synced', full.synchronized);
      final start = full.blockChainHeight();
      print('start height $start');

      int confirmedBalance() => full.balance(accountIndex: 0);
      int spendable() => full.unlockedBalance(accountIndex: 0);

      final response = await (await HttpClient().getUrl(
        Uri.parse(faucet!).replace(queryParameters: {'addr': full.address()}),
      )).close();
      await response.drain<void>();
      expect(response.statusCode, 200, reason: 'faucet request failed');
      await until('faucet coins unlocked (10 blocks)', () => spendable() > 0);

      final view = ViewWallet.create(
        address: full.address(),
        viewKey: full.secretViewKey(),
        restoreHeight: start - 10,
      );
      addTearDown(view.close);
      await view.connect(node);
      await until('view-only wallet synced', () => view.isSynced);
      expect(view.balance, confirmedBalance(), reason: 'incoming payment seen');
      expect(view.outputs.withoutKeyImage, greaterThan(0));

      Future<void> spendAThird() async {
        final before = confirmedBalance();
        final tx = full.createTransaction(
          dst_addr: recipient.address(),
          payment_id: '',
          amount: spendable() ~/ 3,
          mixin_count: 0,
          pendingTransactionPriority: 0,
          subaddr_account: 0,
        );
        expect(tx.status(), 0, reason: tx.errorString());
        expect(
          tx.commit(filename: '', overwrite: false),
          isTrue,
          reason: tx.errorString(),
        );
        final sentAt = full.blockChainHeight();
        // Two blocks later the spend is mined and both wallets have scanned it.
        await until(
          'spend confirmed',
          () =>
              full.blockChainHeight() >= sentAt + 2 &&
              view.height >= sentAt + 2 &&
              confirmedBalance() < before,
        );
      }

      await spendAThird();
      print('first spend at height ${full.blockChainHeight()}');
      // Without key images the view-only wallet can't see the spend, and counts
      // the change coming back on top of the coin that was spent.
      expect(view.balance, greaterThan(confirmedBalance()));

      final keyImages = '${dir.path}/key_images';
      expect(full.exportKeyImages(keyImages, all: true), isTrue);
      await view.importKeyImages(keyImages);
      expect(view.balance, confirmedBalance(), reason: 'balance after import');
      expect(view.transfers.where((t) => !t.incoming), hasLength(1));
      // The transaction screen shows the spend's ID and fee as the wallet that
      // sent it records them. Compared without printing either.
      final history = full.history()..refresh();
      final sentByFull = [
        for (var i = 0; i < history.count(); i++) history.transaction(i),
      ].singleWhere((tx) => tx.direction() == 1);
      final seen = view.transfers.singleWhere((t) => !t.incoming);
      expect(seen.hash == sentByFull.hash(), isTrue, reason: 'transaction ID');
      expect(seen.fee == sentByFull.fee(), isTrue, reason: 'fee');
      expect(seen.account, 0);

      // A later spend of an output whose key image was imported shows up from
      // scanning alone, with no new import.
      await until('change unlocked (10 blocks)', () => spendable() > 0);
      await spendAThird();
      print('second spend at height ${full.blockChainHeight()}');
      expect(view.transfers.where((t) => !t.incoming), hasLength(2));
      expect(
        view.balance,
        confirmedBalance(),
        reason: 'balance after 2nd spend',
      );
    },
    skip: node == null || faucet == null
        ? 'set MVW_STAGENET_NODE and MVW_STAGENET_FAUCET'
        : false,
    timeout: const Timeout(Duration(hours: 3)),
  );
}
