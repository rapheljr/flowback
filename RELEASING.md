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

Assemble the bundle and apply Hardened Runtime signature:

```bash
# Package the application bundle
bash Scripts/package_app.sh

# Official Developer ID Signing
codesign --force --options runtime --deep \
    --sign "Developer ID Application: Flowback Inc (TEAMID)" \
    --entitlements "dist/Flowback.entitlements" \
    "dist/Flowback.app"

# Verify signature
codesign --verify --deep --strict --verbose=4 "dist/Flowback.app"
spctl --assess --type exec -v "dist/Flowback.app"
```

---

## 3. Create & Notarize DMG

Build the compressed DMG disk image:
```bash
bash Scripts/create_dmg.sh
```

Sign the DMG:
```bash
codesign --sign "Developer ID Application: Flowback Inc (TEAMID)" "dist/Flowback.dmg"
```

Submit for Apple Notarization:
```bash
xcrun notarytool submit "dist/Flowback.dmg" \
    --keychain-profile "flowback-notary" \
    --wait
```

Staple the notarization ticket:
```bash
xcrun stapler staple "dist/Flowback.dmg"
xcrun stapler staple "dist/Flowback.app"
```

Verify notarization ticket:
```bash
spctl --assess -t open --context context:primary-signature -v "dist/Flowback.dmg"
```

---

## 4. Homebrew Cask Formula

To distribute via Homebrew:

```ruby
cask "flowback" do
  version "1.0.0"
  sha256 "HASH_OF_FLOWBACK_DMG"

  url "https://github.com/flowback/flowback/releases/download/v#{version}/Flowback.dmg"
  name "Flowback"
  desc "Universal macOS AI Agent Context and Focus Manager"
  homepage "https://flowback.app"

  app "Flowback.app"
  binary "#{appdir}/Flowback.app/Contents/Resources/flowback"

  zap trash: [
    "~/.flowback",
    "~/Library/Preferences/com.flowback.app.plist",
    "~/Library/Saved Application State/com.flowback.app.savedState",
  ]
end
```
