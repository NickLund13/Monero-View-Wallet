# Third-party code in the app

What the app ships besides its own code, and the license of each part. The
app's own code is under the GPL-3.0 with an App Store permission (`LICENSE`
and `APP-STORE-PERMISSION.txt`, shown in the app as `monero-view.txt` and
`gpl-3.0.txt`). The license texts are in `assets/licenses/`, and the app shows
them under Settings → Open-source licenses (`lib/licenses.dart`), each build
only its own. Flutter lists its engine and every Dart package there by itself.

Found on 2026-10-09 (the Android library on 2026-10-10) by reading the
pinned binaries themselves (the symbols, version strings and debug info of
the iPhone, Windows and Android wallet library, the member list of
Tor.framework's static library, the version strings of the Windows `tor.exe`
and the notices in its bundle's `docs/` folder), and the build files of
monero_c and Tor.framework at the pinned versions. If a pinned
version in `tool/fetch_monero_c.sh` or `tool/fetch_tor.sh` changes, check this
list again.

Each text is the upstream license file at that version, unchanged. Where a part
also carries notices in its source files, they follow the license after a
dashed line that says where they come from.

## The wallet library (monero_c v0.18.4.6-RC2)

In the iPhone build (MoneroWallet.framework), the Windows build (the DLL) and
the Android build (`libmonero_wallet2_api_c.so`, one for each kind of
processor).

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

Android only: the library is built with the Android NDK (r28c), which links
LLVM's C++ runtime (libc++, libc++abi and libunwind) into it. Their license,
Apache-2.0 with the LLVM exception, asks for no notice in a compiled program,
so there is no file for them. Otherwise the Android library holds the same
parts as the iPhone's.

Checked and not in the library, though monero_c's build list names some:
ZeroMQ, expat, zlib, libiconv, ICU, liblzma, zstd, hidapi, libusb, miniupnpc.

## Tor

| File | Part | Version | License | In | Text from |
| --- | --- | --- | --- | --- | --- |
| `tor.txt` | Tor | 0.4.9.13 | BSD-3-Clause, with the notices of code bundled in Tor | all | `LICENSE` in [tor-0.4.9.13.tar.gz](https://archive.torproject.org/tor-package-archive/tor-0.4.9.13.tar.gz) |
| `tor-source.txt` | Where the source of the Windows and Android tor is (written for this app) | | | Windows and Android | |
| `libevent.txt` | libevent | 2.1.13 | BSD-3-Clause | all | [LICENSE](https://raw.githubusercontent.com/libevent/libevent/release-2.1.13-stable/LICENSE) |
| `liblzma.txt` | liblzma (XZ Utils) | 5.8.4 | 0BSD | iPhone | [COPYING.0BSD](https://raw.githubusercontent.com/tukaani-project/xz/v5.8.4/COPYING.0BSD) |
| `tor-framework.txt` | Tor.framework, which built the iPhone's Tor | 409.13.1 | MIT | iPhone | [LICENSE](https://raw.githubusercontent.com/iCepa/Tor.framework/v409.13.1/LICENSE) |
| `zlib.txt` | zlib | 1.3.2 | Zlib | Windows and Android | [LICENSE](https://raw.githubusercontent.com/madler/zlib/v1.3.2/LICENSE) |
| `zstd.txt` | Zstandard | ZSTD_VERSION | BSD-3-Clause (offered with GPL-2.0 as the other choice) | Android | [LICENSE](https://raw.githubusercontent.com/facebook/zstd/vZSTD_VERSION/LICENSE) |

The iPhone's Tor is built without Tor's GPL option, so its LGPL proof-of-work
code is not in it. The Windows `tor.exe` and the Android tor are the Tor
Project's own builds, from its Tor Expert Bundle 15.0.24 for each, which have
that option on ("This build of Tor is covered by the GNU General Public
License"), so each as a whole is under the GPL-3.0. The app only starts it as
a separate program, so this doesn't reach the app's own code. The iPhone build
uses Apple's own zlib, which isn't shipped with the app. The Windows `tor.exe`
has no liblzma or zstd in it. The Android tor (the bundle's `tor/libTor.so`,
one for each kind of processor, shipped as `libtor.so`) has zstd built in and
no liblzma, as `tor --library-versions` says on the emulator (the Android
build workflow's smoke test prints it). `tor.txt`, `openssl.txt`,
`libevent.txt` and `zlib.txt` are byte for byte the notices the Tor Project
ships in both bundles' `docs/` folder, and `zstd.txt` is the Android bundle's
`docs/zstd-bsd.txt`. The Android bundle also has the pluggable transports
(lyrebird, conjure) and their notices, which the app leaves out, as it does
on Windows.

## The Android libraries

In the Android build only: the Java and Kotlin libraries that Flutter's
Android code (its embedding, `io.flutter:flutter_embedding_release`) depends
on, and the ones the app's own camera code (`QrCamera.kt`) uses: AndroidX
CameraX for the camera and ZXing's core to read QR codes, with what CameraX
depends on. Gradle packs them into the app. Found on 2026-10-10 in the release
build's runtime classpath (`./gradlew :app:dependencies --configuration
releaseRuntimeClasspath`, as the Android build workflow prints it when it
writes the Gradle checksums). All are under the Apache-2.0, so they share one
file, `android-libraries.txt`, written for this app: each part's copyright
line, the `NOTICE` files that Kotlin, kotlinx.coroutines, kotlinx.atomicfu,
Jakarta Dependency Injection and ZXing ship (the only ones of these that have
one), then the license, which is
[Kotlin's LICENSE.txt](https://raw.githubusercontent.com/JetBrains/kotlin/v2.4.0/license/LICENSE.txt),
byte for byte the Apache Software Foundation's text.

| Part | Version |
| --- | --- |
| AndroidX: activity 1.8.1, annotation 1.8.1, annotation-experimental 1.4.1, arch core 2.2.0, camera (camera2, camera2-pipe, core, lifecycle and featurecombinationquery) 1.6.2, collection 1.1.0, concurrent-futures 1.1.0, core 1.13.1, core-backported-fixes 1.0.0, customview 1.0.0, exifinterface 1.4.2, fragment 1.7.1, interpolator 1.0.0, lifecycle 2.7.0, loader 1.0.0, profileinstaller 1.3.1, savedstate 1.2.1, startup 1.1.1, tracing 1.3.0, versionedparcelable 1.1.1, viewpager 1.0.0, window 1.2.0, window extensions core 1.0.0 | as listed |
| Kotlin standard library | 2.4.0 |
| kotlinx.coroutines | 1.9.0 |
| kotlinx.atomicfu | 0.28.0 |
| JetBrains Java Annotations | 23.0.0 |
| Guava ListenableFuture | 1.0 |
| ReLinker | 1.4.5 |
| JSpecify | 1.0.0 |
| Dagger (used by CameraX) | 2.59 |
| Jakarta Dependency Injection (`jakarta.inject-api`) | 2.0.1 |
| JSR-330 Dependency Injection (`javax.inject`) | 1 |
| AutoValue annotations | 1.6.3 |
| ZXing core | 3.5.4 |

The app asks for CameraX, ZXing and `lifecycle-process` itself, at the
versions pinned in `android/app/build.gradle.kts`. The rest change with
Flutter, CameraX and the Kotlin version in `android/settings.gradle.kts`:
check this list again when any of them changes.

## The fonts

| File | Part | Version | License | Text from |
| --- | --- | --- | --- | --- |
| `ibm-plex.txt` | IBM Plex Sans and IBM Plex Mono | Sans 1.1.0, Mono 2.5.0 | OFL-1.1 | The releases' `LICENSE.txt`, see `assets/fonts/README.md` |

## What the licenses ask

- **Keep the notices:** every part above. The app does, in Settings.
- **OpenSSL (Apache-2.0):** also say if it was changed. It wasn't.
- **The Android libraries (Apache-2.0):** also ship the `NOTICE` files that
  come with them. The app does, in `android-libraries.txt`. None was changed.
- **monero_c, polyseed and the Trezor definitions (LGPL-3.0):** the app has to
  say they are used and under which license, ship the LGPL-3.0 and GPL-3.0
  texts, and say where their source is (`lgpl-source.txt`); the app does all
  three. The LGPL also asks that people can use the app with a changed version
  of the library. That needs a decision before the App Store: see
  [app-store.md](app-store.md#the-wallet-librarys-lgpl).
- **The Windows and Android tor (GPL-3.0):** ship the GPL-3.0 text and say
  where its source is (`tor-source.txt`); the app does both. If the Windows or
  Android app is ever offered for download, put the same directions next to
  the download as well (GPL-3.0 section 6).
