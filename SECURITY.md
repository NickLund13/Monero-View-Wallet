# Security and privacy

This is a view-only Monero wallet. It can never spend funds, but the data it
holds (private view key, key images, addresses, balances, transaction history)
reveals a person's finances. Security and privacy come before features.

## Rules

1. **No real wallet secrets in the repo, ever.** No private view key, spend
   key, seed phrase, wallet file or key image export in code, tests, fixtures,
   logs, screenshots, commit messages, issues or PRs. Use obviously fake values
   (for example 64 zeros) or published test vectors with a link to the source.
2. **The app never asks for, accepts or stores a spend key or seed.**
3. **The view key and key images live only in the iOS Keychain or encrypted
   storage.** Never in UserDefaults, plain files, caches, backups or logs.
4. **No analytics, crash reporting, ads or tracking SDKs.**
5. **The only network traffic is to the Monero node the user configured,
   plus the two exceptions below: the opt-in USD price lookup and Test
   speed.** Prefer TLS and support Tor/onion
   nodes where possible. Make no other calls (no other price feeds, update
   checks or fonts fetched from a CDN) unless the repository owner decides to
   allow one and the exception is added to this rule in the same PR.

   **The first exception, the USD price lookup** (the owner's decision of
   2026-10-08, see
   [DESIGN.md](docs/design/DESIGN.md#usd-price-lookup-recorded-decision)):
   - Off by default. Only the user turns it on: with "Show USD value" in
     Settings, or by tapping the balance on Home and saying yes to the
     question that names the price source (the owner's decision of
     2026-10-09). While it is off, no price request is made.
   - Asks one price source for the XMR price in USD, over TLS, and sends no
     wallet data: no address, key, key image, balance, amount or transaction
     id.
   - Goes over Tor when Tor is on.

   **The second exception, Test speed** (the owner's decision of 2026-10-10):
   - Only when the user presses Test speed on Choose a node. It then asks
     each public node in the app's list, and each one the user added to it,
     for its block height: one request each, with no wallet data.
   - Goes over Tor when Tor is on. An onion node is asked only over Tor.
   - Settings → "Test speed asks every node" turns it off. Test speed then
     asks only the node the user picked.

   **Tor** (the owner's decision of 2026-10-09 to build Tor into the app):
   with "Connect over Tor" on, the app runs the Tor Project's own Tor (on
   iPhone, the same tor built into the app as a library by the Tor.framework
   project), which connects to the Tor network's relays and directory servers
   to carry the traffic above. It is off by default and only the user turns
   it on. With it on, the node, the nodes Test speed asks and the price
   source are reached only through Tor, never directly instead.
6. **Never log secrets or financial data**: keys, addresses, amounts,
   transaction ids or node URLs.
7. **Dependencies only when necessary**, from well-known sources, pinned to an
   exact version (GitHub Actions pinned to a commit SHA), with the reason
   written in the PR.

## Automatic checks

| Check | Where it runs | What it stops |
| --- | --- | --- |
| Ignored-file check | pre-commit hook, CI | Anything matching `.gitignore` (wallet `.keys` files, `.env`, signing keys) being force-added |
| Monero export check | pre-commit hook, CI | Key image or output export files, recognised by their file header whatever they are named |
| gitleaks | pre-commit hook, CI | API keys, tokens, private keys, plus Monero rules in `.gitleaks.toml` for private keys and seed phrases |
| osv-scanner | CI, and weekly | Dependencies with known vulnerabilities |
| PR checklist | every pull request | Storage, network, logging and dependency mistakes a scanner cannot see |
| Claude review | every pull request, again after each push | Rule violations and bugs a scanner cannot see. Red if Claude finds a blocking problem, and red if no review was posted |

The hook and CI run the same script, `.githooks/pre-commit`.

## One-time setup per clone

```sh
git config core.hooksPath .githooks
```

The hook needs [gitleaks](https://github.com/gitleaks/gitleaks) 8.30.1 on the
PATH and blocks commits until it is installed.
Windows: `winget install Gitleaks.Gitleaks --version 8.30.1`.
macOS: `brew install gitleaks`.

Never commit with `--no-verify`.

## One-time setup per repository

Claude review needs a repository secret named `CLAUDE_CODE_OAUTH_TOKEN`. Run
`claude setup-token`, then add the token on GitHub under Settings → Secrets and
variables → Actions. Never paste the token into chat, code or an issue. Each
review sends the pull request's diff to Anthropic and counts against that
Claude subscription.

## When a check fails

- **A real secret was caught before commit:** remove it and commit again.
- **A real secret was already committed or pushed:** treat it as leaked. Move
  the funds to a new wallet if it was a seed or spend key; for a view key,
  assume that wallet's history is exposed. Then remove it from git history.
  Deleting the file in a new commit is not enough.
- **Claude review is red:** fix each finding and push; the review runs again.
  If a finding is wrong, reply on the pull request saying why and re-run the
  review job. Do not merge on a red or missing review. (When the review job
  can't run, because GitHub Actions cannot start jobs or the job's token isn't
  set yet, CLAUDE.md lets a review by a separate Claude session stand in for
  it.)
- **False positive:** prefer changing the value to an obviously fake one. If it
  is a published test vector, add the finding's fingerprint to
  `.gitleaksignore` with a comment linking the public source.

## Reporting a vulnerability

Do not open a public issue or pull request. Report it privately with **Report
a vulnerability** on the repository's Security tab, which only the owner
sees.
