# Fonts

IBM Plex Sans (UI text) and IBM Plex Mono (amounts, addresses, heights, hosts),
the typefaces in [docs/design/DESIGN.md](../../docs/design/DESIGN.md). They are
bundled with the app, never fetched. Only the weights the app uses are here:
Sans 400, 500 and 600, Mono 400 and 500. Flutter picks the nearest of these for
any other weight.

License: SIL Open Font License 1.1, copyright IBM Corp., Reserved Font Name
"Plex". The license is in [../licenses/ibm-plex.txt](../licenses/ibm-plex.txt)
(the release's `LICENSE.txt`, with LF line endings), and the app shows it under
Settings → Open-source licenses. The OFL allows bundling the fonts with an app,
as long as the license goes with them and the fonts are not sold on their own.

The files are unchanged from IBM's own releases on GitHub, taken from
`fonts/complete/ttf/` in each zip on 2026-10-09:

| Release | Archive | SHA-256 of the archive |
| --- | --- | --- |
| [@ibm/plex-sans@1.1.0](https://github.com/IBM/plex/releases/download/%40ibm%2Fplex-sans%401.1.0/ibm-plex-sans.zip) | `ibm-plex-sans.zip` | `fb365d910566e6d199cc2c15579a7dd9a267128e18431a394ed81f1970c69200` |
| [@ibm/plex-mono@2.5.0](https://github.com/IBM/plex/releases/download/%40ibm%2Fplex-mono%402.5.0/ibm-plex-mono.zip) | `ibm-plex-mono.zip` | `6d23f01257663d8cc49a0d64c22ced630b79e0e2a0ac08a0da86e9a38bbc481c` |

As a cross-check, the zips' `woff2` files are byte for byte the ones in IBM's
npm packages of the same versions, whose checksums npm records and signs.

| File | SHA-256 |
| --- | --- |
| `IBMPlexSans-Regular.ttf` | `975dcda37d80f038dcd143c22e33ca2d97a0cc5a929aace1c749153b0fe1afa5` |
| `IBMPlexSans-Medium.ttf` | `331c8639d7598b2cde62a911a71db195e30cb655cd6bdf2e324a7e984955f907` |
| `IBMPlexSans-SemiBold.ttf` | `a20caf8286023a6a7a85e40b1d2a4ae9fc3e3b1f9eda8f4c542dd4986af67bb1` |
| `IBMPlexMono-Regular.ttf` | `7c6fbddca4b700be918f5f6183d9bd4464fa427fe435f0b480d77fe2bb8c5a43` |
| `IBMPlexMono-Medium.ttf` | `98fbd727aae340b236955879dabed4d991aac9e8e90b3b2a67ce4a59221cc97c` |

To check them: `sha256sum assets/fonts/*.ttf` (Git Bash or Linux), or
`shasum -a 256 assets/fonts/*.ttf` on a Mac.
