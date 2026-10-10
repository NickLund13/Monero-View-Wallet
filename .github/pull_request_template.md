**Before:**

**After:**

**How:**

## Security and privacy checklist

Tick each box or write why it does not apply. Rules are in SECURITY.md.

- [ ] **Secrets:** no real view key, spend key, seed, wallet file or key image export in code, tests, fixtures, logs, screenshots or this PR
- [ ] **Spend key / seed:** nothing asks for, accepts or stores one
- [ ] **Storage:** view key and key images only in Keychain / encrypted storage; nothing sensitive in UserDefaults, plain files, caches or backups
- [ ] **Network:** no calls except to the user's configured node and the opt-in USD price lookup, which stays within SECURITY.md rule 5; TLS and Tor/onion support not weakened
- [ ] **Logging:** no keys, addresses, amounts, transaction ids or node URLs logged
- [ ] **Tracking:** no analytics, crash reporting, ads or tracking SDKs
- [ ] **Privacy policy:** `docs/privacy-policy.md` still says what the app keeps and sends (a change to it is copied into `lib/privacy_policy.dart`)
- [ ] **Dependencies:** none added, or each one is necessary, well known, pinned to an exact version and justified below
- [ ] **Automatic checks:** Security checks, App tests and Claude review are green, and every review finding is fixed or answered

**What was checked:**
