# App design

The screens, colors, type and behavior the iPhone app should be built to.
The interactive mockups live on a private design canvas outside the
repository. This file is the source of truth for building; when the canvas and
this file disagree, update one so they match.

All numbers, addresses and hashes on the canvas are made-up sample data.

## Principles

- **View only.** The app never asks for, accepts or stores a seed or spend key
  (SECURITY.md rule 2). It says so on the Setup screen and nowhere implies it
  can send. A scanned QR code that carries a spend key or seed is refused
  whole.
- **Network:** the app talks to the user's chosen node, plus the opt-in price
  lookup below. Fonts and icons are bundled in the app, never fetched.
- **One main screen.** Home holds the balance and history. There is no tab bar;
  everything else is one tap from Home.
- **Honest balance.** Whenever the balance could be wrong or stale (unsynced,
  node unreachable, outputs without key images), Home says so in one line.

## Visual system

### Color

Two themes. Settings → Appearance offers System (default, follows iOS), Light
and Dark.

| Token | Dark | Light | Used for |
| --- | --- | --- | --- |
| `bg` | `#101113` | `#F4F4F1` | Screen background |
| `card` | `#1C1D21` | `#FFFFFF` | Cards, grouped rows, icon circles |
| `text` | `#ECECEE` | `#16171A` | Primary text |
| `sec` | `#B9BBC1` | `#43454C` | Body copy on cards, row labels |
| `muted` | `#A3A5AC` | `#5C5E66` | Captions, section headers, outgoing amounts |
| `border` | `#2A2B30` | `#E1E1E5` | Row dividers inside cards, input borders |
| `divider` | `#1F2024` | `#E4E4E8` | Dividers in the activity list |
| `track` | `#24252A` | `#E1E1E5` | Progress bar track |
| `btn2` | `#2A2B30` | `#ECECEF` | Secondary buttons, segmented control background |
| `input` | `#141518` | `#F4F4F1` | Text inputs inside cards |
| `ring` | `#5A5C63` | `#9A9CA3` | Unselected radio rings |
| `chev` | `#6B6D74` | `#9A9CA3` | Chevrons |
| `seg` | `#4A4B52` | `#FFFFFF` | Selected option of a segmented control (Appearance) |
| `accent` | `#F26822` | `#F26822` | Primary buttons, selected radios, progress fill |
| `accentText` | `#F26822` | `#AE4B18` | Orange text ("XMR", "Import") |
| `link` | `#F58A4B` | `#AE4B18` | Back links, text buttons |
| `green` | `#4CC38A` | `#1E7A4C` | Synced dot, incoming icon, success text, switches on |
| `amber` | `#F5B14B` | `#B26A00` | Warning icons, catching-up dot |
| `red` | `#FF7A6B` | `#C8372A` | Node unreachable, wrong-wallet icon, Remove wallet |
| `noteBg` | `#2A2216` | `#FFF0D9` | Key images notice background |
| `noteText` | `#F5C98B` | `#6B4300` | Key images notice text |

- Text on an `accent` button is always `#141414`.
- Light mode darkens orange text (accent × 0.72) so it meets 4.5:1 contrast on
  the pale background. Buttons keep the brighter orange.
- `test/theme_test.dart` checks that every text color meets 4.5:1 on the
  backgrounds it is used on, in both themes. Run it after changing a color.
- Incoming and outgoing differ by icon direction and text color, never by hue
  alone.

### Type

- **IBM Plex Sans** for UI text, **IBM Plex Mono** for amounts, addresses,
  block heights, hashes and node hosts. Both are SIL Open Font License and
  bundled with the app (`assets/fonts/`, whose README says which release and
  checksums), never fetched.
- Screen title 28 semibold; Home balance 40 mono medium with the currency in
  18 mono `accentText`; body 15; row text 15; captions 13; small print 12.
  Section headers are 13, uppercase, 0.04em letter spacing, `muted`.
- Support Dynamic Type: these are the default-size values.

### Layout

- Screen side padding 20; content starts below the status bar.
- Cards: radius 16, horizontal padding 16, rows at least 50 tall with
  `border` dividers.
- Primary button: full width, 52 tall, radius 14. Secondary: `card` or `btn2`
  background, 44 to 48 tall.
- Every tap target is at least 44 × 44.
- Icons: 2px stroke line icons (back chevron, gear, receive arrow, warning
  triangle, lock, copy, share, QR, file). Ship them as bundled assets.

### App icon and launch screen

- **Icon:** an orange (`accent`) eye with a catchlight on the dark `bg`, with a
  faint `card` glow behind it: "view only", in the app's own colors. It is not
  the Monero logo, so the icon doesn't lean on someone else's trademark. The
  source is `docs/design/icon/app_icon.svg` (full bleed, iOS rounds the
  corners); the iPhone sizes in `ios/Runner/Assets.xcassets/AppIcon.appiconset`
  are rendered from it at each pixel size, with no transparency, as the App
  Store requires. `windows_icon.svg` is the same as a rounded square for the
  Windows build's `app_icon.ico` (16 to 256 px).
- **Launch screen:** the eye alone (`launch_mark.svg`, 96 × 60 pt, its pupil
  see-through) centered on `bg`, light or dark as the iPhone is set (the
  `LaunchBackground` color in the asset catalog). It shows only until the
  app's first frame, which is the lock when a wallet is saved. It can't
  follow the app's own Appearance choice, only the phone's.
- Other options drawn on 2026-10-09: a dark eye on an orange tile, an orange
  coin with the eye in it, and the eye on the light `bg`.

## Navigation

```
First run:  Setup (type in, or Scan QR code → Scan wallet QR → Setup) → Choose a node
            → First sync → Import key images → Home
Later runs: Home with the saved wallet (First sync, if that had not finished)
Home:       Receive · Settings · Transaction (tap a row) · Import key images (notice)
Settings:   Node → Choose a node  |  Advanced  |  Remove wallet → Setup
Advanced:   Rescan → Home (First sync) → Import key images
Import:     From a file (→ Import problem when it fails)  |  By QR → Key images by QR
App open, or back after 1 minute in the background → Lock
```

## Screens

### 1. Setup ("Watch a wallet")

- At the top, a secondary button with the QR icon: "Scan QR code", with
  "Fills all three from the Monero GUI" below it → Scan wallet QR. Typing or
  pasting the fields still works, with or without a camera.
- Three fields: primary address (multi-line, mono), secret view key (secure
  field, mono), restore height (numeric). The address says the network: 4
  for a real (mainnet) wallet, 5 for a stagenet test wallet, which a caption
  under the field names. Subaddresses (8, or 7 on stagenet) are refused.
  Helper text says where each value is in the Monero GUI (Settings → Wallet → Show seed & keys, which shows all
  three; the restore height is also under Settings → Info).
- As soon as the address and view key are both filled, the app derives the
  public view key and checks it against the address. Match: green check and
  "Matches this address". Mismatch: red message, Continue disabled, and the
  view key field is cleared, because a key that is not this address's view
  key may be the spend key.
- Restore height note: "Use the GUI's height or an earlier one. A later height
  can miss payments."
- A card with a lock icon: "Never enter your 25-word seed or spend key. This
  app only watches; it can't send funds." A pasted 25-word phrase is rejected
  with that explanation.
- Primary button: Continue → Choose a node.
- A "Privacy policy" text button under the lock card → the privacy policy, so
  it can be read before the view key is typed.
- When a wallet is saved on the device but can't be opened (its password is
  gone from the secure storage, or a file is damaged), an amber note at the
  top says why setup is asking again: "The wallet saved on this device
  couldn't be opened. Set it up again to keep watching it."

### 1a. Scan wallet QR

Fills the Setup fields from a view-only wallet QR code, so nothing has to be
retyped. It also brings the GUI's own restore height, which is the height the
key image file's output order depends on. For wallets that show no such code,
it reads the primary address and then the private view key, each from a QR
code of its own.

- Reached only from Setup's "Scan QR code". The camera permission is asked on
  the first tap, never earlier. If it is denied: one line saying the camera
  is off for this app, an Open Settings link, and "Type it in instead".
- Steps card, at the top, "In the Monero GUI": 1 Settings → Wallet → Show
  seed & keys; 2 Enter your wallet password; 3 Under Export wallet, choose
  View Only Wallet. Below it, an amber warning row: "The GUI opens on the
  Spendable Wallet code. It holds your spend key, so this app refuses it."
- Camera view with corner guides, the same as step 2 of Key images by QR.
  Footer in small print: "Feather Wallet works too: Wallet → View-Only → Show
  QR." and "Other wallets: scan the primary address, then the private view
  key on its own."
- Below the camera: "Hold the View Only Wallet code inside the frame." and
  "The picture stays on this iPhone and is never saved."
- On a good scan the camera stops and the app returns to Setup with the three
  fields filled, the view key masked and the match check already showing. The
  Scan QR code row then reads "Filled from QR code" with a green check.
  Continue stays a tap, so the person can check the restore height first.
  An address or a view key on its own fills only its field; the row then
  reads "Address from QR code" or "View key from QR code", and "Filled from
  QR code" once both came from codes. Typing over a field takes its part
  away.

**Codes it accepts** (checked against the wallets' source code, 2026-10-09):

| Wallet | Where | What the QR holds |
| --- | --- | --- |
| Monero GUI | Settings → Wallet → Show seed & keys → Export wallet → View Only Wallet | `monero-wallet:<primary address>?view_key=<secret view key>&height=<restore height>` ([source](https://github.com/monero-project/monero-gui/blob/390e744af5c5d593575804ccfc3b06049014fb2f/pages/Keys.qml#L279-L280)) |
| Feather Wallet | Wallet → View-Only → Show QR | JSON: `{"version":0,"primaryAddress":…,"privateViewKey":…,"restoreHeight":…,"walletName":…}`; the wallet name is ignored ([source](https://github.com/feather-wallet/feather/blob/948773cf13c7486ee230eb67b6bac06b2f94c874/src/dialog/ViewOnlyDialog.cpp#L71-L80)) |
| Any wallet's receive code | Receive (it must show the primary address, not a subaddress) | The primary address alone, bare or as a `monero:` payment request with only the request's own fields (`tx_amount`, `tx_payment_id`, `recipient_name`, `tx_description`, which are ignored; [source](https://github.com/monero-project/monero/blob/24272e4a3b2e812cc2a569d95b177ecef4b91e46/src/wallet/wallet2.cpp#L15399-L15486)). Fills only the address. |
| Stack Wallet, and any wallet that shows a key on its own | Stack Wallet: Wallet → Settings → Wallet backup → keys → Selected key: Private View Key | The private view key alone, 64 hex characters. Fills only the view key, once Setup has the primary address to check it against. |

The GUI's Spendable Wallet code is the same URI with `&spend_key=<secret spend
key>` added, and it is the one selected when the page opens. (For a
view-only or hardware wallet the GUI shows only the view-only code.) Cake
Wallet reads both formats and also accepts `monero_wallet:` with an
underscore, so this app does too.

The other wallets on getmonero.org's downloads page show no view-only wallet
QR (their source checked 2026-10-10): Cake Wallet / Monero.com's only key QR
is `monero-wallet:?seed=…`, which always holds the seed; Stack Wallet shows
single keys as bare QR codes, the spend key among them (its key selector
opens on the public view key); Monerujo, Unstoppable and Edge show the view
key as text only. Feather changed its code
to match ANONERO's in 2023 ([commit](https://github.com/feather-wallet/feather/commit/a131bbc16599d3692aa7fe139b9faac69220f635)),
so ANONERO's may read too; its source and Monfluo's weren't reachable to
check. Any of them can still be typed in.

**Checks, in order, all on the phone.** A code is used only if it passes every
one; otherwise nothing from it is put in any field.

1. Anything that carries spend authority is refused whole: a parameter or
   JSON field (at any depth) whose name mentions a spend key, seed or
   mnemonic, in any case or spelling (`spend_key`, `Spend_Key`,
   `privateSpendKey`, `seed`, `mnemonic_seed`), or a run of 12 or more words
   in any script, also once `%20` and `+` are decoded (what a seed phrase
   looks like). Checked before any field is read, so not even the address is
   kept.
2. It must be one of the formats above, with nothing added: an extra or
   repeated parameter, or a JSON field Feather doesn't write, is refused too.
   Other codes (a payment request with other fields, an animated `ur:xmr-…`
   code, a web link) are refused.
3. The address must be a primary address for mainnet or stagenet, not an
   integrated address; a subaddress, and a testnet primary address
   (starting with 9 or A), get cards of their own. The view key must be 64
   hex characters and the height a whole number.
4. The same view key check as typed entry: the public view key derived from
   the scanned key must match the address, the code's own or, for a key on
   its own, the one already on Setup (without one, it is refused and nothing
   is kept). If it doesn't match, the key may be the spend key, which looks
   the same on its own, so it is refused like rule 1. If the check can't be
   made at all, the code is refused too. An address on its own has no key to
   check; Setup checks it against a typed key as usual.

**When a code is refused**, the camera pauses (guides turn grey) and a card
below it says why:

| Case | Title | Says | Buttons |
| --- | --- | --- | --- |
| Spend key or seed in the code | That code holds your spend key | Nothing from it was kept. In the GUI, choose View Only Wallet and scan that code. This app can't send, so it never takes a spend key. | Scan again |
| Not a view-only wallet code | Not a wallet code | Scan the View Only Wallet code under Export wallet in the Monero GUI, or Feather's View-Only QR. From another wallet, scan the primary address, then the private view key. | Scan again · Type it in instead |
| Wrong network | This is a test network wallet | The address is for testnet. This app watches mainnet and stagenet wallets. | Scan again |
| A subaddress | That's a subaddress | Scan the wallet's primary address, which starts with 4 (5 for a stagenet test wallet). Receive screens often show a subaddress. | Scan again · Type it in instead |
| A key on its own, and no address on Setup | This key needs its address | Nothing from the code was kept. Scan or type the wallet's primary address first, then scan its private view key. | Scan again · Type it in instead |
| Key doesn't match the address | This key isn't this address's view key | Nothing from the code was kept. Scan the View Only Wallet code again, or this address's private view key. | Scan again · Type it in instead |
| The key check couldn't be made | This code couldn't be checked | Nothing from it was kept. Scan it again, or type the wallet in. | Scan again · Type it in instead |

**Privacy.** The camera picture is read on the phone and never saved, sent
or logged, and the camera stops as soon as a code is accepted or refused. The
decoded text is held in memory only until the fields are filled; it is never
written to a file, the clipboard or a log. A view key that came from a QR
code is stored exactly like a typed one (Keychain only). The scanner decodes
on the phone with Apple's own AVFoundation (`AVCaptureMetadataOutput`, in
`ios/Runner/QrCamera.swift`), with no scanning library and not with Google ML
Kit, whose terms say it sends usage metrics to Google. The iOS camera
permission text: "Scans your view-only wallet and key image QR codes. The
picture stays on this iPhone."

The camera frame is near-black in both themes (`#050506` dark, `#1A1B1E`
light), with grey `#8A8C93` text while the camera is off ("Checking the
code…" while rule 4 runs, off the UI thread because it makes a throwaway
wallet; "Camera paused" after a refusal; "Camera off" when the permission is
denied).

**Built:** the checks (`lib/wallet_qr.dart`), this screen and Setup's Scan QR
code row (`lib/scan_screen.dart`), and the iPhone camera
(`ios/Runner/QrCamera.swift`): a platform view with a capture session of its
own, which stops at the first code it reads and is torn down as soon as the
screen takes the view away. Not yet tried with a real camera, which waits for
TestFlight. The Windows test build has no camera, so setup there stays
typed.

### 2. Choose a node

- Intro: the node sends blocks and sees the IP address, never the view key or
  balance.
- "My own node" card (default, tagged "Most private"): address and port field
  (LAN, Tailscale or .onion), a Test button, and a status line (reachable,
  height, latency).
- "Public nodes": a short radio list of the wallet's network (host in mono,
  operator below) and "Add another node", which opens a host:port field; an
  added node shows "Added by you" with a remove button, and is kept with the
  wallet. "Test speed" asks every listed node for its height, one after the
  other and over Tor when Tor is on (onion nodes only then), and puts the
  answer after the operator: "120 ms", "N blocks behind" (amber), "can't
  reach it" or "not a mainnet node, or far from synced" (red). The owner
  allowed this on 2026-10-10 as the second exception in SECURITY.md rule 5, with
  Settings → "Test speed asks every node" to turn it off: Test speed then
  asks only the node picked, and is greyed out until one is. Answers stay on
  their rows, so nodes can still be compared one by one. A note says what a public node learns that your own would not:
  when key images are imported, the node is asked which are spent and can
  link those spends to one wallet. The shipped list is in
  `lib/node_screen.dart`, checked again by each run of the Stagenet tests
  workflow.
- A node whose height doesn't fit the wallet's network (more than 500,000
  blocks from where that chain should be by the date) is refused by Test,
  Start sync and Save.
- "Tor (experimental)" card: a Connect over Tor switch. On, the app runs its
  own Tor, and the node is reached only through it and so is the price lookup.
  It is on and locked for a .onion node. The caption says it is new and little
  tested, that starting takes up to a minute and that syncing is slower; while
  Tor starts it shows "Connecting to Tor… N%". If Tor can't start, Test, Start
  sync and Save say so and nothing is contacted. A build without Tor (Android,
  for now) shows "This build has no Tor yet." and locks the switch.
  Home shows "Connecting to Tor… N%" at launch until Tor is connected.
- Primary button: Start sync (during setup) or Save (from Settings).
- The same screen is used in setup and from Settings.

### 3. First sync ("Scanning the blockchain")

- Large percentage, progress bar, "N of M blocks · from height H", and a
  rough time left.
- Card: received so far, outputs found, node with status dot.
- Note: spends appear after key images are imported; the app asks for them
  when the scan finishes.
- Footer: "Keep the app open for the fastest scan.", and under it a red text
  button, Remove wallet (same confirmation as in Settings): Settings can't be
  reached until the first scan is done, and a wrong restore height needs a
  way out.

### 4. Import key images

- Intro: key images let the phone see spends.
- Card "From the Monero GUI, as a file": the three steps (GUI Advanced mode:
  Send → Advanced options → Key images → Export; move it by AirDrop, iCloud
  Drive or email; choose it here or "Open in…" this app) and a Choose file
  button.
- Card "From a signing device, by QR" → Key images by QR. Names Passport with
  Cake Signer, Feather's offline signing, and other wallets using Monero's
  animated QR codes.
- "Last import" card: when, from where, key images imported, newly spent,
  outputs without one.

### 5. Key images by QR

- Two steps shown as pills: 1 Show outputs, 2 Scan key images.
- Step 1: an animated QR (UR type `xmr-output`) of the outputs this phone
  found, with "part N of M", and the screen kept awake. The signing device
  scans it.
- Step 2: camera view with corner guides; progress "N of M parts scanned"
  while reading the signer's animated `xmr-keyimage` QR. "Show outputs again"
  goes back.
- Footer: the Monero GUI can't make these codes; use the file import for it.
- monero_c already exposes `exportOutputsUR` and `importKeyImagesUR`.

**Built** (`lib/key_images_qr_screen.dart`), on iPhone only, where the card
shows. Step 1 waits for sync to catch up, then shows monero_c's
`exportOutputsUR` parts (130 bytes of message each, Cake Wallet's size) five
a second in a 296-point tile with low error correction, "part N of M · screen
stays on" and how many outputs it holds. By default it holds the outputs from
the first one without a key image, as wallet2 exports them for a device that
signed for this wallet before; an "All outputs" switch, shown only when the
two differ, holds every one, for a device that hasn't or says some are
missing. The screen stays on (`isIdleTimerDisabled`) while Key images by QR
is open, and may sleep while the app is locked.

Step 2 uses the setup camera in a mode that keeps reading and hands over each
new part. The app reads the parts itself (`lib/ur.dart`, a port of bc-ur's
decoder, fountain-coded parts included) to show "N of M parts scanned", then
hands the whole message to `importKeyImagesUR` as one code, so nothing is
written to a file. Each part is first checked like a setup code: one that
might carry a spend key or seed (a run of words, a field named for one, or a
UR type such as `crypto-seed`) is refused in red, anything but an
`xmr-keyimage` code, or a whole one that doesn't start "Monero key image
export", in amber ("Not a key images code"). A refusal pauses the camera;
Scan again keeps the parts read. The import then goes as for a file, through
Import problem (screen 6) worded for a code, whose "Scan again" starts the
reading over; Cancel goes back to Import key images. Last import's From says
"Signing device, by QR".

Tried with throwaway wallets (a full wallet standing in for the signing
device) and the simulator. A real signing device and a real camera wait for
TestFlight.

### 6. Import problem

One layout for every case: an icon in a circle (red when the file is wrong,
amber otherwise), a title, a plain explanation, a two-row facts card in mono,
and the fix as the main button with Cancel under it. The facts use only what
the app knows: the file can't say which height it needs, so "Finishing sync
first" shows the node's height instead.

| Case (what wallet2 says) | Title | Facts | Fix |
| --- | --- | --- | --- |
| File from another wallet (can't decrypt, or a different account) | This file is from another wallet | Wallet on this iPhone (first 6…last 6 of the address), file name and size | Choose another file |
| Not a key images file (wrong header or size) | This isn't a key images file | File name, size | Choose another file |
| Restore height too late (file mentions outputs this wallet never found) | Some outputs are missing | Restore height here, outputs not found ("k of n", n from the file size) | Rescan from an earlier height → Advanced |
| Not synced far enough (still scanning, or catching up) | Finishing sync first | Scanned to, node is at; live progress bar and sync line | Imports by itself when the sync catches up; Cancel import |
| The node didn't answer the spent check | Your node didn't answer | Node, file | Try again |
| Anything else | The key images weren't imported | File name, size | Choose another file |

- "Finishing sync first" opens before the import when the app is still
  scanning, catching up, rescanning or can't reach the node. It also opens
  when an import reports missing outputs while the phone is behind its node
  (the file may list a payment in a block the phone hasn't scanned yet), so
  the app waits once before saying "Some outputs are missing".
- While it waits it shows the Tor or node status ("Connecting to your
  node…", "Syncing · N blocks to go"); leaving it with Cancel import keeps
  nothing.
- The app's copy of the file is deleted however the screen ends, as on
  Import key images.

### 7. Home

- Header: wallet name, "View only · can't send", Receive and Settings
  buttons. The name is the person's own: tapping it asks for a new one
  ("Monero wallet" until then, and again if cleared), kept inside the
  encrypted wallet file.
- Balance: tap to switch between XMR and USD (USD only when the price lookup
  is on). XMR shows 4 decimals with "N unlocked · N locking (N blocks)"; USD
  shows "$N unlocked · at $N per XMR". With the lookup on, a "Balance ⇄ tap
  for USD" caption sits above the amount. If the latest price request failed,
  the line adds "as of HH:MM" (the time of the price shown); with no price
  yet it says "Getting the XMR price…" or "Can't reach Kraken for the XMR
  price." Switching to USD after a failure asks again at once.
- Sync line, one of:
  - Synced: green dot, "Synced to block N · N min ago".
  - Catching up: amber dot, "Catching up · N blocks to go" and a thin
    progress bar. Right after launch, until the node has answered, the text
    is "Connecting to your node…" over the saved balance.
  - Node unreachable: red dot and text, "Can't reach your node. Balance as of
    HH:MM." and a Change node link. The last known balance stays visible. A
    balance saved on an earlier day shows its date too: "8 Oct 2026, 09:05".
- Key images notice when outputs arrived after the last import: one amber row,
  "N new outputs since your key images", an Import link, and a dismiss (×).
  Dismissing hides it until another new output arrives. Otherwise a quiet row,
  "Key images imported <date>", links to Import key images.
- Activity list: direction icon, "Received"/"Sent", a sub line (pending
  confirmations, date, subaddress, or "found via key images"), and the amount
  in mono (incoming in `text`, outgoing in `muted`). A payment that has
  unlocked shows where it went after the date: its Receive label, or
  "subaddress #N", or "primary address"; until then the line only counts
  confirmations. Tapping a row opens Transaction.

### 8. Receive

- Shows a fresh, unused subaddress (not the primary address): "Subaddress
  #N · New, not used yet" with a New button for another one. Opening the
  screen again shows the same one until a payment to it arrives; then it says
  "Paid already" and the next visit makes a new one.
- New stops 50 past the highest subaddress paid so far ("No more new ones for
  now"). The Monero GUI watches 199 past it (wallet2's default lookahead of
  200 includes it), but moves that window on only once a payment confirms,
  and checks a whole batch of blocks against the window it had when the
  batch began. The margin keeps payments to several new subaddresses at once
  (in one block, or while the GUI was closed) inside it; at 200 the GUI could
  miss one.
- QR of the address (made on the phone, dark on white in both themes), the
  full address in mono, Copy (shows "Copied") and Share (the phone's share
  sheet; the Windows test build has Copy only).
- Optional label, stored only on the phone, with the wallet.
- Note: give each payer a new subaddress so payments can't be linked; the GUI
  wallet sees payments to it too, just not the label. The GUI numbers
  subaddresses the same way, so skip any number already given out from it.

### 9. Transaction

- Direction icon, "Sent"/"Received", amount in 36 mono, date and time.
- Card: fee, confirmations, block, account, transaction ID (mono, with a
  copy button). The fee shows for spends only: the sender paid the fee of a
  payment received, which instead shows the address it went to
  ("Subaddress #N · label"). Confirmations count up while the screen is
  open; below 10 they read "N of 10", and a payment still in the pool shows
  "None yet" and "Not in a block yet".
- For spends: "Found through imported key images. A view-only wallet can't
  see who you paid, only what left this wallet."

### 10. Settings

- Node: current node, status, latency (asked once when Settings opens) →
  Choose a node. Below it the "Test speed asks every node" switch, on by
  default, kept in the encrypted wallet file.
- Wallet: restore height; Advanced, with "Rescan, subaddress lookahead
  (50 × 200)" under it → Advanced.
- Advanced:
  - Rescan from an earlier height: says which block this phone started from
    and points to the Monero GUI's restore height (Settings → Info). The
    field starts at the current restore height and takes that or an earlier
    one. Rescan asks first ("The balance and history start again from block
    N. The app forgets the key images imported so far… Subaddresses and
    their labels stay."), then goes back to Home, which shows First sync and
    then asks for the key images, as on the first run. It needs the node;
    without it nothing changes. The new height is kept in the encrypted
    wallet file and shows as the restore height.
  - Subaddress lookahead: accounts × addresses, the Monero GUI's 50 × 200 by
    default; at least 1 of each and no more than 100000 in all. Raising it
    finds payments to addresses handed out further ahead, after a rescan.
    Kept in the encrypted wallet file.
- Display: Appearance (System / Light / Dark segmented control); Show USD
  value switch, off by default, with "Off by default. Gets the XMR price from
  Kraken, over Tor when the node is reached over Tor. Without Tor, Kraken sees
  your IP address. It never sees anything about your wallet." below it.
- Security: Face ID to open, "Locks when the app opens and after 1 minute in
  the background". On by default. The name follows the phone (Touch ID to
  open, Passcode to open). Turning it off asks for Face ID or the passcode
  first; turning it on asks nothing. The choice is kept inside the encrypted
  wallet file, not as plain text. On an iPhone with no passcode the switch is
  off and locked, with "Needs a passcode on this iPhone. Set one in its
  Settings."; the Windows test build shows it the same way with "iPhone only.
  This test build doesn't lock."
- About: Privacy policy → the app's privacy policy, docs/privacy-policy.md
  built into the app (`lib/privacy_policy.dart`): headings, paragraphs and
  bullets in the body style, selectable so its web address can be copied.
  Open-source licenses → Flutter's license list, with the app's own
  copyright and license at the top and under Monero View Wallet, and the
  wallet library's parts, Tor's and the fonts' added (`lib/licenses.dart`,
  [third-party-code.md](../third-party-code.md)).
- Remove wallet from this iPhone (red text button, with a confirmation).

### 11. Lock

- Lock icon, "Wallet locked", one line of explanation.
- Unlock with Face ID (primary) and Use passcode (text button).
- The app switcher snapshot shows a blank screen, never the balance.

**When it locks** (built 2026-10-09): with a wallet saved and Face ID to open
on, the app opens locked, before its first frame, and locks again when it
comes back after 1 minute or more in the background (a clock set back while
away counts as a long time). Leaving for less, the Face ID sheet, Control
Center, notifications or a call don't lock it. The lock goes up as the app
comes back, before it is in front, so Home never shows first.

**Unlocking.** Face ID starts by itself once each time the lock screen comes
up; the button tries again. The Face ID sheet has no "Enter Password" button:
Use passcode on the screen is the fallback, and asks for the iPhone's passcode
through iOS (which may try Face ID once more first: iOS has no passcode-only
check). With no Face ID or Touch ID set up, or Face ID turned off for this
app, the one button reads "Unlock with passcode". Touch ID phones read
"Unlock with Touch ID". Both checks are Apple's LocalAuthentication; the app
only learns whether one passed. When a check fails, a red line under the
explanation says what to do:

| Case | Line |
| --- | --- |
| Face ID didn't match | Face ID didn't recognise you. Try again, or use your passcode. |
| Too many tries | Face ID is off after too many tries. Use your passcode. |
| Face ID not available | Face ID isn't available. Use your passcode. |
| Passcode check failed | That didn't unlock it. Try again. |
| Cancelled | (nothing) |

An iPhone with no passcode can't lock the app. If the passcode is taken off
while the app is locked, the next tap opens it: only the owner can take it
off, and nothing is left to check with.

**The blank snapshot.** Whenever the app stops being active, the Runner puts a
plain view in the `bg` color over it, and takes it away when the app is active
again. This holds on every screen, Setup included, whether the lock is on or
not.

**What it is not.** The lock hides the balance and history; it doesn't
encrypt anything. The wallet's files are encrypted with a password the
Keychain only gives out while the iPhone is unlocked. The Windows test build
has no lock.

## USD price lookup (recorded decision)

The owner chose on 2026-10-08 to show USD through an opt-in price lookup. This is
the one exception to node-only network traffic, and SECURITY.md rule 5 sets
its limits.

- Off by default. Turned on by "Show USD value" in Settings, or from Home:
  the owner asked on 2026-10-09 to switch to USD by tapping the balance without
  going to Settings. While the lookup is off, a tap on the balance asks
  "Show the USD value?", saying the app will ask Kraken for the price (over
  Tor when the node is reached over Tor, otherwise that Kraken sees the IP
  address) and where to turn it off. Only "Show USD" turns it on, the same
  as the switch; "Not now" makes no request. The choice is
  remembered between launches, as the word "on" or "off" stored like the
  Appearance choice, so a saved "on" asks for the price again at launch.
  Removing the wallet, or a launch that finds no wallet, sets it back to off:
  Settings can't be reached without a wallet to turn it off.
- One source: Kraken's public ticker,
  `https://api.kraken.com/0/public/Ticker?pair=XMRUSD` (the last trade price).
  It needs no account or API key, and it is the same URL the Monero GUI asks
  for its own price display (its default source). Kraken sees the IP address and the time, never the balance or
  addresses. Kraken has stopped selling XMR in some regions (the EEA,
  Canada), but its public XMR/USD ticker still answered on 2026-10-09. If the
  pair ever goes away, the GUI's other source, CoinPaprika, is the one to
  consider next.
- The request is one GET over TLS with the certificate checked, no cookies,
  no wallet data, and redirects refused, so no other host is contacted. It is
  asked when the switch is turned on and then every 10 minutes while it stays
  on. `lib/price.dart` holds it.
- Goes over Tor when Tor is on, which is whenever the node is reached over
  Tor: `priceClient` in `lib/price.dart` then connects through the same Tor
  proxy (`lib/tor.dart`), which also looks up Kraken's name. The request is
  unchanged, TLS is still checked against Kraken's name, and there is no
  direct connection to fall back to.
- With it off, tapping the balance only asks, and no price request is made.
  Turning it off forgets the price.

## Open items

- Tor on a real iPhone. The iPhone build runs the same tor 0.4.9.13 inside
  the app (built 2026-10-09; the README's Tor section says how it behaves):
  - The library: Tor.framework's `tor.xcframework` (github.com/iCepa/
    Tor.framework, release 409.13.1, the build Onion Browser uses), static
    libraries of tor, OpenSSL, libevent and liblzma. `tool/fetch_tor.sh`
    fetches it and checks the SHA-256 that Tor.framework's podspec checks.
    The Xcode project links it into the app with `libz`.
  - Chosen over Foundation Devices' `tor` Flutter package, which wraps arti
    (Tor in Rust) through flutter_rust_bridge: that needs a Rust toolchain in
    the iOS build and more packages, and it is a different Tor from the one
    the Windows build runs.
  - Starting it: `ios/Runner/InAppTor.swift` calls Tor's C API (`tor_api.h`:
    `tor_main_configuration_new`, `tor_main_configuration_set_command_line`,
    `tor_run_main`) on a thread of its own, with the command line from
    `inAppTorArguments` in `lib/tor.dart`. Tor starts off the network.
  - Progress and stopping: `lib/tor.dart` signs in to Tor's control port
    (127.0.0.1:19051) with the cookie Tor writes into its folder, turns the
    network on, and asks `GETINFO status/bootstrap-phase` each second. Tor's
    API warns against running it twice in one process, so stopping is
    `SETCONF DisableNetwork=1`, which closes the SOCKS port and every
    connection, and starting again turns the network back on.
  - Tried only on the simulator, where it starts and answers on its control
    port. What a real iPhone has to show: iOS takes an app's sockets away
    while it is suspended, so Tor may need its listeners reopened, or a
    restart, when the app comes back.
- Built-in Tor is marked experimental. Before that label comes off: bridges
  for networks that block Tor, a way to see why Tor failed, and more than the
  one nightly test against the real Tor network.
- The app's source is public since 2026-10-10 (GPL-3.0 with an App Store
  permission), the simplest way to meet the wallet library's LGPL-3.0.
  Whether App Store terms and the LGPL fit together at all is still disputed;
  see [app-store.md](../app-store.md#the-wallet-librarys-lgpl).
- Key images by QR: try it with a real signing device (Passport with Cake
  Signer, Feather's offline signing) and the iPhone's camera once TestFlight
  is set up. An Android version needs its own camera code; mobile_scanner uses
  Google ML Kit there, which the privacy rules rule out.
- Confirm by hand that the GUI shows a payment to a subaddress made on the
  phone. The addresses match the GUI's (tested), and New stays inside its
  lookahead.
