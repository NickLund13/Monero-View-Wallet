# Monero View privacy policy

Last updated: 10 October 2026

Monero View is a view-only Monero wallet for iPhone. It shows a wallet's balance and history from the wallet's address and secret view key, and the key images you export from the Monero GUI or a signing device. This policy says what the app keeps, what it sends and to whom, and how to delete it.

## In short

- The app collects no data. It has no account, analytics, crash reporting, ads or tracking, and sends nothing to its developer. The developer has no server and never sees your wallet, your keys or how you use the app.
- Your wallet stays on your iPhone, encrypted, and out of iCloud and computer backups.
- The app connects to the Monero node you choose. The node sees your IP address unless you use Tor, and if you import key images, it can tell which spends come from one wallet.
- Anything else happens only when you ask for it: Test speed asks public nodes for their block height, Show USD value asks Kraken for the XMR price, and Connect over Tor runs Tor.

## What the app keeps on your iPhone

All of it stays in the app's own storage on the iPhone, which other apps can't read.

- **Your wallet:** its address and secret view key, and what the app finds on the blockchain for it: payments received, imported key images, spends, the balance and the history. With it are the subaddresses made on Receive and their labels, the wallet's name, its restore height and subaddress lookahead, the node you chose and the public nodes you added, whether you use Tor, when the node last answered, the time, file name (or that it came by QR code) and counts of the last key images import, and your Face ID to open and Test speed settings. All of this is in the wallet's two files, which are encrypted with a password the app makes at random.
- **That password,** in the iPhone's Keychain. Only this app can read it, only while the iPhone is unlocked, and only on this iPhone: it is not synced to iCloud Keychain and does not move to another phone with a backup. You never see or type it.
- **Two display choices,** Appearance (System, Light or Dark) and Show USD value (on or off), each kept as one word in a plain file. They say nothing about the wallet.
- **Monero's ring database.** Once you import key images, the wallet library records there the ring of each spend it sees, encrypted with a key made from the view key.
- **Tor's own files,** once you have used Connect over Tor: what Tor knows about the Tor network and the entry relays it picked. Nothing about the wallet or the node.
- **A key images file you hand the app,** only until it is imported. The app deletes its copy once the import is done, or when you leave Import key images without importing. A copy left behind, for instance if the app closed during an import, is deleted the next time the app starts. The file you sent stays where it was.

The wallet's files, the display choices and the ring database are kept out of iCloud and computer backups. A backup of the wallet could never be opened anyway, because the password never leaves the iPhone. iOS never backs up Tor's files or the copy of a key images file. The USD price is held in memory only.

Face ID and the iPhone's passcode are checked by iOS. The app only learns whether the check passed, never your face or your passcode.

Scan QR code, at setup, and Key images by QR use the iPhone's camera once you allow it. The picture is read on the iPhone to find the code and is never saved or sent, and the camera turns off as soon as a code is read, or for an animated key images code once all of it is read. A code that holds a spend key or seed is refused and nothing from it is kept. The address, view key or restore height a good code holds go into the setup fields, as if you had typed them. A key images code is held in memory, never in a file, until it is imported like a key images file.

Key images by QR also shows the wallet's outputs on screen, as an animated QR code for your signing device to read, and keeps the screen on while it is open. The wallet library encrypts the outputs with the view key, so only a device with the view key can read them. Someone who photographs the code can tell from its length roughly how many outputs it holds, and nothing else. The code is never saved or sent.

## What the app sends, and to whom

The app connects to nothing except what this section lists. It never sends your secret view key anywhere, and sends nothing to the developer.

### The Monero node you choose

To show your balance, the app downloads the blockchain from one Monero node: your own, or a public node from the app's list or one you added to it. The app finds your payments on the iPhone, so the node isn't told which are yours. No node is contacted until you press Test, Test speed or Start sync. After that, the app stays in touch with the node while it is open, and Settings asks the node once how fast it answers each time you open it.

The node sees:

- your IP address, or a Tor address with Tor on, and when the app is open;
- which blocks the app downloads, which shows from which block your wallet's history starts;
- when you import key images, the key images you import, from a file or a QR code, because the app asks the node which of them are spent. The node can then tell that they all belong to one wallet and, through them, which transactions spent from it, and link that to your IP address. Tor hides your IP address but not that link. Your own node keeps all of this to yourself.

The node never gets your view key, your address, your balance or your labels.

The connection to the node is encrypted when the node offers it, as the public nodes in the app's list do. But the app doesn't check the node's certificate, because most nodes make their own, so someone who can get in between could read what the app asks the node, encrypted or not, and change what the node answers, which could make the app show a wrong balance or history: for instance whoever runs your Wi-Fi or, with Tor on, the last Tor relay before a node that isn't an onion node. An onion node, which Tor encrypts the whole way, or your own node on your own network avoids that.

The public nodes in the app's list are run by the people or projects it names, not by the developer. What a node logs is up to whoever runs it.

### Test speed

Test speed on Choose a node runs only when you press it. It then asks each public node in the list, including the ones you added, for its block height: one request each, with no wallet data. Each node sees your IP address, or a Tor address with Tor on. An onion node is asked only over Tor. With Settings → "Test speed asks every node" turned off, Test speed asks only the node you picked. Test, under My own node, asks only that node.

### The USD price, if you turn it on

Show USD value is off by default. It turns on only if you turn it on in Settings, or tap the balance on Home and say yes. While it is on, the app asks Kraken (api.kraken.com) for the XMR price in US dollars: as soon as it is turned on, each time the app starts, every 10 minutes while the app is open, and at once when you switch the balance to USD while there is no price yet or the last request failed. The request carries no wallet data: no address, key, key image, balance, amount or transaction ID. Kraken sees your IP address, or a Tor address with Tor on, and the time. Kraken's own privacy notice covers what Kraken does with that: https://www.kraken.com/legal/privacy. Turning Show USD value off stops the requests.

### Tor, if you turn it on

Connect over Tor is off by default, and always on for an onion node. With it on, the app runs the Tor Project's own Tor inside the app. Tor connects to the Tor network's relays and directory servers, and the node, Test speed and the price request then go only through Tor, never directly. Your internet provider can see that you use Tor but not what for. Tor in this app is new and marked experimental, so don't rely on it yet to hide your IP address.

### What you copy or share

Copy puts an address or transaction ID on the iPhone's clipboard, and Share hands an address to the app you pick in the share sheet. From there it is out of this app's hands.

If you paste the address or the secret view key at setup, the app empties the clipboard once the wallet is set up, or once it has cleared a field that held something that doesn't belong there, such as a seed.

## What the developer receives

Nothing. The app contains no code from anyone that collects data: no analytics, crash reporting, advertising or tracking. The developer has no data about you, so shares none with anyone.

Apple runs the App Store, Face ID, the Keychain, the share sheet and iCloud under its own privacy policy. If Share With App Developers is on in Settings → Privacy & Security → Analytics & Improvements, Apple may give app developers crash data and statistics about how their apps are used, in a form that does not identify you. The app adds nothing to that, and you can turn it off there.

## Deleting your data

- **Remove wallet from this device,** in Settings, deletes the wallet's password and then its files, empties the ring database, and turns Show USD value off. It leaves the Appearance choice and Tor's files.
- **Deleting the app** deletes everything it kept in its storage. iOS keeps Keychain items after an app is deleted, so the wallet's password stays in the Keychain, opening nothing, until the app is installed and set up again, which replaces it.
- **The optional connections:** the price requests stop when you turn Show USD value off, and with Settings → "Test speed asks every node" off, Test speed asks only the node you picked. Using your own node keeps your key images to yourself.
- **The developer** holds no data about you, so there is nothing to ask the developer to delete.

## The Windows test build

This policy is about the iPhone app. A Windows build exists only for testing and is not distributed. It connects to the same places in the same way, with these differences: it keeps the wallet's files in the Windows user's AppData folder, and the password in Windows Credential Manager, where other programs running as the same Windows user can read it. It also uses the ring database the Monero GUI shares, in the .shared-ringdb folder in C:\ProgramData, which other accounts on the computer can usually read and which Remove wallet doesn't clear.

## Changes to this policy

If the app starts to keep or send anything new, this policy changes in the same app update, and the date at the top changes with it.

## Contact

For questions about this policy, use the support link on the app's App Store page.
