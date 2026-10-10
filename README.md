# Monero-View-Wallet
iPhone app to view an accurate Monero balance by including key images to be able to view past outgoing transactions. 

Screen designs and the visual spec: [docs/design/DESIGN.md](docs/design/DESIGN.md).

## Running the test build (Windows)

The test build runs the app in a phone-width column. The first launch goes
through setup; every later launch opens Home straight away with the saved
wallet:

1. **Watch a wallet:** primary address, secret view key and restore height.
   The app tells the network from the address: a real (mainnet) wallet's
   starts with 4, a stagenet test wallet's with 5. It checks the key against
   the address. It refuses and wipes a seed phrase, and any key that is not
   that address's view key (which is what a spend key looks like).
   Subaddresses are refused: watch the primary address.
   On an iPhone, **Scan QR code** fills all three from the Monero GUI's View
   Only Wallet code (Settings → Wallet → Show seed & keys → Export wallet) or
   Feather's View-Only QR. From other wallets it reads the primary address
   and then the private view key, each from a code of its own; a key on its
   own is checked against the address and refused unless it is the view key.
   Any code that holds a spend key or seed is refused whole, as is the GUI's
   Spendable Wallet code. The camera reads the code on the phone and the
   picture is never saved.
2. **Choose a node:** your own (with a Test button), or one from a short list
   of public nodes on the wallet's network, to which **Add another node** adds
   your own picks; the app keeps them with the wallet. **Test speed** asks each
   listed node for its height and shows how fast it answered (a switch in
   Settings limits it to the node you picked). Nothing is
   contacted before you press Test, Test speed or Start sync. A node on the
   other network, or far from synced, is refused. **Connect over Tor**
   (experimental) reaches the node through the app's own Tor, and is always on
   for a `.onion` node; see [Tor](#tor).
3. **Scanning the blockchain:** progress of the first sync.
4. **Import key images:** choose the file the Monero GUI exported. On an
   iPhone, choose it in the Files picker, or open it with this app from Files,
   the share sheet or AirDrop; the app then shows the file and imports it when
   you tap Import this file. On an iPhone, **Use QR codes** works with a
   signing device that uses Monero's animated QR codes (Passport with Cake
   Signer, Feather's offline signing): the app shows the wallet's outputs as
   an animated code for the device to read, then reads the key images code it
   shows back and imports it. The outputs are encrypted with the view key, the
   key images code is held in memory only, and any code that might hold a
   spend key or seed is refused. The Monero GUI can't make these codes.
5. **Home:** the wallet's name (tap it to rename the wallet), balance,
   activity, whether the app is synced, catching up or can't reach the node,
   and a notice when outputs have no key image yet. Each payment says which
   subaddress it went to, or its label, once it has unlocked. Tap one to see
   the transaction: amount, date, fee (of a spend), confirmations, block,
   account and the transaction ID with a copy button.
6. **Receive** (arrow on Home): a subaddress nobody has paid yet, as a QR
   code made on the device, with Copy, New and a label that stays with the
   wallet. Share opens the phone's share sheet; the Windows build has Copy
   only.
7. **Settings** (gear on Home): the node and how fast it answers, whether
   Test speed asks every node (on by default), the restore height, Appearance
   (System, which follows the computer or phone, Light or Dark), Show USD
   value, Face ID to open (iPhone only, see [the lock](#the-lock)), Privacy
   policy, Open-source licenses and Remove wallet from this device. Show USD
   value is off by default; turned on, the app asks Kraken for the XMR price (the
   mainnet price, also shown for a stagenet wallet, whose coins are worth
   nothing) and the balance on Home switches between XMR and USD when tapped.
   Tapping the balance while it is off asks whether to turn it on, and turns
   it on only if you say yes. The app remembers the choice, so it asks Kraken
   again at each launch until you turn it off or remove the wallet.

On Windows a real wallet's spends are also recorded in the Monero GUI's own
ring database (see below). A public node sees your IP address, and learns which key images
belong to one wallet when you import them; your own node avoids both. With Show USD value
on, Kraken sees your IP address too, but nothing about the wallet.

### Tor

**Experimental.** Built-in Tor is new in this app and has had little testing:
runs against the real Tor network in the nightly Stagenet tests workflow, and
no review by anyone outside this project. Don't rely on it yet to hide your IP
address.

The Windows build ships the Tor Project's own `tor.exe` (tor 0.4.9.13, from
Tor Expert Bundle 15.0.24) next to the app. With Connect over Tor on, the app
runs it as a separate program and stops it when Tor is turned off or the app
closes.

An iPhone app can't run a separate program, so the iPhone build has the same
tor 0.4.9.13 built into the app as a library, from the
[Tor.framework](https://github.com/iCepa/Tor.framework) project (release
409.13.1, the build Onion Browser uses). It runs inside the app from the first
time Tor is turned on until the app is closed: Tor can only run once per
launch, so turning Tor off takes it off the network instead (no connections
in or out) and turning it on again puts it back. If it ever stops, the app
says to close and open it again. Not tried on a real iPhone yet: iOS takes
network connections away from an app in the background, and only a phone can
show how Tor recovers when the app comes back.

- Starting Tor takes from a few seconds to a minute or more, at each launch.
  Home shows "Connecting to Tor…" meanwhile. Syncing over Tor is slower.
- The node, including a `.onion` node, is reached only through Tor, which also
  looks up the node's name. The node sees a Tor address, not yours.
- With Show USD value on, the price request to Kraken goes through the same
  Tor.
- While Tor is starting, or if it can't start or connect, the node and Kraken
  can't be reached. The app never falls back to a direct connection.
- The choice is saved with the node, inside the encrypted wallet file.
- Tor listens for the app on port 19050 of this computer only, and gives each
  host (the node, Kraken, each node Test speed asks) a circuit of its own.
  Other programs on the computer could use that port too while the app runs.
  The app sends nothing there until its own Tor has connected and holds the
  port, so a program that took the port first gets nothing, and Tor fails to
  start instead. On iPhone Tor also takes commands on a free port it picks
  and writes down in its folder, only from someone who shows the cookie Tor
  writes next to it. No other app can read either file.
- With Tor on, Choose a node lists the onion nodes first. With any other node
  the last Tor relay sits between the app and the node and, as the app can't
  check most nodes' certificates, could read and change the traffic.
- Your internet provider can see that this computer uses Tor, though not what
  for. The app has no bridges, so it won't connect where Tor is blocked.
- What Tor does not change: a public node still learns which key images belong
  to one wallet when you import them.

### What the app keeps on the computer

Every build keeps the wallet between launches. The iPhone and Android are
described further down: [iPhone](#what-the-app-keeps-on-an-iphone),
[Android](#what-the-app-keeps-on-android).

The wallet files, the Appearance and Show USD value choices and Tor's own
folder are in `%LOCALAPPDATA%\MoneroViewWallet`. The password and the ring database are
elsewhere, as described below.

- **The wallet**, in the wallet library's own two files. `wallet.keys` holds
  the address and the view key. `wallet` holds what the scan found (outputs,
  imported key images, history), the subaddresses made on Receive with their
  labels, the wallet's name, the node, the public nodes you added to the
  list, when the node last answered, the time, file name and counts of the
  last key images import, and whether the iPhone build locks.
  The library encrypts both files with
  a key made from the wallet's password. On stagenet the library also writes
  the address to `wallet.address.txt` as plain text; the app deletes that file
  as soon as the wallet is created.
- **The wallet's password**, 32 random bytes the app makes itself, with the
  wallet's network (`mainnet` or `stagenet`) in front of it: the wallet
  library has to be told the network before it opens the files. Between
  launches both are kept only in Windows Credential Manager, as "Monero View
  Wallet: " followed by the wallet file's path, marked for this computer only.
  You never see or type it. Windows encrypts it with your Windows account's
  key, but any program running under that account can ask for it. On an
  iPhone the Keychain keeps it private to the app.
- **The Appearance choice**, as the word `system`, `light` or `dark` in the
  plain text file `appearance`.
- **The Show USD value choice**, as the word `on` or `off` in the plain text
  file `show_usd`. Remove wallet sets it back to `off`.
- **Tor's own folder**, `tor`, once Connect over Tor has been used: what Tor
  knows of the Tor network and the entry relays it picked, which it keeps so
  it uses the same ones each time. Nothing in it is about the wallet or the
  node. Remove wallet leaves it.
- **Monero's shared ring database**, `C:\ProgramData\.shared-ringdb` for a
  real wallet and its `stagenet` folder for a test wallet: the folders the
  Monero GUI uses too. The wallet library opens it every time it opens a
  saved wallet, and once key images are imported it records there the ring
  of each spend it sees, under the spend's key image. Both are encrypted with
  a key made from the wallet's keys, which for a view-only wallet means from
  the view key alone, so anyone with the view key and this computer could
  tell which transactions are the wallet's spends. Other Windows accounts on
  the computer can usually read the folder. The library offers no way to move
  it or switch it off, and a view-only wallet, which never spends, gains
  nothing from it. Remove wallet does not clear it. The owner allowed this
  on 2026-10-10.

The wallet is saved when a node is chosen, when the first scan finishes, after
a key images import, on leaving Receive, after renaming it, every two minutes while new blocks
are being scanned, and whenever Home loses focus, which on an iPhone comes
before the app goes to the background. So closing the app loses about two
minutes of scanning at most. **Remove wallet** deletes the password, then both wallet
files. A wallet whose setup stopped before "Start sync" is deleted at the next
launch, and setup starts over.

Not built yet: the rest of Settings.

Needs [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop)
3.47.6 and Visual Studio with the "Desktop development with C++" workload.

```sh
sh tool/fetch_monero_c.sh   # in Git Bash: downloads the wallet library, checks its SHA-256
sh tool/fetch_tor.sh        # the same for the Tor Project's tor.exe
flutter run -d windows
flutter test                # add $env:MVW_STAGENET_NODE = "host:port" to include a live first run and relaunch
```

Every pull request runs `flutter analyze` and the tests that need no network
on Linux (the App tests check). To run the same on Linux, for example in a
cloud session:

```sh
sh tool/fetch_monero_c.sh   # fetches the Linux library into the same folder
sh tool/fetch_tor.sh        # fetches the Linux tor into windows/tor
flutter analyze
LD_LIBRARY_PATH="$PWD/windows/monero_c" flutter test
```

The stagenet node tests run in the Stagenet tests workflow instead, against a
public stagenet node, every night and when started by hand (Actions > Stagenet
tests > Run workflow). It then checks that every public node the app offers,
mainnet and stagenet, still answers on its network, synced, over TLS or Tor.
The Windows build and the hour-long spend test run on the PC.

The tests save their throwaway wallets in a temporary folder and delete them.
On Windows each wallet's password goes into Credential Manager under a name of
its own and is deleted too. On Linux, which has no Credential Manager, the
tests hold it in memory instead. Like the app, the tests make the wallet
library open the shared ring database (`~/.shared-ringdb/stagenet` on Linux,
and `~/.shared-ringdb` for the one mainnet wallet they reopen, which on
Windows is the Monero GUI's `C:\ProgramData\.shared-ringdb`; that throwaway
wallet never spends, so nothing is recorded there).

The wallet library is [monero_c](https://github.com/MrCyjaneK/monero_c)
v0.18.4.6-RC2, the prebuilt release Cake Wallet also uses. Its version is
pinned in two places that must match: `pubspec.yaml` (Dart bindings) and
`tool/fetch_monero_c.sh` (native library).

## Building for iPhone

The app builds for iPhone, but can't go on a phone until it is signed with an
Apple developer account (then through TestFlight). Until then the iOS build
workflow (Actions > iOS build > Run workflow) builds it unsigned on a GitHub
Mac and runs a smoke test on the iOS simulator: the wallet library loads and
runs there, and the app shows its first screen. It runs by itself on pull
requests that are ready for review and after a push to main, when they change
the iOS project, the wallet library or the scripts that fetch it.

The smoke test also saves a throwaway wallet with its password in the
Keychain, opens it again and removes it, and asks the lock's Face ID and
passcode checks. The workflow then enrolls a face in the simulator, which the
lock must offer, sends the app to the background and checks that the app
switcher's snapshot of it is blank, and lists the names of the files the app
left in its folder.

The smoke test also checks that the app's code for key images files answers
and that it deletes, as it starts, copies of those files an earlier launch
left behind, and that the Tor inside the app starts and answers on its
control port as tor 0.4.9.13. It keeps Tor off the network, so the test
contacts nothing. The Files picker, "Open in…" and AirDrop themselves need a person
to tap through, so they wait for TestFlight to be tried on a phone.

The smoke test also checks that the camera's native code answers, and that it
can keep the screen on and let it sleep again. Scanning itself, the wallet's
QR code and the animated key images code alike, needs a real camera, so it
waits for TestFlight too.

What App Store Connect will ask when the app is submitted (encryption export,
App Privacy, privacy manifests, the wallet library's license) is in
[docs/app-store.md](docs/app-store.md).

### The lock

On iPhone the app opens locked whenever a wallet is saved, and locks again
when it comes back after a minute or more in the background. Face ID (or
Touch ID) starts by itself; **Use passcode** asks for the iPhone's passcode
instead. Both are Apple's own checks: the app only learns whether one passed.

- Settings → **Face ID to open** turns the lock off and on. It is on by
  default, and turning it off asks for Face ID or the passcode first. The
  choice is kept inside the encrypted wallet file.
- An iPhone with no passcode can't lock the app, and Settings says so.
- Whatever the lock is set to, the app covers itself whenever it isn't in
  front (the app switcher, Control Center, a call), so the app switcher's
  picture of it is blank.
- The lock hides the balance and history. It doesn't encrypt anything: the
  wallet's files are encrypted with a password the Keychain only gives out
  while the iPhone is unlocked.
- The Windows test build has no lock.

Face ID itself, a face on the Face ID sheet, isn't tried yet: the simulator
test only checks that the lock offers Face ID once a face is enrolled. That
waits for TestFlight and a real iPhone.

### What the app keeps on an iPhone

The same as on Windows, but in places no other app can read:

- **The wallet's two files and the Appearance and Show USD value choices**, in
  `Library/Application Support/MoneroViewWallet`. That folder is kept out of
  iCloud and computer backups: a backup of the files could never be opened,
  because the password never leaves the phone. The Face ID to open choice is
  kept inside the wallet's encrypted file.
- **The wallet's password** and its network, in the Keychain, as "Monero View
  Wallet: wallet" under the service "Monero View Wallet". Only this app can read it, only while
  the phone is unlocked, and only on this phone: it is not synced to iCloud
  Keychain and does not move to a new phone with a backup.
- **Tor's own folder**, `Library/Caches/tor`, once Connect over Tor has been
  used: the same as on Windows, plus the cookie that lets the app give Tor
  commands. iOS never backs up an app's caches, and may clear them when the
  phone runs low on space; Tor then fetches what it needs again.
- **Monero's ring database**, which the wallet library puts in
  `.shared-ringdb` at the top of the app's folder (in its `stagenet` folder
  for a stagenet wallet), also kept out of backups. If iOS doesn't let the app write there, the library goes without
  it, which a view-only wallet doesn't need.
- **A key images file you hand the app**, only until it is imported. Whether
  you choose it in the Files picker or open it with the app from Files, the
  share sheet or AirDrop, iOS gives the app its own copy (in `tmp` or
  `Documents/Inbox`). The app moves that copy to `tmp/KeyImages`, which is
  never backed up, and deletes it once the import is done, whether the wallet
  took the file or not, or when you leave Import key images without
  importing it. Without a wallet set up, it deletes the file at once. Copies
  left behind, for instance by the app being closed mid-import, are deleted
  at the next launch. The file you sent stays where it was, in Files or
  iCloud Drive; the GUI encrypted it with the wallet's view key.

The iPhone offers this app for any file in "Open in…" and the share sheet,
because the GUI's file has no extension of its own to recognise it by. The
app never becomes the one that opens files by default.

Remove wallet deletes the password, then both files, and empties the ring
database. Deleting the app deletes its folder, but iOS keeps Keychain items
after an app is deleted: the password stays behind, opening nothing, until the
app is installed and set up again.
Not tried on a real iPhone yet, only on the simulator (TestFlight comes with
the Apple developer account).

On a Mac with Apple silicon and Xcode:

```sh
sh tool/fetch_monero_c.sh   # packs the iPhone and simulator libraries as ios/MoneroWallet.xcframework
sh tool/fetch_tor.sh        # fetches Tor.framework's tor.xcframework into ios/
flutter run                 # on a simulator; or flutter build ios --simulator
```

## Building for Android

The app builds for Android 11 and later, so far only as a test build: it
isn't on Google Play, and it has no Tor, camera, key images file import or
lock yet. Those follow the iPhone's. The Android build workflow (Actions >
Android build) builds it on a GitHub Linux runner, signed only with a
throwaway debug key, and checks the result:

- The wallet library is in the app for 64-bit and 32-bit ARM phones and for
  the emulator, and the app's native libraries work on phones with 16 KB
  memory pages, as Google Play asks.
- The app asks for no permission but the internet, and Android may neither
  back it up nor move its files to a new phone.
- A smoke test on the emulator, on Android 11 and Android 15, both without
  Google's apps or services: the wallet library loads and runs, a throwaway
  wallet is saved with its password under the Keystore, opens again after the
  Keystore is read afresh, as at the next launch, and is removed, and the app
  shows its first screen.

It runs by itself on pull requests that are ready for review and after a push
to main, when they change the Android project, the app's code, the wallet
library or the scripts that fetch it.

With Flutter, the Android SDK and a JDK (17 or later):

```sh
sh tool/fetch_monero_c.sh android   # the Android libraries, into android/app/src/main/jniLibs
flutter run                         # on a phone or the emulator; or flutter build apk
```

Gradle checks each file it downloads against the checksums in
`android/gradle/verification-metadata.xml`. After Flutter or a build tool
changes, start the Android build workflow by hand with "Write the Gradle
checksums" on, check what it prints and commit it.

### What the app keeps on Android

The same as on the iPhone, in the app's own storage, which other apps can't
read:

- **The wallet's two files and the Appearance and Show USD value choices**, in
  `no_backup/MoneroViewWallet`: the app's folder that Android never backs up.
  The app also turns backups off altogether and leaves every file out of a
  transfer to a new phone. A copy of the files could never be opened anyway,
  because the password's key never leaves the phone.
- **The wallet's password** and its network, as "Monero View Wallet: wallet",
  in `no_backup/secrets`, encrypted (AES-GCM) with a key that the Android
  Keystore makes and keeps, on most phones in their secure hardware. The key
  can't be read out of the phone, backed up or moved to another phone.
- **Monero's ring database**, in `no_backup/.shared-ringdb` (in its
  `stagenet` folder for a stagenet wallet). The wallet library keeps it in
  the home folder, which the app sets to `no_backup` (`MainActivity.kt`).

Remove wallet deletes the password, then both files, and empties the ring
database. Deleting the app deletes all of it, the Keystore's key included.

## Security

Security and privacy come first in this project. The rules and the automatic
checks are described in [SECURITY.md](SECURITY.md). After cloning, run
`git config core.hooksPath .githooks` once to switch on the commit-time checks.

## License

Monero View Wallet is free software under the
[GNU General Public License version 3](LICENSE), with an
[additional permission](APP-STORE-PERMISSION.txt) for app stores: it, and
versions others make of it, may be offered through Apple's App Store, Google
Play or a similar store whose terms the GPL alone would not allow, as long as the
source of each version offered there is public under the same terms.
Contributions are accepted under the same license and permission
([CONTRIBUTING.md](CONTRIBUTING.md)). The parts that come from other projects
keep their own licenses: see [docs/third-party-code.md](docs/third-party-code.md).
