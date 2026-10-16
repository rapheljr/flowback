# Release Engineering & Publishing Checklist

This document details the step-by-step process for preparing, testing, packaging, signing, notarizing, publishing, and verifying Flowback releases.

---

## 1. Release Philosophy

* **Semantic Versioning:** Flowback strictly follows `MAJOR.MINOR.PATCH` ([semver.org](https://semver.org)).
* **Reproducibility:** All release artifacts must be built from a clean Git working tree tagged with `v<MAJOR>.<MINOR>.<PATCH>`.
* **Honest Provenance:** Never publish unsigned or ad-hoc builds claiming to be notarized. When Apple Developer ID credentials are not provided, release artifacts are clearly labeled as unsigned development builds.
* **Controlled Publishing:** Never automatically publish a production release purely because `main` branch updated. Releases are triggered exclusively by vetted version tags.

---

## 2. Pre-Release Preparation Checklist

Before cutting a release:

1. **Working Tree Cleanliness:**
   ```bash
   git status
   # Ensure working tree has no uncommitted changes
   ```

2. **Verify Version Consistency:**
   Ensure the target version (e.g., `1.0.0`) is updated across:
   * `Package.swift`
   * `Scripts/package_app.sh` (`CFBundleShortVersionString` in Info.plist template)
   * `Website/release-manifest.json`
   * `CHANGELOG.md`

3. **Review and Finalize Changelog:**
   * Open `CHANGELOG.md`.
   * Rename the `[Unreleased]` section to the new version header (e.g., `## [1.0.0] - 2026-10-16`).
   * Verify all added, changed, fixed, security, and known limitation entries are user-facing and accurate.

4. **Execute Full Test & Verification Suite:**
   ```bash
   # Run all 61 verification scenarios
   swift run FlowbackTestRunner
   ```
   Ensure 100% pass rate: `Passed: 61, Failed: 0`.

5. **Linting & Code Quality:**
   ```bash
   make lint || swiftlint
   ```

---

## 3. Building & Packaging Release Artifacts

Flowback builds disk images (`.dmg`) and zip archives (`.zip`) along with cryptographically verified checksums and a staged Homebrew Cask formula:

```bash
# 1. Clean previous build dist (optional)
rm -rf dist .build/release

# 2. Package universal release artifacts, DMG, ZIP, checksums, and Cask
bash Scripts/package_release_artifacts.sh 1.0.0 universal
# (Or using Makefile: make artifacts)
```

Artifacts produced in `dist/`:
```text
dist/
├── Flowback.app                  # Packaged macOS application bundle
├── Flowback-1.0.0-macos.zip      # Canonical distribution ZIP for Homebrew Cask
├── Flowback-1.0.0-arm64.zip      # Apple Silicon ZIP
├── Flowback-1.0.0.dmg            # Universal installer DMG
├── Flowback-1.0.0-arm64.dmg      # Apple Silicon installer DMG
├── Flowback.dmg                  # Unversioned convenience DMG
├── Flowback.entitlements         # Hardened Runtime entitlements
├── SHA256SUMS                    # SHA-256 cryptographic hashes
└── release-manifest.json         # Release metadata and asset provenance
Casks/
└── flowback.rb                   # Staged Homebrew Cask candidate
```

---

## 4. Code Signing & Apple Notarization

For official production distribution, Apple requires Developer ID Application signing and notarization:

### Prerequisites:
* Apple Developer ID Application certificate installed in macOS Keychain.
* Apple ID & App-specific password or App Store Connect API Key configured in `notarytool`:
  ```bash
  xcrun notarytool store-credentials "flowback-notary" \
      --apple-id "developer@flowback.app" \
      --team-id "YOUR_TEAM_ID" \
      --password "app-specific-password"
  ```

### Inside-Out Signing Workflow:
Apple requires code signing complex bundles from the inside out without `--deep` on the outer bundle:

```bash
# 1. Sign nested CLI companion
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app/Contents/Resources/flowback"

# 2. Sign main executable
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app/Contents/MacOS/Flowback"

# 3. Sign application bundle without --deep
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app"

# 4. Verify signature
codesign --verify --deep --strict --verbose=4 "dist/Flowback.app"
codesign -dv --verbose=4 "dist/Flowback.app"
```

### Apple Notarization & Stapling:
```bash
# 1. Submit distribution ZIP to Apple Notary Service
xcrun notarytool submit "dist/Flowback-1.0.0-macos.zip" \
    --keychain-profile "flowback-notary" \
    --wait

# 2. If submission fails, retrieve diagnostics:
xcrun notarytool log <SUBMISSION_ID> --keychain-profile "flowback-notary"

# 3. Staple ticket to bundle and disk image
xcrun stapler staple "dist/Flowback.app"
xcrun stapler staple "dist/Flowback-1.0.0.dmg"

# 4. Validate stapled ticket and Gatekeeper acceptance
xcrun stapler validate "dist/Flowback.app"
spctl --assess --type exec -v "dist/Flowback.app"
```

> [!NOTE]
> If Apple Developer credentials are absent (e.g. community pull requests or unauthenticated CI runners), the build pipeline automatically marks `signatureStatus` as `"ad-hoc"` and `notarizationStatus` as `"unnotarized"`.

---

## 5. Automated Release Validation

Before tagging or distributing any release, run the automated validation suite:

```bash
# Local development mode (permits ad-hoc signed preview):
bash Scripts/validate_release.sh --local 1.0.0
# (Or: make validate)

# Strict production release mode (requires Developer ID signature & notarization ticket):
bash Scripts/validate_release.sh --release 1.0.0
# (Or: make validate-release)
```

The validator checks:
1. Bundle layout and `+x` permissions for both `Flowback` and `flowback` binaries.
2. `Info.plist` validity via `plutil -lint` and key consistency.
3. Brand icon and menu bar template presence.
4. Minimal entitlements (strictly no `allow-jit` or `allow-unsigned-executable-memory`).
5. Binary architectures (`arm64`, `x86_64`, `universal`).
6. Code signature, runtime flags, and Gatekeeper assessment.
7. ZIP archive extraction and executable launch verification.
8. Checksums in `SHA256SUMS` match generated files.
9. `release-manifest.json` schema and git commit consistency.
10. Homebrew Cask formula syntax and hash alignment (`brew audit --cask`, `brew style --cask`).

---

## 6. Homebrew Cask Distribution

The staged Cask formula is generated at `Casks/flowback.rb`.

To audit and style check with Homebrew:
```bash
bash Scripts/generate_cask.sh 1.0.0
```

To test local installation in a dry-run or temporary directory:
```bash
brew tap-new --no-git local-flowback-test/tap
cp Casks/flowback.rb "$(brew --repo local-flowback-test/tap)/Casks/"
brew audit --cask local-flowback-test/tap/flowback
brew style --cask local-flowback-test/tap/flowback
brew untap local-flowback-test/tap
```

When publishing to the official tap `rapheljr/homebrew-flowback`:
1. Ensure the release tag `v1.0.0` is published and assets are downloadable from GitHub Releases.
2. Copy `Casks/flowback.rb` to the `rapheljr/homebrew-flowback` repository under `Casks/flowback.rb`.
3. Commit and push to `main` branch of `homebrew-flowback`.
4. Users install with:
   ```bash
   brew tap rapheljr/flowback
   brew install --cask flowback
   ```

---

## 7. GitHub Tagging & Automated Release Pipeline

1. **Commit and Tag:**
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0: Universal macOS AI Agent Context & Focus Manager"
   git push origin v1.0.0
   ```

2. **GitHub Actions Workflow:**
   * Pushing tag `v*` triggers `.github/workflows/release.yml`.
   * The workflow compiles the release binaries on a clean macOS runner.
   * Assembles `Flowback.app`, creates DMG and ZIP.
   * Signs and notarizes if secrets (`APPLE_CERTIFICATE`, `APPLE_ID`) are configured.
   * Runs `Scripts/validate_release.sh`.
   * Calculates SHA-256 hashes and generates `release-manifest.json` and `Casks/flowback.rb`.
   * Publishes GitHub Release with attached assets:
     - `Flowback-<version>-macos.zip`
     - `Flowback-<version>-arm64.zip`
     - `Flowback-<version>.dmg`
     - `Flowback-<version>-arm64.dmg`
     - `SHA256SUMS`
     - `release-manifest.json`
     - `Casks/flowback.rb`

---

## 7. Website Metadata Sync

1. Update `Website/release-manifest.json` with the newly published asset URLs and checksums.
2. The Download page (`/download/`) automatically consumes this manifest, rendering dynamic download buttons, version badges, release dates, and verified hashes.

---

## 8. Post-Release Smoke Testing

Immediately after publishing:
1. Download `Flowback-<version>-arm64.dmg` from the live release link.
2. Verify checksum against published `SHA256SUMS`.
3. Open DMG, mount volume, and launch `Flowback.app`.
4. Run `flowback doctor` and `flowback status`.
5. Trigger a test event via `flowback test-focus` or `flowback emit`.
6. Confirm notification and window restoration behavior.

---

## 9. Rollback & Yanking Procedures

If a critical flaw or regression is detected in a released build:

1. **Edit the GitHub Release:**
   * Mark the release as **Pre-release** or prepend `[BROKEN / DO NOT USE]` to the title.
   * Provide a clear explanation of the affected scenario and recommended workaround.
2. **Revert Website Manifest:**
   * Update `Website/release-manifest.json` to point back to the previous stable release version.
   * Deploy the updated site so new visitors are not served the faulty build.
3. **Issue Hotfix:**
   * Implement fix on `main`.
   * Run verification suite.
   * Tag incremented patch release (e.g. `v1.0.1`) following this checklist.
