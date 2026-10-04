# Linko SSH — investigation and discussion

Updated: 4 October 2026. This file is our persistent communication note.

## 1. My recommendation

Build Linko SSH around **saved connections → terminal tabs → persistent tmux sessions**, preserving the existing keyboard and touch controls. Keep all currently implemented SSH authentication and connection routes, including direct connections and jump hosts. Use the separate Tailscale Android app for networking.

The biggest wins are **an APK for each CPU architecture**, **removing the built-in video/audio player**, and **removing the built-in PDF reader**. We can simplify the rest of the interface without sacrificing SSH.

Your size estimate was right: I downloaded and inspected the upstream v2.10.2 release APK. It is **134.20 MB**, or **127.98 MiB**. It contains three sets of Android native binaries, for three CPU architectures. These are all Android binaries; they are not iPhone or Linux copies.

A phone-specific ARM64 APK with all current features would contain roughly **47.5 MB** of the current APK's entries. Removing media and PDF components brings that arithmetic estimate to about **27.6 MB**, before any savings from simplifying Dart application code. These are estimates from the existing binary, not newly built or tested APKs.

**Current status:** investigation only. No app code, branding, dependencies, Git remotes, or release scripts have been changed. Nothing has been committed, pushed, or uploaded. Only this report, its browser version, measured data, and local Dev Panel preview configuration were added.

## 2. What the software contains

The copied application is **KAMMEL SSH**, implemented in Flutter/Dart. The checkout is version `2.10.2+74`, commit `9e7334c`. It configures Android and Linux; there are no iOS, macOS, or Windows app runners in this checkout. Some dependencies support those platforms, but that does not mean their native binaries are included in the Android APK.

| Feature area | What is included | Fit for your needs |
| --- | --- | --- |
| SSH connections | Saved profiles, passwords, pasted private keys, generated device key, custom ports, jump hosts, SSH config import, connection testing | Keep |
| Sessions | Multiple terminal tabs, rename/close/reconnect, optional remote tmux attachment | Keep; improve tmux selection |
| Terminal input | Configurable quick keys, Ctrl/Esc/Tab/arrows, touch pad, gestures, selection, clipboard, search, command history, physical keyboard and Android IME handling | Keep |
| Background operation | Android foreground service, persistent notification, optional wake lock | Keep |
| Connection protection | Host key confirmation and SHA256 pinning, secure credential storage, optional biometric/device lock | Keep |
| SSH tunnels | Local `-L`, dynamic SOCKS `-D`, remote `-R`, tunnel controls and timeouts | Preserve initially |
| File tools | SFTP browser, upload/download, search, copy/move/delete/create, bookmarks and folder synchronization | Optional |
| Editing and viewing | Syntax-highlighted code editor, Markdown preview, raster/SVG images, PDF reader, video/audio players, external document opening | Remove media/PDF first; other tools optional |
| Server console | CPU/RAM/disk/services, Docker containers/images/volumes/networks/Compose, PostgreSQL/MySQL controls | Remove from your minimal version |
| Git tools | Changes, diffs, project tree, commit actions and commands sent to an agent | Remove from your minimal version |
| AI conveniences | Agent detection, status dashboard, alerts, launch buttons, prompt snippets, prompt composer, speech dictation, image/file attachments | Optional; some may still help your workflow |
| General app tools | Themes, fonts, Spanish/English/Chinese UI, backup/restore, onboarding, release notes, GitHub APK updater, desktop window/pane management | Keep useful settings and backups; simplify the rest |

The app provides interfaces to Docker, databases, Git and AI agents on your remote machine. It does **not** bundle Docker Engine, database servers, or an AI model. There is also no bundled Tailscale engine in the app.

Some old comments mention a local Linux distro, Alpine and proot. I found no `assets/distro` directory, no distro service, and no corresponding entry in the current asset manifest. That is not the explanation for this APK's size.

## 3. What actually takes space

These are measured ZIP entry sizes inside the [published APK](https://github.com/Jhongdlp/Kammel_ssh/releases/tag/v2.10.2), summed across ARM64, ARM32 and x86_64. MB means decimal megabytes. For the native libraries in this APK, the entries are stored without ZIP compression.

| Component | Measured APK contribution | What we can do |
| --- | --- | --- |
| Compiled Dart application, `libapp.so` | 41.52 MB | Includes reachable app and package code; a build size report is needed to allocate it to features |
| Media engine, `libmpv.so` | 39.93 MB | Remove the built-in audio/video players and media dependencies |
| Flutter engine, `libflutter.so` | 32.89 MB | Keep Flutter; ship only the appropriate architecture per APK |
| PDF engine, `libpdfium.so` | 13.41 MB | Remove built-in PDF viewing and its dependency |
| Other Flutter assets | 2.33 MB | Includes a 1.98 MB PDF WebAssembly asset |
| Other native libraries | 1.37 MB | Includes 1.04 MB of media helper libraries; some disappear with media playback |
| Fonts | 0.95 MB | Small compared with native engines |
| Android bytecode | 0.78 MB | Small; reduce unused plugins where practical |
| Other APK entries | 0.70 MB | Android resources and packaging entries |
| Bundled license asset | 0.11 MB | Retain required notices |

Entry sizes total approximately 133.99 MB. ZIP headers, alignment and signing account for the remaining approximately 0.21 MB. Raw data, byte counts and the APK SHA256 are in `docs/apk-size-analysis.json`.

Media playback plus its helper libraries account for about **40.96 MB**. PDF native libraries plus the PDF WebAssembly asset account for about **15.39 MB**. Together, these identifiable entries account for about **56.36 MB**, or **42%** of the current universal APK. Removing their dependencies can also reduce Dart code, but that extra saving has not been measured.

The PDF package explicitly documents removing its WebAssembly assets from non-web release builds. If you decide to keep PDF viewing, removing the unused web module is still a roughly 1.98 MB opportunity in this baseline. [PDF package instructions](https://pub.dev/packages/pdfrx/versions/2.2.24).

### Why separate Android APKs help

The current release repeats native code for three architectures:

| Architecture | Native entries | Shared non-native entries | Estimated existing-content APK size |
| --- | --- | --- | --- |
| ARM64, common on current phones | 42.62 MB | 4.86 MB | About 47.5 MB plus packaging |
| ARM32, for compatible older phones | 38.69 MB | 4.86 MB | About 43.6 MB plus packaging |
| x86_64, used by this emulator | 47.80 MB | 4.86 MB | About 52.7 MB plus packaging |

Flutter can generate these as separate APKs. Each is installable on devices supporting that architecture. We should confirm your phone's architecture before choosing its download. Keep x86_64 as a separate test artifact for the emulator. [Flutter Android build documentation](https://docs.flutter.dev/deployment/android).

The savings from architecture splitting and deleting libraries overlap: **do not add the 56.36 MB universal saving to the ARM64 saving**. Applying both to the current entry inventory yields roughly 27.6 MB for ARM64, before rebuilding.

APK download size, Android's installed app size, and later cache/download storage are different measurements. This report measures the APK file. Images/files downloaded through SFTP and cached fonts can add storage later.

## 4. What I would preserve

- Ordinary SSH over Tailscale, LAN, public IPs or another VPN; custom host, username and port.
- Password login, private-key login and the generated Ed25519 device key.
- Existing encrypted-key parsing. The current implementation reuses the profile password as the key passphrase; it does not offer a separate passphrase field.
- Jump hosts and multi-hop routes, including per-hop host key checks.
- Existing supported SSH config import and SSH command parsing.
- Host key verification, secure storage, profile backup/restore and optional app lock.
- Terminal tabs, reconnect, tmux, keyboard customization, clipboard, touch gestures, search and font sizing.
- Android background service and its notification, even if the AI alert/dashboard features are removed.
- Existing tunnel features initially, because you asked to preserve connection methods.

Keep the patched `third_party/xterm` terminal: it contains the Android keyboard and image-paste improvements. Keep patched `third_party/dartssh2`: it fixes tunnel flow control and exposes raw host keys for SHA256 pinning.

“All login methods” here means all methods currently wired into the app. It is not a complete OpenSSH replacement: keyboard-interactive/MFA has no app callback, SSH agent forwarding is not implemented, and config import does not implement `ProxyCommand`, `Match` or `Include`. Import records `IdentityFile` information but does not copy that private key from your computer. The short SSH-command parser also skips `-i` and `-J`; jump hosts are supported through the profile form and supported config import. These are current limitations, not proposed removals.

## 5. What I would cut, in order

### First: large libraries that SSH does not need

**Remove video/audio playback:** delete those viewers and playback widgets, remove `MediaKit.ensureInitialized()` and imports, and remove `media_kit`, `media_kit_video` and `media_kit_libs_video` dependencies. This saves the biggest optional native payload. If file tools remain, media files can be downloaded and opened in another Android app.

**Remove built-in PDF viewing:** remove the PDF viewer and `pdfrx`; its transitive PDF engine packages and WebAssembly assets should then disappear. PDFs can likewise open externally if downloads remain.

Hiding a menu item is insufficient. We must remove the code paths, dependencies and packaged assets, then verify the produced APK.

### Second: simplify the product

**Remove Docker/database/server panels and Git panels.** Their main benefit is a simpler app and less maintenance. These are mostly Dart interfaces and remote commands, so I cannot promise a particular MB saving. You can still run `docker`, `git`, `psql`, and other commands in the remote terminal.

**Remove the graphical code editor and document viewers** if you use terminal editors or coding agents. This removes `re_editor`, `re_highlight`, Markdown rendering and, where no remaining feature needs it, SVG viewing.

**Choose whether to keep a small SFTP tool.** Removing the full explorer simplifies the interface, but removing SFTP support itself is not a major size win because it lives in the same Dart SSH package. A small upload/download tool may be useful. Terminal image paste and attachments currently depend on SFTP, so they must be preserved or deliberately removed with the file tools.

**Treat AI features separately from terminal usability.** Agent dashboards, launchers, detection and alerts are optional. They are not bundled AI models and are not the main size problem. Keep prompt snippets or an easy multiline paste/composer if you use coding agents. Dropping custom speech dictation is an option; Android keyboard dictation can remain. Keep the keyboard-related terminal patches regardless.

### Third: low-value size work

Dropping Linux files and desktop window controls reduces maintenance, but Linux native binaries are already absent from the Android APK. Removing nonexistent iPhone support saves nothing.

The four Cascadia font files occupy 2.11 MB in the checkout, but about **0.81 MB** in the APK. All font entries together are about 0.95 MB. Agent image assets occupy about 180 KiB in the checkout. Languages and theme choices are also small compared with the media/PDF engines. I would preserve readability and keyboard comfort before optimizing these.

The Git history, README files, tests, screenshots in `public/`, build SDK and emulator are development files, not automatically shipped in the APK. Deleting them is not a useful APK size strategy.

## 6. Tailscale and tmux

**Recommended setup:** install and connect the separate Tailscale app on the phone; save the server's Tailscale IP or MagicDNS name in Linko SSH. Linko SSH uses its normal SSH client through that network. This keeps ordinary password/key login available when you use a different network route.

Tailscale networking and the **Tailscale SSH server feature** are distinct choices. Tailscale SSH authenticates using tailnet identity and SSH's `none` authentication method. The vendored Dart SSH library tries that method, so there is a plausible compatibility path, but I have not tested the app against your server or its browser-check policy. [Tailscale SSH documentation](https://tailscale.com/docs/features/tailscale-ssh).

Tmux runs on the **remote machine**, so it does not need a tmux executable bundled inside the Android APK. The current app optionally runs `tmux new-session -A`, attaches if a session exists, and falls back to a normal shell if tmux is absent.

There is one important usability gap: the automatic tmux session name is derived from the saved connection profile name, currently `kammel-<profile-name>`. Multiple terminal tabs using the same profile therefore target the same tmux session. It is not a dedicated browser for selecting several remote tmux sessions.

For your workflow, I recommend an explicit tmux session name per terminal tab and a small list/create/attach screen. That would let you choose, for example, `work`, `maintenance`, and `agent`, rather than requiring duplicate server profiles. It is a proposed improvement; nothing has been implemented.

## 7. Renaming and the later fork

Once we move from brainstorming to implementation, change the product name to **Linko SSH** in the Android launcher, app titles, onboarding, About screen, notification text, translated strings and documentation. Also replace the camel logo and launcher/notification artwork.

The rename needs more care than a global text replacement:

- Give the fork its own Android application ID and signing key so it installs independently and can receive consistent future updates.
- Update corresponding Kotlin packages and Flutter/native channel names together if those identifiers change.
- Disable or redirect the updater: it currently checks `Jhongdlp/Kammel_ssh`. With several APK architectures, replace its “first APK in the release” selection with device-architecture selection.
- Update release tooling and links after your repository exists. The existing `scripts/release.sh` commits, tags, pushes and publishes; we did not run it.
- Handle old tmux names and backup markers deliberately. Simply replacing `kammel-` or `kammel_backup` could prevent attachment to an existing remote session or import of an existing backup.
- Retain upstream and third-party copyright/license notices, including the notice explicitly required by the copied license. Preserve attribution in notices while rebranding the product interface.

The Android build currently uses compile SDK 36, target SDK 28 and legacy shared-storage behavior. A future fork should review that separately, especially if file downloads remain. It is not a major explanation for the APK size.

## 8. Building and testing later

The Android SDK, Java and a running x86_64 emulator are available here. Flutter is not on PATH, and the README's claimed `sdk/flutter` directory is absent from this checkout. We will need a compatible Flutter SDK before rebuilding; the project's CI pins Flutter 3.44.4 and the Dart constraint is `^3.12.2`.

An emulator is useful for running and testing the app, but it is **not required to produce an APK**. Building needs Flutter, Java and the Android SDK. This investigation did not install or launch the upstream app or produce a new APK.

A sensible implementation sequence is:

1. Establish a clean release-build baseline and size report.
2. Build separate architecture APKs, preserving all features, to measure that saving alone.
3. Remove media and PDF dependencies; measure again.
4. Simplify server/Git/editor/agent/file tools according to the agreed scope.
5. Implement Linko SSH branding and deliberate tmux session selection.
6. Verify password/key/device-key login, direct and jump-host routes, tunnels, host key checks, keyboard/paste behavior, reconnect and background operation in tmux. Test Tailscale on a real phone too; an emulator is not proof of phone VPN behavior.
7. Produce a signed phone APK and a separate emulator APK. Upload only after you request it and provide the new repository.

For measurement, Flutter supports release size analysis and comparing builds in DevTools. Debug APK sizes should not be used as the production baseline. [Flutter size analysis documentation](https://docs.flutter.dev/perf/app-size).

**Proposed scope for discussion:** Android, all existing SSH connection/authentication routes, terminal tabs, multiple named remote tmux sessions, full keyboard/touch/clipboard usability, background connection support, host key checks and saved credentials. Cut media/PDF, Docker/database/server controls, Git panels and the code editor. Keep a small SFTP/attachment tool and AI convenience controls only if they earn their place in your daily workflow.
