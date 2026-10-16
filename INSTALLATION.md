# Flowback Installation & Setup Guide

This guide walks you through installing, configuring, verifying, and uninstalling Flowback on macOS.

---

## System Requirements

* **Operating System:** macOS 14.0 (Sonoma) or newer (macOS 14, macOS 15 Sequoia, and newer).
* **Architecture:** Apple Silicon (M1/M2/M3/M4) or Intel x86_64.
* **Permissions:** Accessibility (`AXUIElement`) and User Notifications (`UNUserNotificationCenter`).

---

## Installation Methods

### Method 1: macOS Disk Image (`.dmg`) — Recommended

1. **Download the Disk Image:**
   Download the latest `Flowback-<version>-arm64.dmg` (for Apple Silicon) or `Flowback-<version>-universal.dmg` from the [Downloads Page](https://rapheljr.github.io/flowback/download/) or [GitHub Releases](https://github.com/rapheljr/flowback/releases).

2. **Verify Checksum (Optional but Recommended):**
   Compare the downloaded file's SHA-256 hash against the published `SHA256SUMS`:
   ```bash
   shasum -a 256 Flowback-*.dmg
   ```

3. **Install Application:**
   * Double-click the downloaded `.dmg` file to mount it.
   * Drag the **Flowback** icon into your **Applications** folder.
   * Eject the disk image.

4. **Install CLI Companion (`flowback`):**
   The CLI tool is bundled inside the application bundle at `Flowback.app/Contents/Resources/flowback`. You can symlink it to your PATH:
   ```bash
   sudo ln -sf /Applications/Flowback.app/Contents/Resources/flowback /usr/local/bin/flowback
   ```
   *(Or run `Scripts/install_cli.sh` from the repository).*

---

### Method 2: Homebrew Cask

To install Flowback via Homebrew Cask:
```bash
brew tap rapheljr/flowback
brew install --cask flowback
```

To upgrade via Homebrew:
```bash
brew upgrade --cask flowback
```

To uninstall via Homebrew:
```bash
brew uninstall --cask flowback
# Or to additionally remove local database and preferences:
brew uninstall --cask --zap flowback
```

---

### Method 3: Build from Source

If you prefer building from source:

```bash
# 1. Clone repository
git clone https://github.com/rapheljr/flowback.git
cd flowback

# 2. Compile release binaries
bash Scripts/build.sh

# 3. Assemble application bundle
bash Scripts/package_app.sh

# 4. Copy to Applications
cp -R dist/Flowback.app /Applications/

# 5. Link CLI
bash Scripts/install_cli.sh
```

---

## First-Time Configuration & Permissions

When you first launch Flowback:

### 1. Launch the Application
```bash
open -a Flowback
```
A lightweight compass/focus icon appears in your macOS menu bar.

### 2. Grant Accessibility Permission
Flowback requires macOS Accessibility permissions to query window titles and perform exact window raising without disruptive application-switching loops:
1. Open **System Settings** → **Privacy & Security** → **Accessibility**.
2. Toggle **Flowback** to **ON**.
*(If prompted by macOS upon launch, click "Open System Settings" and grant permission).*

> [!NOTE]
> If Accessibility permission is not granted, Flowback degrades gracefully to application-level switching via `NSWorkspace` instead of raising specific windows.

### 3. Grant Notification Permission
When prompted, click **Allow** so Flowback can deliver alerts when you are actively typing in another application.

### 4. Verify System Health with `flowback doctor`
Run the built-in diagnostic tool to verify all permissions and hooks:
```bash
flowback doctor
```

Expected output:
```text
=== Flowback Doctor Diagnostics ===
✓ Operating System: macOS 14.0+ supported
✓ Accessibility Permission: Granted
✓ Notification Permission: Authorized
✓ Database: Connected (~/.flowback/flowback.sqlite)
✓ IPC Socket: Active (~/.flowback/flowback.sock)
✓ Event Bus: Operational
✓ Focus Controller: Ready
```

---

## macOS Gatekeeper Troubleshooting

If macOS displays *"Flowback cannot be opened because the developer cannot be verified"*:

1. Right-click (or Control-click) on `/Applications/Flowback.app` in Finder and select **Open**.
2. In the confirmation dialog, click **Open**.
3. Alternatively, if developing or using an ad-hoc signed build:
   ```bash
   xattr -cr /Applications/Flowback.app
   ```

---

## Upgrading Flowback

1. Download the new release `.dmg`.
2. Open the `.dmg` and drag `Flowback.app` to `/Applications`, selecting **Replace**.
3. Launch Flowback. Your existing local session database (`~/.flowback/flowback.sqlite`) and settings will be preserved and automatically migrated to newer schema versions.

---

## Complete Uninstallation

Flowback provides a clean removal process that does not delete your projects or personal files.

### Step 1: Quit Flowback
```bash
pkill Flowback || true
```

### Step 2: Remove Injected Hooks
Remove Flowback commands from your agent configurations (e.g., Antigravity `~/.gemini/config/hooks.json` or custom shell scripts):
```bash
flowback hook antigravity --uninstall 2>/dev/null || true
```

### Step 3: Remove Application & CLI
```bash
rm -rf /Applications/Flowback.app
sudo rm -f /usr/local/bin/flowback
```

### Step 4: Remove Persistent State (Optional)
To delete local session history, database, and Unix domain socket:
```bash
# WARNING: This permanently deletes local session history
rm -rf ~/.flowback
rm -f ~/Library/Preferences/com.flowback.app.plist
```
