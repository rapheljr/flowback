# Flowback Releasing, Signing & Notarization

This document outlines the official procedure for signing, notarizing, and distributing Flowback for macOS.

---

## Prerequisites

1. Active Apple Developer Account
2. Developer ID Application Certificate installed in macOS Keychain
3. App Store Connect API Key or Notarytool Keychain profile configured:
   ```bash
   xcrun notarytool store-credentials "flowback-notary" \
       --apple-id "developer@flowback.app" \
       --team-id "YOUR_TEAM_ID" \
       --password "app-specific-password"
   ```

---

## 1. Build Release Artifacts

Compile optimized release binaries:
```bash
bash Scripts/build.sh
```

---

## 2. Package & Code Sign `.app` Bundle

Assemble the bundle and apply Hardened Runtime signature inside-out:

```bash
# Package the application bundle
bash Scripts/package_app.sh 1.0.0 1 universal

# Official Developer ID Signing (Inside-Out)
# 1. Sign nested CLI binary
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app/Contents/Resources/flowback"

# 2. Sign main executable
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app/Contents/MacOS/Flowback"

# 3. Sign top-level bundle without --deep
codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Flowback (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app"

# Verify signature
codesign --verify --deep --strict --verbose=4 "dist/Flowback.app"
codesign -dv --verbose=4 "dist/Flowback.app"
```

---

## 3. Create & Notarize Artifacts

Build the distribution archives and compressed disk image:
```bash
# Package universal release artifacts, DMG, ZIP, and checksums
bash Scripts/package_release_artifacts.sh 1.0.0 universal
```

Sign the DMG (if distributing disk image):
```bash
codesign --sign "Developer ID Application: Flowback (TEAMID)" "dist/Flowback-1.0.0.dmg"
```

Submit for Apple Notarization:
```bash
xcrun notarytool submit "dist/Flowback-1.0.0-macos.zip" \
    --keychain-profile "flowback-notary" \
    --wait
```

If submission fails, retrieve Apple's detailed rejection log:
```bash
xcrun notarytool log <SUBMISSION_ID> --keychain-profile "flowback-notary"
```

Staple the notarization ticket to the application and disk image:
```bash
xcrun stapler staple "dist/Flowback.app"
xcrun stapler staple "dist/Flowback-1.0.0.dmg"
```

Validate stapled ticket and Gatekeeper acceptance:
```bash
xcrun stapler validate "dist/Flowback.app"
spctl --assess --type exec -v "dist/Flowback.app"
```

---

## 4. Homebrew Cask Formula

The staged Homebrew Cask formula is maintained at `Casks/flowback.rb` for tap distribution via `rapheljr/homebrew-flowback`:

```ruby
cask "flowback" do
  version "1.0.0"
  sha256 "VERIFIED_ARCHIVE_SHA256"

  url "https://github.com/rapheljr/flowback/releases/download/v#{version}/Flowback-#{version}-macos.zip"
  name "Flowback"
  desc "Focus and context orchestration across developer applications"
  homepage "https://rapheljr.github.io/flowback/"

  depends_on macos: :sonoma

  app "Flowback.app"
  binary "#{appdir}/Flowback.app/Contents/Resources/flowback"

  uninstall quit: "com.flowback.app"

  zap trash: [
    "~/.flowback",
    "~/Library/Preferences/com.flowback.app.plist",
    "~/Library/Saved Application State/com.flowback.app.savedState",
  ]
end
```

To validate the cask against Homebrew's official style and audit rules:
```bash
bash Scripts/generate_cask.sh 1.0.0
```

To test local installation from the cask:
```bash
brew install --cask Casks/flowback.rb
```
