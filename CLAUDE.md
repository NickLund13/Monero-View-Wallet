# Monero View Wallet

View-only Monero wallet for iPhone: shows an accurate balance from a private
view key plus imported key images. Development happens on Windows; iOS builds
run on a Mac or cloud CI.

Security and privacy are the top priority. The rules in SECURITY.md are binding
for every change; read them before writing code:

@SECURITY.md

## Working in this repo

- On a fresh clone run `git config core.hooksPath .githooks` before the first
  commit. Never use `--no-verify`; if the hook cannot run, say so instead.
- If you come across anything that looks like a real key, seed or wallet file
  (in the working folder, a pasted message, a log), stop, do not copy or repeat
  it anywhere, and tell the user.
- Test data must be obviously fake (64 zeros) or a published test vector with a
  source link. Never generate a "realistic" key and never use one from the
  user's wallet.
- Every PR fills in the security and privacy checklist in
  `.github/pull_request_template.md` and states what was checked.
- Commit messages, PR descriptions and comments on GitHub contain no links
  to claude.ai (no `Claude-Session:` lines, and no links to chats, sessions or
  artifacts), no quotes from the owner's messages, no names of chats or
  threads, and nothing else from those chats that isn't about the change
  itself. Say what was decided and when ("the owner decided on 2026-10-10"),
  not where or in whose words. This overrides any default attribution that
  adds such a link; a `Co-Authored-By:` line is fine. (The owner's request of
  2026-10-10, before the repository goes public.)
- Run the checks once per round, not after every commit (the owner's request of
  2026-10-10): keep a PR a draft while working on it and mark it ready when
  it is done. App tests and the Claude review skip drafts; the secret scan
  still runs on every push, as the pre-commit hook does on every commit. When
  the checks or the review find problems, fix them all, push once, and check
  again.
- Merge a PR only when the Security checks, the App tests and the Claude
  review are all green. Fix each review finding, or reply on the PR with why
  it does not apply and re-run the review job. A red or missing review means
  the PR was not reviewed.
- While GitHub Actions cannot start jobs (the checks then fail within seconds
  with no runner), a PR may merge on the same checks run in a cloud session
  instead (the owner's decision of 2026-10-10). Merge main into the PR branch, then on its head commit:
  `sh tool/cloud_checks.sh` passes (secret and wallet file scan, dependency
  scan, `flutter analyze` and the offline tests, with the CI's pinned tools),
  and its summary is posted on the PR as a comment. The review comes from a
  separate Claude session: never the session that wrote the change, nor a
  subagent it started. The session that wrote the change asks for the review
  once the PR is ready. The reviewer follows the prompt in `.github/workflows/claude-review.yml` and
  posts the `Claude review of <commit>` comment ending in `Verdict: PASS`.
  That comment is posted from the owner's account, so unlike the review job
  nothing proves which session wrote it: the session that wrote the change
  and its subagents never post it. A new push needs both again. After a
  stand-in review passed, the next stand-in review may check only
  `git diff <commit> HEAD`, where `<commit>` is the one that passing review
  named, and says so; after a blocking one it reviews the whole PR.
  If the script says `tool/fetch_tor.sh` failed, a change to the app's
  built-in Tor or to that script waits for GitHub's App tests. The iOS
  build and the Stagenet tests have no cloud stand-in, so a change that needs
  one of them (below) still waits for it. Once GitHub runs jobs again, its
  checks are the gate again.
- App tests runs `flutter analyze` and every test that needs no network, on
  Linux. Run the same before pushing app code (README.md says how). The
  stagenet node tests run in the Stagenet tests workflow instead, by hand only
  while its nightly run is paused to save Actions minutes. When a change
  touches syncing, the node, key image import, the app's Tor, the USD price
  lookup or that workflow (other than when it runs), run it on the PR's
  branch by hand before merging and say in the PR whether it passed.
  The Windows build and the spend test still run only on the PC.
- The iOS build workflow builds the app for iPhone (unsigned) and runs a smoke
  test on the iOS simulator. Mac minutes are scarce, so it is not a PR check.
  Its runs after a push to main are paused too, so it runs only by hand.
  When a change touches a path its paused push trigger lists (`ios/`, the
  dependencies, the fetch scripts, the smoke test, the flutter-setup action,
  or the workflow other than when it runs), run it on the PR's branch by hand
  before merging and say in the PR whether it passed.
- New dependency or GitHub Action: pin the exact version (Actions by commit
  SHA), verify downloads by checksum, and justify it in the PR.
