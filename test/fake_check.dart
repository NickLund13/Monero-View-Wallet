import 'package:monero_view_wallet/lock.dart';

/// Stands in for Face ID, Touch ID and the passcode. Gives the [answers] in
/// order, then cancels, and records each check: true for the passcode.
class FakeCheck implements OwnerCheck {
  FakeCheck(this.unlock);

  /// What the device unlocks with. A test can change it.
  Unlock unlock;
  final answers = <CheckResult>[];
  final asked = <bool>[];

  /// The iPhone's side doesn't answer, so both calls throw.
  bool broken = false;

  @override
  Future<Unlock> kind() async {
    if (broken) throw Exception('made-up failure');
    return unlock;
  }

  @override
  Future<CheckResult> ask({
    required String reason,
    required bool passcode,
  }) async {
    if (broken) throw Exception('made-up failure');
    asked.add(passcode);
    return answers.isEmpty ? CheckResult.cancelled : answers.removeAt(0);
  }
}
