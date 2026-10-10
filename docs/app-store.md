# App Store notes

What App Store Connect will ask when the app is submitted, and what the app
already has in place. Written on 2026-10-09; Apple's forms change wording
over time, so answer the substance. None of this is legal advice.

Still to do before submitting: the real bundle id (now the
`com.example.moneroViewWallet` placeholder), signing, a public web address
for the privacy policy (see [App Privacy](#app-privacy)), and the app's source
public on GitHub (see [The wallet library's LGPL](#the-wallet-librarys-lgpl)).

## Export compliance (encryption)

`ios/Runner/Info.plist` sets `ITSAppUsesNonExemptEncryption` to NO, so App
Store Connect doesn't ask about encryption for every build. That answer holds
**as long as the app isn't offered in France**.

Why, in plain words:

- Any app that uploads to the App Store "exports" its encryption from the
  US. Encryption that only comes from iOS needs nothing. This app brings its
  own as well: the TLS connections to the node and to Kraken (BoringSSL,
  inside Flutter), Tor (with OpenSSL), and the wallet library, which decrypts
  the wallet's files and the GUI's key images file (ChaCha20).
- All of it is standard, published cryptography, nothing secret or home-made.
  Under the US rules that makes the app a "mass market" item, which since
  March 2021 needs no classification request (CCATS) and no yearly
  self-classification report
  ([86 FR 16482](https://www.federalregister.gov/documents/2021/03/29/2021-05481/export-administration-regulations-implementation-of-wassenaar-arrangement-2019-plenary-decisions)).
- Apple's table then asks for one document only: a French encryption
  declaration, and only for apps on the French App Store
  ([Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)).
  France requires it for encryption that does more than authenticate.
- Orbot, Onion Browser, Signal and Stack Wallet (Monero and Tor) also set the
  key to NO.

If App Store Connect asks anyway: "What type of encryption algorithms does
your app implement?" → **Standard encryption algorithms instead of, or in
addition to, using or accessing the encryption within Apple's operating
system**; "Is your app going to be available on the App Store in France?" →
**No**.

So, in App Store Connect under Pricing and Availability, leave France out.
Also leave out Russia and Belarus unless checked first: US export rules add
licence requirements there (EAR 746.8). To offer the app in France later: file the
declaration with ANSSI (it took about a month in reports), upload it in App
Store Connect, then set the key to YES with the
`ITSEncryptionExportComplianceCode` Apple gives back.

Where it is less certain: Monero's own algorithms are published but not
adopted by a standards body. A view-only wallet doesn't sign anything, and
what it decrypts with (ChaCha20, Keccak, Ed25519 maths) is standard, so this
note treats the app as standard. For certainty, BIS classifies an item for
free on request (about 30 days).

## App Privacy

The "App Privacy" answer is **"No, we do not collect data from this app"**,
shown on the App Store as "Data Not Collected". Apple: "'Collect' refers to
transmitting data off the device in a way that allows you and/or your
third-party partners to access it for a period longer than what is necessary
to service the transmitted request in real time"
([Apple](https://developer.apple.com/app-store/app-privacy-details/)). The app
sends nothing to its developer. The node is one the user picks, Test speed
only asks public nodes for their block height, Kraken only answers a price
request, none of them gets wallet data, and no code of theirs is in the app.
The camera (Scan wallet QR at setup) is read on the phone by Apple's own
AVFoundation and the picture is never saved or sent, so it collects nothing
either; the App Review note can say so if asked why the app uses the camera.

The privacy policy is [privacy-policy.md](privacy-policy.md), written from
what the code does. Apple asks for a link to it in App Store Connect and for it
in the app, easy to find (App Review Guideline 5.1.1(i)). The app shows the
same text, built into the app so reading it contacts nothing, under Settings →
About → Privacy policy and from a link on Setup; a test checks the two copies
match. Still to do: put the file on a public web page and give App Store
Connect that address. Keep the policy in step with the app: a change to what
the app keeps or sends changes the policy in the same pull request (the PR
checklist asks).

## Privacy manifests

Apple asks apps to give a reason for some APIs ("required reason APIs") and
refuses uploads that miss one (ITMS-91053). Each executable needs a manifest
in its own bundle:

| Bundle | Manifest | Reasons declared |
| --- | --- | --- |
| The app (Swift code and the Tor built into it) | `ios/Runner/PrivacyInfo.xcprivacy` | File timestamps `C617.1`, system boot time `35F9.1` |
| MoneroWallet.framework (the wallet library) | written by `tool/fetch_monero_c.sh` | the same, plus disk space `E174.1` (LMDB checks for room before the ring database grows) |
| Flutter.framework | Flutter's own | |

Every manifest says the app tracks nobody and collects nothing. The iOS build
workflow checks each binary in the app against its manifest
(`tool/check_privacy_manifests.sh`), so a library update that starts calling
another such API fails the build instead of the upload.

## The wallet library's LGPL

monero_c, the wrapper the app uses to reach Monero's wallet code, and two
parts inside it (polyseed and the Trezor message definitions) are under the
LGPL-3.0 ([third-party-code.md](third-party-code.md)). The app shows their
license and says where their source is, which the LGPL asks for. The LGPL
also asks that someone who gets the app can run it with a changed version of
those parts. Here that is hard to offer as things stand: the library is a
separate framework inside the app, but iOS won't run an app whose framework
was swapped without signing it again, and monero_c's Dart bindings are
compiled into the app's own code. Whether App Store terms and the LGPL fit
together at all is also disputed.

The simplest way to meet it is to publish this app's source under an open
license when it goes on the App Store, as Cake Wallet (MIT, and it uses the
same monero_c) and Stack Wallet (GPL-3.0) do: anyone can then rebuild the app
with a changed library. Nothing here matters while the app only goes to your
own phone through TestFlight.

Decided on 2026-10-10: the app's own code is published on GitHub under the
GPL-3.0 ([LICENSE](../LICENSE)) with an additional permission for app stores
([APP-STORE-PERMISSION.txt](../APP-STORE-PERMISSION.txt)). The Free Software
Foundation holds that the GPL alone clashes with App Store terms (limits on
devices and copying, signing that stops changed versions from running), which
got VLC pulled from the App Store in 2011, so every contributor would have to
agree before a version with their code could go there. The permission allows
it for this app and for versions others make of it, as long as the source of
each version offered there is public under the same terms, and contributions
come in under it (CONTRIBUTING.md). The app shows its copyright and license at
the top of Settings → Open-source licenses, as the GPL asks of an app with a
screen. The repository has to be public, with the source of the version
submitted, before the app goes on the App Store.

## Name and icon

- The name under the icon is "Monero View" (`CFBundleDisplayName`): the home
  screen cuts longer names off. The App Store name is set separately in App
  Store Connect.
- The icon is in `ios/Runner/Assets.xcassets/AppIcon.appiconset`, with the
  1024 px App Store size and no transparency, as Apple requires. The source and
  the other options are in `docs/design/icon/` and DESIGN.md.
