# Third-party code in the app

What the app ships besides its own code, and the license of each part. The
app's own code is under the GPL-3.0 with an App Store permission (`LICENSE`
and `APP-STORE-PERMISSION.txt`, shown in the app as `monero-view.txt` and
`gpl-3.0.txt`). The license texts are in `assets/licenses/`, and the app shows
them under Settings → Open-source licenses (`lib/licenses.dart`), each build
only its own. Flutter lists its engine and every Dart package there by itself.

Found on 2026-10-09 by reading the pinned binaries themselves (the symbols,
version strings and debug info of the iPhone and Windows wallet library, the
member list of Tor.framework's static library, the version strings of the
Windows `tor.exe` and the notices in its bundle's `docs/` folder), and the
build files of monero_c and Tor.framework at the pinned versions. If a pinned
version in `tool/fetch_monero_c.sh` or `tool/fetch_tor.sh` changes, check this
list again.

Each text is the upstream license file at that version, unchanged. Where a part
also carries notices in its source files, they follow the license after a
dashed line that says where they come from.

## The wallet library (monero_c v0.18.4.6-RC2)

In the iPhone build (MoneroWallet.framework) and the Windows build (the DLL).

| File | Part | Version | License | Text from |
| --- | --- | --- | --- | --- |
| `monero.txt` | Monero (wallet2 and what it needs) | 0.18.4.6, with monero_c's patches | BSD-3-Clause, plus notices in its source | [LICENSE](https://raw.githubusercontent.com/monero-project/monero/v0.18.4.6/LICENSE) |
| `epee.txt` | epee (in Monero) | as in Monero 0.18.4.6 | BSD-3-Clause | [contrib/epee/LICENSE.txt](https://raw.githubusercontent.com/monero-project/monero/v0.18.4.6/contrib/epee/LICENSE.txt) |
| `lmdb.txt` | LMDB (in Monero, for the ring database) | 0.9.70 | OpenLDAP 2.8 and ISC | [COPYRIGHT and LICENSE](https://raw.githubusercontent.com/monero-project/monero/v0.18.4.6/external/db_drivers/liblmdb/LICENSE) |
| `easylogging.txt` | Easylogging++ (in Monero) | 9.96.7 | MIT | [LICENSE](https://raw.githubusercontent.com/abumq/easyloggingpp/v9.96.7/LICENSE) |
| `randomx.txt` | RandomX (MrCyjaneK's fork) | 5dfeeb30 | BSD-3-Clause | [LICENSE](https://raw.githubusercontent.com/MrCyjaneK/RandomX/5dfeeb30ec3446ec9d348153767abc324436c56c/LICENSE) |
| `rapidjson.txt` | RapidJSON | 1.1.0 | MIT | [license.txt](https://raw.githubusercontent.com/Tencent/rapidjson/129d19ba7f496df5e33658527a7158c79b99c21c/license.txt) |
| `monero_c.txt` | monero_c, and the Dart bindings the app uses (`monero` in pubspec.yaml) | 3bfb3856 | LGPL-3.0, plus BSD-2-Clause for its pbkdf2.c | [LICENSE](https://raw.githubusercontent.com/MrCyjaneK/monero_c/3bfb3856a838f2bf6b729501837bb0295dedf25d/LICENSE) |
| `polyseed.txt` | polyseed | bd79f501 | LGPL-3.0 | [LICENSE](https://raw.githubusercontent.com/tevador/polyseed/bd79f5014c331273357277ed8a3d756fb61b9fa1/LICENSE) |
| `trezor-common.txt` | Trezor message definitions (compiled into Monero's Trezor support) | bff7fdfe | LGPL-3.0 | [COPYING](https://raw.githubusercontent.com/trezor/trezor-common/bff7fdfe436c727982cc553bdfb29a9021b423b0/COPYING) |
| `gpl-3.0.txt` | The GPL-3.0 text, which LGPL-3.0 builds on, and the app's own license | | | [COPYING3](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-15.2.0/COPYING3) |
| `lgpl-source.txt` | Where the source of the three LGPL parts is (written for this app) | | | |
| `utf8proc.txt` | utf8proc | 2.9.0 | MIT and the Unicode data license | [LICENSE.md](https://raw.githubusercontent.com/JuliaStrings/utf8proc/3de4596fbe28956855df2ecb3c11c0bbc3535838/LICENSE.md) |
| `bc-ur.txt` | bc-ur (MrCyjaneK's fork, for animated QR codes), and the app's own reader of those codes (`lib/ur.dart`), ported from its decoder | d82e7c75 | BSD-2-Clause-Patent, with BSD-3-Clause, MIT and CC0 parts | [LICENSE](https://raw.githubusercontent.com/MrCyjaneK/bc-ur/d82e7c753e710b8000706dc3383b498438795208/LICENSE) |
| `boost.txt` | Boost | 1.90.0 | BSL-1.0 | [LICENSE_1_0.txt](https://raw.githubusercontent.com/boostorg/boost/boost-1.90.0/LICENSE_1_0.txt) |
| `openssl.txt` | OpenSSL (also inside Tor) | 3.5.1 here, 3.6.4 in the iPhone Tor, 3.5.8 in the Windows Tor | Apache-2.0 | [LICENSE.txt](https://raw.githubusercontent.com/openssl/openssl/openssl-3.5.1/LICENSE.txt) |
| `libsodium.txt` | libsodium | 1.0.18 (from the build recipe; the binary has no version string) | ISC | [LICENSE](https://raw.githubusercontent.com/jedisct1/libsodium/1.0.18/LICENSE) |
| `unbound.txt` | Unbound | 1.23.0 | BSD-3-Clause and ISC | [LICENSE](https://raw.githubusercontent.com/NLnetLabs/unbound/release-1.23.0/LICENSE) |
| `protobuf.txt` | Protocol Buffers runtime | 3.6.1 | BSD-3-Clause | [LICENSE](https://raw.githubusercontent.com/protocolbuffers/protobuf/v3.6.1/LICENSE) |

Windows only, from the compiler the DLL was built with:

| File | Part | Version | License | Text from |
| --- | --- | --- | --- | --- |
| `mingw-w64-runtime.txt` | MinGW-w64 runtime, linked into the DLL | 13.0.0 | Permissive, several | [COPYING.MinGW-w64-runtime.txt](https://raw.githubusercontent.com/mingw-w64/mingw-w64/v13.0.0/COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt) |
| `winpthreads.txt` | `libwinpthread-1.dll` | mingw-w64 13.0.0 | MIT and BSD-3-Clause | [COPYING](https://raw.githubusercontent.com/mingw-w64/mingw-w64/v13.0.0/mingw-w64-libraries/winpthreads/COPYING) |
| `gcc-runtime-library-exception.txt` | GCC's libstdc++ and libgcc, linked into the DLL | 15.2.0 | GPL-3.0 with the GCC Runtime Library Exception, which leaves no source obligation | [COPYING.RUNTIME](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-15.2.0/COPYING.RUNTIME) |

Checked and not in the library, though monero_c's build list names some:
ZeroMQ, expat, zlib, libiconv, ICU, liblzma, zstd, hidapi, libusb, miniupnpc.

## Tor

| File | Part | Version | License | In | Text from |
| --- | --- | --- | --- | --- | --- |
| `tor.txt` | Tor | 0.4.9.13 | BSD-3-Clause, with the notices of code bundled in Tor | iPhone and Windows | `LICENSE` in [tor-0.4.9.13.tar.gz](https://archive.torproject.org/tor-package-archive/tor-0.4.9.13.tar.gz) |
| `tor-source.txt` | Where the source of the Windows `tor.exe` is (written for this app) | | | Windows | |
| `libevent.txt` | libevent | 2.1.13 | BSD-3-Clause | iPhone and Windows | [LICENSE](https://raw.githubusercontent.com/libevent/libevent/release-2.1.13-stable/LICENSE) |
| `liblzma.txt` | liblzma (XZ Utils) | 5.8.4 | 0BSD | iPhone | [COPYING.0BSD](https://raw.githubusercontent.com/tukaani-project/xz/v5.8.4/COPYING.0BSD) |
| `tor-framework.txt` | Tor.framework, which built the iPhone's Tor | 409.13.1 | MIT | iPhone | [LICENSE](https://raw.githubusercontent.com/iCepa/Tor.framework/v409.13.1/LICENSE) |
| `zlib.txt` | zlib | 1.3.2 | Zlib | Windows | [LICENSE](https://raw.githubusercontent.com/madler/zlib/v1.3.2/LICENSE) |

The iPhone's Tor is built without Tor's GPL option, so its LGPL proof-of-work
code is not in it. The Windows `tor.exe` is the Tor Project's own build, which
has that option on ("This build of Tor is covered by the GNU General Public
License"), so that `tor.exe` as a whole is under the GPL-3.0. The app only
starts it as a separate program, so this doesn't reach the app's own code. The
iPhone build uses Apple's own zlib, which isn't shipped with the app. The
Windows `tor.exe` has no liblzma or zstd in it, and `tor.txt`, `openssl.txt`,
`libevent.txt` and `zlib.txt` are byte for byte the notices the Tor Project
ships in its bundle's `docs/` folder.

## The fonts

| File | Part | Version | License | Text from |
| --- | --- | --- | --- | --- |
| `ibm-plex.txt` | IBM Plex Sans and IBM Plex Mono | Sans 1.1.0, Mono 2.5.0 | OFL-1.1 | The releases' `LICENSE.txt`, see `assets/fonts/README.md` |

## What the licenses ask

- **Keep the notices:** every part above. The app does, in Settings.
- **OpenSSL (Apache-2.0):** also say if it was changed. It wasn't.
- **monero_c, polyseed and the Trezor definitions (LGPL-3.0):** the app has to
  say they are used and under which license, ship the LGPL-3.0 and GPL-3.0
  texts, and say where their source is (`lgpl-source.txt`); the app does all
  three. The LGPL also asks that people can use the app with a changed version
  of the library. That needs a decision before the App Store: see
  [app-store.md](app-store.md#the-wallet-librarys-lgpl).
- **The Windows `tor.exe` (GPL-3.0):** ship the GPL-3.0 text and say where its
  source is (`tor-source.txt`); the app does both. If the Windows app is ever
  offered for download, put the same directions next to the download as well
  (GPL-3.0 section 6).
