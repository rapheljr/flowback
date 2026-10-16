# Third-Party Notices & Licenses

Flowback is built using native macOS technologies, the Swift Standard Library, and select open-source components. This document provides notice of third-party software, fonts, and standards incorporated into or utilized by Flowback.

---

## 1. SQLite

* **Component:** SQLite 3 (C Library)
* **Website:** https://www.sqlite.org/
* **License:** Public Domain
* **Notice:**
  > All of the code and documentation in SQLite has been dedicated to the public domain by the authors. All code authors, and representatives of the companies they work for, have signed affidavits dedicating their contributions to the public domain and original signed copies of these affidavits are stored in a firesafe at the main offices of Hwaci. Anyone is free to copy, modify, publish, use, compile, sell, or distribute the original SQLite code, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

---

## 2. Apple Technologies & Frameworks

Flowback interfaces with standard system frameworks provided by macOS 14 Sonoma SDK and newer under Apple Inc. developer terms:

* **AppKit (`Cocoa.framework`)**: Window management, running application observation (`NSWorkspace`), status bar item coordination (`NSStatusBar`).
* **SwiftUI**: Dashboard view presentation and UI components.
* **CoreGraphics (`CGEventSource`)**: Senses system idle duration without inspecting keystrokes or event data.
* **ApplicationServices (`HIServices / AXUIElement`)**: Queries window identifiers and executes window raise actions (`kAXRaiseAction`) when accessibility authorization is granted by the user.
* **UserNotifications (`UNUserNotificationCenter`)**: Delivers interactive macOS completion notifications.
* **ServiceManagement (`SMAppService`)**: Modern launch-at-login background agent registration.

---

## 3. Web & Font Assets

* **Fonts Used in Marketing Website:**
  * System Font Stack (`-apple-system`, `BlinkMacSystemFont`, `SF Pro Display`, `SF Pro Text`, `SF Mono`): Native Apple system fonts rendered directly from the host operating system.
* **Icons:**
  * All application icons, diagrams, and branding graphics in this repository are custom SVG vector illustrations authored specifically for Flowback and released under the repository's MIT License.

---

## 4. Contributor Covenant Code of Conduct

* **Document:** `CODE_OF_CONDUCT.md`
* **Source:** Contributor Covenant version 2.1
* **License:** Creative Commons Attribution 4.0 International (CC BY 4.0)
* **Website:** https://www.contributor-covenant.org/
