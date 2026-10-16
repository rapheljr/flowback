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

Flowback builds disk images (`.dmg`) and zip archives (`.zip`) along with cryptographically verified checksums:

```bash
# 1. Clean previous build dist
rm -rf dist .build/release

# 2. Build release binaries
bash Scripts/build.sh

# 3. Package application bundle & apply ad-hoc or Developer ID signature
bash Scripts/package_app.sh

# 4. Generate compressed DMG
bash Scripts/create_dmg.sh

# 5. Generate release manifest & SHA-256 checksums
bash Scripts/generate_manifest.sh 1.0.0
```

Artifacts produced in `dist/`:
```text
dist/
├── Flowback.app
├── Flowback-1.0.0-arm64.dmg
├── Flowback-1.0.0-arm64.zip
├── SHA256SUMS
└── release-manifest.json
```

---

## 4. Code Signing & Apple Notarization (When Credentials Present)

For official production distribution, Apple requires Developer ID Application signing and notarization:

### Prerequisites:
* Apple Developer ID Application certificate installed in Keychain.
* Apple ID & App-specific password or App Store Connect API Key configured in `notarytool`.

### Commands:
```bash
# 1. Sign App Bundle with Hardened Runtime
codesign --force --options runtime --deep \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app"

# 2. Verify App signature
codesign --verify --deep --strict --verbose=4 "dist/Flowback.app"
spctl --assess --type exec -v "dist/Flowback.app"

# 3. Sign DMG
codesign --sign "Developer ID Application: Flowback (TEAMID)" "dist/Flowback-1.0.0-arm64.dmg"

# 4. Submit to Apple Notary Service
xcrun notarytool submit "dist/Flowback-1.0.0-arm64.dmg" \
    --keychain-profile "flowback-notary" \
    --wait

# 5. Staple Notarization Ticket
xcrun stapler staple "dist/Flowback-1.0.0-arm64.dmg"
xcrun stapler staple "dist/Flowback.app"

# 6. Verify Gatekeeper Acceptance
spctl --assess -t open --context context:primary-signature -v "dist/Flowback-1.0.0-arm64.dmg"
```

> [!NOTE]
> If Apple Developer credentials are absent (e.g. community pull requests or unauthenticated CI runners), the build pipeline automatically marks `signatureStatus` as `"ad-hoc"` and `notarizationStatus` as `"unnotarized"`.

---

## 5. Checksum Generation & Verification

Generate cryptographic hashes for all released binaries:

```bash
cd dist
shasum -a 256 Flowback-*.dmg Flowback-*.zip > SHA256SUMS
cat SHA256SUMS
```

To verify:
```bash
shasum -a 256 -c SHA256SUMS
```

---

## 6. GitHub Tagging & Automated Release Pipeline

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
   * Calculates SHA-256 hashes and generates `release-manifest.json`.
   * Drafts or publishes GitHub Release with attached assets:
     - `Flowback-<version>-arm64.dmg`
     - `Flowback-<version>-arm64.zip`
     - `SHA256SUMS`
     - `release-manifest.json`

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
