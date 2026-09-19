# Building Öffi NG

Öffi NG has **two parallel build systems**. Use the modern one.

| | `androidstudio/` (use this) | repo root (`build.Containerfile`, `.gitlab-ci.yml`) |
|---|---|---|
| Gradle | 9.6.1 (via `androidstudio/gradlew`) | 4.4.1 (Debian/Ubuntu `gradle`) |
| Android Gradle Plugin | 9.4.0 | 3.1.4 |
| App id / package | `namespace` in `build.gradle` | `package=` in the manifest |
| Status | **works** | **broken** — see below |

The shared `oeffi/AndroidManifest.xml` has no `package=` attribute (it relies on
the AGP `namespace` DSL). The legacy AGP 3.1.4 build at the repo root therefore
fails with `Cannot read packageName from .../AndroidManifest.xml`. This is true
of upstream `nextgen` as well; the root/Containerfile path is a leftover from the
original Öffi and has not survived the `namespace` migration. Build via
`androidstudio/`.

Sources are shared: `androidstudio/oeffi-studio/build.gradle` points its
sourceSets back at `../../oeffi/src`, `../../public-transport-enabler/src`,
`../../oeffi/res` and `../../oeffi/AndroidManifest.xml`.

## Toolchain

- **JDK 17 or 21** (AGP 9.x requires 17+).
- **Android SDK** with `platform-tools`, `platforms;android-36`,
  `platforms;android-37.0`, `build-tools;36.1.0`, `build-tools;37.0.0`
  (`compileSdk 37` maps to the `android-37.0` minor-version package).
- The **`public-transport-enabler` submodule** must be checked out
  (`git submodule update --init public-transport-enabler`).

On **Claude Code on the web** all of this is provisioned automatically by the
`SessionStart` hook (`.claude/hooks/session-start.sh`); nothing to do by hand.

## Build a debug APK (no release secret needed)

```bash
./.claude/build-debug.sh
# -> androidstudio/oeffi-studio/build/outputs/apk/ng/debug/oeffi-studio-ng-debug.apk
```

The app's `signingConfig` hard-codes santawho's **secret** release keystore
(`oeffi-ng.jks` + `OEFFI_NG_JKS_PASSWORD`). `build-debug.sh` sidesteps that with a
throwaway keystore and a Gradle `--init-script`
(`.claude/oeffi-debug-signing.init.gradle`); no tracked files are modified.

### Branch name → applicationId

`oeffi-studio/build.gradle` derives the applicationId from the current git
branch: any branch other than `main` / `master` / `nextgen` becomes an
`edition` suffix (e.g. `de.santawho.oeffi_ng.<branch>`). Branch names containing
`/` or `-` produce an **invalid** Android package name and fail resource linking.
`build-debug.sh`'s init script normalizes this automatically. To build the exact
release identity, build from `nextgen`.

## Carried MOTIS fixes (`.claude/patches/`)

Two fixes to `public-transport-enabler`'s MOTIS provider are not yet upstream, so
they ride as patches applied to the submodule at build time:

- `0001-ghost-bus-realtime.patch` — only show a real-time departure countdown when
  MOTIS actually has real-time data (otherwise it's shown as scheduled).
- `0002-resolve-freetext-locations.patch` — resolve a pasted free-text address
  (e.g. `600 N 34th St, Seattle, WA 98103`) via the geocoder instead of crashing;
  expands US street abbreviations so the address actually resolves.

The SessionStart hook and the CI workflow apply them idempotently. To apply by hand:

```bash
git submodule update --init public-transport-enabler
for p in .claude/patches/*.patch; do git -C public-transport-enabler apply "$PWD/$p"; done
```

## Continuous integration

`.github/workflows/build-debug-apk.yml` builds a debug-signed APK on every push to
this branch (and via **Run workflow**) and publishes it two ways:

- as a workflow **artifact** (`oeffi-ng-debug-apk`), and
- as a rolling pre-**release** tagged `debug-latest`, so the APK has a stable direct
  download URL — installable from a phone browser and trackable by Obtainium:
  `https://github.com/xerootg/oeffi-ng/releases/download/debug-latest/oeffi-ng-debug.apk`

It needs no secrets: it applies the patches above and signs with an ephemeral key.
Enable **Actions** on the fork (Actions tab) for it to run.

## Official release build

Real releases are produced by `androidstudio/` with the release keystore and a
GitHub token supplied via the environment (or `passwords.properties`):

```bash
export OEFFI_NG_JKS_PASSWORD=…            # unlocks the committed oeffi-ng.jks
cd androidstudio
./gradlew :oeffi-studio:assembleNgMainRelease
```

`assembleNgMainRelease` / `assembleNgPreRelease` also run release automation
(git tag + GitHub release upload); do not run them for a plain local build.

## Tests

Unit tests live in `oeffi/test` (2) and `public-transport-enabler/test`. Most PTE
tests are **live** (`*Live`) and need network access plus provider secrets
(`test/de/schildbach/pte/live/secrets.properties`); only the non-live tests run
offline:

```bash
cd androidstudio
./gradlew :oeffi-studio:testNgDebugUnitTest --tests '*ColorHashTest'
```
