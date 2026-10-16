# Flowback — Brand Identity Guidelines & Asset Specifications

**Version:** 1.0.0  
**Effective Date:** October 2026  
**Status:** Official & Production-Ready  
**Asset Location:** `Design/Brand/`  

---

## Table of Contents
1. [Brand Overview & Philosophy](#1-brand-overview--philosophy)
2. [Primary Symbol](#2-primary-symbol)
3. [Typography & Wordmark](#3-typography--wordmark)
4. [Logo Lockups & Clear Space](#4-logo-lockups--clear-space)
5. [Color System & Palette](#5-color-system--palette)
6. [macOS Application Icon](#6-macos-application-icon)
7. [macOS Menu Bar Icon](#7-macos-menu-bar-icon)
8. [Usage Rules & Anti-Patterns](#8-usage-rules--anti-patterns)
9. [Asset Directory Index](#9-asset-directory-index)
10. [Production Integration Guide](#10-production-integration-guide)

---

## 1. Brand Overview & Philosophy

### Product Context
Flowback is a native macOS focus and context orchestrator for AI coding workflows. It operates alongside developer tools—including AI coding agents (Claude Code, Cursor, Codex, aider), editors (Xcode, VS Code, JetBrains), and terminals (Ghostty, iTerm2, Terminal.app).

Flowback is **not** an AI coding agent, IDE, or general automation platform. It is a precision attention orchestrator designed to protect developer concentration and restore context when background agents finish or require human intervention.

### Core Philosophy
- **Integrate broadly, orchestrate narrowly:** Connect seamlessly to developer environments, but intervene only when attention decisions are required.
- **Restore focus conservatively:** Never steal focus while active typing or active thought is occurring.
- **Respect user intent:** When human attention is needed, route the user back to the exact origin window, workspace, and context.
- **Calm, precise, and technical:** Deliver a native macOS utility aesthetic that feels engineered rather than illustrated.

### Brand Promise
> **"Get back to the right context, at the right moment."**

---

## 2. Primary Symbol

The Flowback symbol is an engineered geometric mark representing **the cycle of asynchronous work flowing out and orchestrated attention returning to the origin context**.

```
       ┌────────────────────────────────────────────────────────┐
       │                 THE FLOWBACK SYMBOL                    │
       │                                                        │
       │           [64,112]                                     │
       │           ╭──────╮       ╭────────────────╮            │
       │           │      │───────╯                │            │
       │           │  (⊙) │  [Nucleus]             │            │
       │           │      │                        │ [Loop]     │
       │           │      │◀──────────────╮        │            │
       │           │      │ [Chevron]     ╰────────╯            │
       │           ╰──────╯                                     │
       │           [Origin Anchor]                              │
       │                                                        │
       └────────────────────────────────────────────────────────┘
```

### Symbol Anatomy
1. **The Origin Context Anchor (Left Monolith):**
   - A grounded, pill-shaped monolith (`width: 96`, `height: 288`, `corner-radius: 48`).
   - Represents the developer's primary workspace (the origin IDE or terminal window).
   - Solid, stable, and reassuring.

2. **The Focus Nucleus (Target Core):**
   - An aperture knockout (`r: 22`) centered at `(112, 256)` with an electric cyan core dot (`r: 10`).
   - Represents the precise coordinate of active focus.

3. **The Asynchronous Return Loop (Cantilever Trajectory):**
   - A continuous 48-unit wide ribbon that departs from the anchor, arcs 180° around the center, and sweeps back horizontally.
   - Represents the autonomous, background flight path of an AI coding agent.

4. **The Precision Re-Entry Chevron (Focus Vector):**
   - A 45° beveled return vector pointing directly into the receiving edge of the Origin Anchor.
   - Separated by an intentional 32-unit negative space tension channel.
   - Represents the instant attention snaps cleanly back to the origin context.

### Mathematical Geometry & Construction
- **Master Coordinate Space:** `512 × 512` units.
- **Active Glyph Bounds:** Width = 348 units, Height = 320 units.
- **Optical Centering Offset:** `translate(+18, -16)` gives equal margins:
  - Horizontal Margins: Exactly **82 units** left and right.
  - Vertical Margins: Exactly **96 units** top and bottom.
- **Mass-to-Space Ratio:** 58% positive solid mass to 42% calibrated negative space.

---

## 3. Typography & Wordmark

### The Brand Name
The brand name is written in Title Case: **`Flowback`**.  
*Never write `flowback` (all-lowercase) in display typography or headers, nor `FLOWBACK` (all-caps), unless representing CLI commands (`flowback status`).*

### Typographic Specification
- **Primary Typeface:** SF Pro Display (macOS System Font) / Inter / Segoe UI.
- **Weight:** Semibold (`font-weight: 650` or `font-weight: 600`).
- **Letter Spacing:** `-0.025em` to `-0.03em` (`-1.8px` at 64px display size).
- **Ascender Harmony:** In the word `Flowback`, letters `F`, `l`, `b`, and `k` share identical ascender height.
- **Grounded Baseline:** `Flowback` contains **zero descenders** (`p`, `q`, `g`, `j`, `y`). All 8 characters sit firmly on the baseline, providing extraordinary architectural stability next to the symbol.

```
       F  l  o  w  b  a  c  k
       ┬  ┬  ─  ─  ┬  ─  ─  ┬   <- Ascender Plane (F, l, b, k)
       │  │  ╭──╮  │  ╭──╮  │
       │  │  │  │  │  │  │  │   <- Midline / x-height (o, w, a, c)
       ┴  ┴  ╰──╯  ┴  ╰──╯  ┴   <- Baseline Plane (All 8 letters sit squarely)
```

---

## 4. Logo Lockups & Clear Space

### 1. Horizontal Lockup (`logo-horizontal-dark.svg`, `logo-horizontal-light.svg`)
The horizontal lockup is the primary identity presentation for web headers, documentation titles, README banners, and marketing materials.
- **Canvas:** 640 × 160 px.
- **Symbol Scale:** Scaled to 104 × 104 px, vertically aligned with the cap-height of the wordmark.
- **Clear Distance:** Exactly 24 px between the symbol right edge and the wordmark left edge.

### 2. Stacked Lockup (`logo-stacked-dark.svg`, `logo-stacked-light.svg`)
The stacked lockup is designed for centered presentations, splash screens, square social avatars, and exhibition cards.
- **Canvas:** 360 × 400 px.
- **Symbol Scale:** Scaled to 200 × 200 px, horizontally centered.
- **Clear Distance:** 60 px between symbol bottom and wordmark baseline.

### Clear Space Rule
A mandatory clear space perimeter equal to **$X$** (where $X = 1/2$ the symbol width) must surround all lockups on all four sides. No text, graphic, border, or interface element may encroach upon this clear space zone.

```
            ┌──────────────────────────────────────────────┐
            │                     X                        │
            │     ┌──────┐                                 │
            │  X  │ SYMBOL│   X   Flowback   macOS     X   │
            │     └──────┘                                 │
            │                     X                        │
            └──────────────────────────────────────────────┘
```

### Minimum Sizing Limits
| Format | Minimum Dimensions | Primary Use Case |
| :--- | :--- | :--- |
| **Menu Bar Icon** | 16 × 16 px (18 × 18 pt canvas) | macOS Menu Bar Status Item |
| **Standalone Symbol** | 24 × 24 px | List icons, compact CLI tables |
| **Horizontal Lockup** | 120 × 30 px | Navigation bars, documentation headers |
| **Stacked Lockup** | 120 × 133 px | Centered dialogs, modal cards |
| **Application Icon** | 16 × 16 px up to 1024 × 1024 px | macOS Dock, Finder, App Store |

---

## 5. Color System & Palette

Flowback utilizes a calm, restrained, Mac-native color palette inspired by deep slate, precision aluminum, and electric focus illumination.

```
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│  DEEP GRAPHITE  │  SLATE SURFACE  │ CRISP OFF-WHITE │  ELECTRIC CYAN  │
│     #0B0F17     │     #141B29     │     #F8FAFC     │     #38BDF8     │
│                 │                 │                 │                 │
│  Canvas Base    │  Elevated Card  │  Primary Metal  │  Focus Accent   │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

### Palette Tokens

#### 1. Primary Colors
| Color Token | HEX | RGB | HSL | Role / Application |
| :--- | :--- | :--- | :--- | :--- |
| **Deep Graphite** | `#0B0F17` | `11, 15, 23` | `220°, 35%, 7%` | Primary dark canvas background, dark app icon body |
| **Slate Surface** | `#141B29` | `20, 27, 41` | `220°, 34%, 12%` | Secondary elevated surface, card fill, badge background |
| **Crisp Off-White** | `#F8FAFC` | `248, 250, 252` | `210°, 40%, 98%` | Primary Origin Anchor monolith, dark-mode wordmark |
| **Electric Cyan** | `#38BDF8` | `56, 189, 248` | `199°, 94%, 60%` | Primary return trajectory gradient start, focus nucleus dot |
| **Deep Focus Blue**| `#0284C7` | `2, 132, 199` | `200°, 98%, 39%` | Return trajectory gradient terminal, ambient lighting |

#### 2. Neutral & Supporting Colors
| Color Token | HEX | RGB | Role / Application |
| :--- | :--- | :--- | :--- |
| **Border Slate** | `#334155` | `51, 65, 85` | Subtle container borders, engineering guide rings |
| **Muted Text** | `#94A3B8` | `148, 163, 184` | Subtitles, version badges, secondary descriptions |
| **Aluminum Silver**| `#CBD5E1` | `203, 213, 225` | Monolith bevel highlights, light-mode secondary text |
| **Light Canvas** | `#FFFFFF` | `255, 255, 255` | Light-mode application background, pure white mono |
| **Jet Black** | `#000000` | `0, 0, 0` | Pure black monochrome, terminal silhouette |

### Color Contrast & Accessibility (WCAG 2.1 Scope)
Contrast ratios have been mathematically calculated using WCAG 2.1 relative luminance formulas ($L = 0.2126 \cdot R + 0.7152 \cdot G + 0.0722 \cdot B$). Requirements differ between text (4.5:1 AA / 7.0:1 AAA) and graphical user interface components (3.0:1 AA):

- **Dark Mode Primary Text:** Crisp Off-White (`#F8FAFC`) on Deep Graphite (`#0B0F17`) achieves **18.33 : 1** (Passes WCAG AAA for normal text, large text, and icons).
- **Dark Mode Focus Accent:** Electric Cyan (`#38BDF8`) on Deep Graphite (`#0B0F17`) achieves **8.95 : 1** (Passes WCAG AAA for text and UI graphical components).
- **Dark Mode Elevated Surface:** Electric Cyan (`#38BDF8`) on Slate Surface (`#141B29`) achieves **8.04 : 1** (Passes WCAG AAA).
- **Light Mode Primary Text:** Deep Slate text (`#0F172A`) on Light Canvas (`#FFFFFF`) achieves **17.85 : 1** (Passes WCAG AAA).
- **Light Mode Graphical Accent:** Deep Focus Blue (`#0284C7`) on Light Canvas (`#FFFFFF`) achieves **4.10 : 1** (Passes WCAG 2.1 AA for UI components and large text >= 18pt).
- **CRITICAL RESTRICTION — Light Mode Accent Usage:** Electric Cyan (`#38BDF8`) on Light Canvas (`#FFFFFF`) achieves only **2.14 : 1** and fails WCAG minimums. Consequently, Electric Cyan is **strictly forbidden for use on light backgrounds**. On light interfaces, Deep Focus Blue (`#0284C7` or `#0369A1`) must be used for all graphical elements and text.


---

## 6. macOS Application Icon

The Flowback Application Icon (`app-icon.svg`, `app-icon.png`) is designed in strict accordance with Apple's macOS Human Interface Guidelines (macOS Sonoma and Sequoia):

```
       ┌────────────────────────────────────────────────────────┐
       │             macOS APP ICON SPECIFICATION               │
       │                                                        │
       │   Master Canvas: 1024 × 1024 px                        │
       │   Squircle Base: 824 × 824 px centered at (512, 512)   │
       │   Corner Radius: 185 px                                │
       │   Overhead Lighting: 90° diffuse illumination          │
       │   Rim Highlight: 3 px gradient stroke (32% opacity)    │
       │   Shadows: Layered drop shadow (dy=28, blur=32, α=0.55)│
       │                                                        │
       └────────────────────────────────────────────────────────┘
```

### Key Engineering Details
1. **Materiality:**
   - Deep graphite brushed slate finish (`#1E2638` top to `#0A0E17` bottom).
   - Micro-beveled rim highlight reflecting ambient overhead light.
2. **Subtle Engineering Alignment Guides:**
   - Ultra-subtle concentric radar rings and orthogonal crosshair lines (35% opacity `#334155` with dash arrays `4 8`), signaling context orchestration.
3. **Symbol Luminescence:**
   - The Cantilever Return Loop emits a soft cyan ambient back-glow (`feGaussianBlur stdDeviation="36"`), illuminating the brushed slate canvas.
4. **Dock Presence:**
   - Standout silhouette that holds its ground alongside Xcode, Terminal, Instruments, and Docker on both light and dark desktop wallpapers.

---

## 7. macOS Menu Bar Icon

The Menu Bar icon (`menubar-icon.svg`) is engineered specifically for the macOS menu bar status item (`NSStatusItem` / SwiftUI `MenuBarExtra`).

### Template Image Protocol
- In macOS AppKit, the menu bar icon must be configured as a **Template Image**:
  ```swift
  let statusImage = NSImage(named: "MenuBarIcon")
  statusImage?.isTemplate = true
  statusButton.image = statusImage
  ```
- **Vector Construction:**
  - Designed on an **18 × 18 pt** canvas (36 × 36 px Retina `@2x`).
  - Uses `fill="currentColor"` and `stroke="currentColor"`.
  - When the user selects a Dark Menu Bar, macOS automatically paints the icon in crisp white.
  - When the user selects a Light Menu Bar, macOS automatically paints the icon in crisp graphite black.
  - Zero loss of legibility at 16 × 16 px.

---

## 8. Usage Rules & Anti-Patterns

To maintain brand consistency and authority, strictly follow these rules:

```
┌─────────────────────────────────┬─────────────────────────────────┐
│            CORRECT              │           DO NOT USE            │
├─────────────────────────────────┼─────────────────────────────────┤
│ ✓ Use official SVG/PNG assets.  │ ✗ Do not flip or mirror glyph.  │
│ ✓ Preserve negative space gap.  │ ✗ Do not add AI sparkle stars.  │
│ ✓ Maintain 1/2 clear space.     │ ✗ Do not add 3D bevel bubbles.  │
│ ✓ Use electric cyan accent.     │ ✗ Do not use rainbow gradients. │
│ ✓ Render monochrome on template.│ ✗ Do not embed wordmark in icon.│
└─────────────────────────────────┴─────────────────────────────────┘
```

### The 10 Inviolable Rules
1. **Never Flip or Reverse the Trajectory:** The Cantilever Loop must always depart from the top and return *from right to left* back into the Origin Anchor. Never mirror or reverse this flow.
2. **Never Add AI Sparkles or Stars:** Flowback is an engineered developer utility, not a consumer chatbot. Never decorate the mark with sparkles, magic wands, or neural network nodes.
3. **Never Compress or Distort Proportions:** Always scale the symbol and wordmark proportionally (`aspect-ratio: 1 / 1`).
4. **Never Encroach on Clear Space:** Respect the mandatory $X$ clear space clearance perimeter around all lockups.
5. **Never Use Unapproved Color Gradients:** Do not replace the Electric Cyan gradient (`#38BDF8` → `#0284C7`) with purple, magenta, orange, or rainbow gradients.
6. **Never Add Heavy 3D Textures or Drop Shadows to the Standalone Symbol:** The standalone symbol is a clean, flat engineered mark. The drop shadow belongs exclusively on the macOS squircle app icon canvas.
7. **Never Embed the Wordmark in the App Icon:** In accordance with Apple HIG, macOS app icons should never contain the app title text.
8. **Never Use Thin Wireframes at 16px:** For menu-bar sizes, always use the dedicated `menubar-icon.svg` asset where stroke weights are calibrated to 1.8 pt.
9. **Never Colorize the Menu Bar Template:** The menu bar icon must always remain pure monochrome (`isTemplate = true`) to respect the user's macOS system appearance.
10. **Never Separate the Anchor and Loop Arbitrarily:** The Origin Anchor, Focus Nucleus, Return Loop, and Chevron form a unified semantic system. Do not isolate individual pieces out of context.

---

## 9. Asset Directory Index

All production assets are organized in `Design/Brand/`:

```
Design/Brand/
│
├── Vector SVGs (Self-Contained, Scalable)
│   ├── symbol.svg                    # Primary standalone color symbol
│   ├── symbol-monochrome-black.svg   # Pure black silhouette on transparent
│   ├── symbol-monochrome-white.svg   # Pure white silhouette on transparent
│   ├── menubar-icon.svg              # 18x18 pixel-aligned macOS template image
│   ├── wordmark.svg                  # Standalone typographic wordmark (dark)
│   ├── wordmark-dark.svg             # Typographic wordmark for dark surfaces
│   ├── wordmark-light.svg            # Typographic wordmark for light surfaces
│   ├── logo-horizontal.svg           # Standard horizontal lockup
│   ├── logo-horizontal-dark.svg      # Horizontal lockup (dark background)
│   ├── logo-horizontal-light.svg     # Horizontal lockup (light background)
│   ├── logo-stacked.svg              # Stacked vertical lockup
│   ├── logo-stacked-dark.svg         # Stacked lockup (dark background)
│   ├── logo-stacked-light.svg        # Stacked lockup (light background)
│   ├── app-icon.svg                  # macOS 1024x1024 squircle application icon
│   ├── app-icon-dark.svg             # Dark mode application icon
│   └── app-icon-light.svg            # Light mode application icon
│
├── Multi-Resolution PNG Previews (`Design/Brand/png/`)
│   ├── symbol-[16, 32, 64, 128, 256, 512, 1024].png
│   ├── symbol-mono-black-[16, 32, 64, 128, 256, 512, 1024].png
│   ├── symbol-mono-white-[16, 32, 64, 128, 256, 512, 1024].png
│   ├── app-icon-[16, 32, 64, 128, 256, 512, 1024].png
│   ├── app-icon-light-[16, 32, 64, 128, 256, 512, 1024].png
│   ├── menubar-icon-black-[16, 18, 24, 32, 36, 48].png
│   ├── menubar-icon-white-[16, 18, 24, 32, 36, 48].png
│   ├── logo-horizontal-dark-[256, 512, 1024, 2048].png
│   ├── logo-horizontal-light-[256, 512, 1024, 2048].png
│   ├── logo-stacked-dark-[256, 512, 1024].png
│   └── logo-stacked-light-[256, 512, 1024].png
│
├── Documentation & Specifications
│   ├── BRAND_GUIDELINES.md           # This comprehensive brand manual
│   └── CONCEPT_EXPLORATION.md        # Concept exploration & evaluation matrix
```

---

## 10. Production Integration Guide

### macOS AppKit Status Item (`MenuBarController.swift`)
To load the menu bar icon natively as a template image:
```swift
if let iconUrl = Bundle.main.url(forResource: "menubar-icon", withExtension: "svg"),
   let image = NSImage(contentsOf: iconUrl) {
    image.isTemplate = true
    statusItem?.button?.image = image
} else {
    // Fallback to SF Symbol
    let fallback = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: "Flowback")
    fallback?.isTemplate = true
    statusItem?.button?.image = fallback
}
```

### Xcode Asset Catalog (`AppIcon.appiconset`)
To generate standard `.icns` or Xcode asset sets from `app-icon.svg`:
```bash
# Generate iconset folder
mkdir Flowback.iconset
sips -z 16 16     Design/Brand/png/app-icon-16.png   --out Flowback.iconset/icon_16x16.png
sips -z 32 32     Design/Brand/png/app-icon-32.png   --out Flowback.iconset/icon_16x16@2x.png
sips -z 32 32     Design/Brand/png/app-icon-32.png   --out Flowback.iconset/icon_32x32.png
sips -z 64 64     Design/Brand/png/app-icon-64.png   --out Flowback.iconset/icon_32x32@2x.png
sips -z 128 128   Design/Brand/png/app-icon-128.png  --out Flowback.iconset/icon_128x128.png
sips -z 256 256   Design/Brand/png/app-icon-256.png  --out Flowback.iconset/icon_128x128@2x.png
sips -z 256 256   Design/Brand/png/app-icon-256.png  --out Flowback.iconset/icon_256x256.png
sips -z 512 512   Design/Brand/png/app-icon-512.png  --out Flowback.iconset/icon_256x256@2x.png
sips -z 512 512   Design/Brand/png/app-icon-512.png  --out Flowback.iconset/icon_512x512.png
sips -z 1024 1024 Design/Brand/png/app-icon-1024.png --out Flowback.iconset/icon_512x512@2x.png

# Compile into native Apple ICNS
iconutil -c icns Flowback.iconset -o dist/Flowback.app/Contents/Resources/AppIcon.icns
```

### Markdown Documentation & GitHub README
```markdown
<p align="center">
  <img src="Docs/assets/flowback-banner.svg" alt="Flowback Banner" width="100%">
</p>
```
