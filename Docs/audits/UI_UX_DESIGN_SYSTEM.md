# Flowback — Unified Native Design System

**Date:** October 2026  
**Auditor / Architect:** Principal macOS Product Designer & Design Systems Engineer  
**Scope:** All UI modules in `Sources/FlowbackUI`  

---

## 1. Design Principles

Flowback’s visual design system follows five core principles:

1. **Native macOS Citizenship:** Uses Apple HIG conventions, SF Symbols, continuous rounded rectangles, and standard macOS control sizes.
2. **Tabular Information Density:** Coding agent orchestration requires dense, scannable technical metadata (PIDs, workspace paths, timings, provider tokens) without visual clutter.
3. **Unambiguous State Communication (WCAG AA):** Statuses must never rely solely on color. Every status badge pairs an adaptive luminance color with a standardized SF Symbol glyph and high-contrast perimeter.
4. **Card-Based Visual Anchors:** Related controls and telemetry are grouped into rounded card containers (`cornerRadius: 14pt`) with subtle, contrast-adaptive borders.
5. **Actionable State Recovery:** Every empty or degraded state provides concise explanations and immediate recovery action buttons.

---

## 2. Design Tokens Reference

### 2.1 Spacing Scale

All layout padding and gaps must strictly adhere to the documented spacing scale:

```swift
public enum FlowbackSpacing {
    /// 2pt: Micro-adjustments and icon-to-badge gaps
    public static let xxs: CGFloat = 2
    /// 4pt: Badge internal vertical padding, tight label gaps
    public static let xs: CGFloat = 4
    /// 8pt: Content-to-subheading gap, icon-to-text spacing
    public static let sm: CGFloat = 8
    /// 12pt: List item spacing, card internal gap, control spacing
    public static let md: CGFloat = 12
    /// 16pt: Card internal padding, section row spacing
    public static let lg: CGFloat = 16
    /// 20pt: Major section separation, form insets
    public static let xl: CGFloat = 20
    /// 24pt: Standard page horizontal margins and header offsets
    public static let xxl: CGFloat = 24
}
```

---

### 2.2 Corner Radii

Flowback standardizes on continuous curvature (`RoundedRectangle(cornerRadius:style: .continuous)`):

```swift
public enum FlowbackRadius {
    /// 6pt: Inline chips, badges, and code tags
    public static let badge: CGFloat = 6
    /// 8pt: Standard buttons, text fields, and icon tiles
    public static let control: CGFloat = 8
    /// 12pt: Nested containers and alert banners
    public static let subcard: CGFloat = 12
    /// 14pt: Primary section cards and modal surfaces
    public static let card: CGFloat = 14
}
```

---

### 2.3 Semantic Surfaces & Colors

All background fills, borders, and status colors adapt to both **Color Scheme** (Light/Dark) and **macOS Accessibility Increase Contrast**:

| Token Name | Light Appearance | Dark Appearance | Increase Contrast Adaptation |
| :--- | :--- | :--- | :--- |
| `cardFill` | `Color.white.opacity(0.70)` | `Color(white: 0.14).opacity(0.80)` | Solid background without transparency |
| `cardBorder` | `Color.black.opacity(0.10)` | `Color.white.opacity(0.12)` | Opacity increases to 0.30 (light) / 0.35 (dark); line width increases to 1.2pt |
| `controlFill` | `Color.black.opacity(0.05)` | `Color.white.opacity(0.08)` | Opacity increases to 0.12 |
| `iconTileFill` | Tinted background with 12% opacity | Tinted background with 22% opacity | Stroke added to icon perimeter |

---

### 2.4 Accessible Status Palette & Glyphs

Every `AgentState` maps to a WCAG AA verified color and an unambiguous SF Symbol glyph:

| Agent State | Semantic Color (Light / Dark) | SF Symbol Glyph | Meaning |
| :--- | :--- | :--- | :--- |
| `.running` | `#0D61C7` (Blue) / `.blue` | `arrow.triangle.2.circlepath` | Active background task |
| `.starting` | `#0D61C7` (Blue) / `.blue` | `rays` | Initializing session |
| `.waiting` | `#B85105` (Orange) / `.orange` | `clock.arrow.circlepath` | Waiting for user interaction |
| `.permissionRequired` | `#B85105` (Orange) / `.orange` | `hand.raised.fill` | Security authorization pending |
| `.completed` | `#147B38` (Green) / `.green` | `checkmark.circle.fill` | Completed successfully |
| `.failed` | `#D31A26` (Red) / `.red` | `xmark.circle.fill` | Agent encountered an error |
| `.cancelled` | `.secondary` / `.secondary` | `slash.circle` | Stopped by user |
| `.paused` | `.secondary` / `.secondary` | `pause.circle` | Temporarily halted |

---

## 3. Reusable Component Conventions

### 3.1 `FlowbackCard`
A versatile card wrapper supporting optional title, custom padding, and automatic contrast border overlay.

### 3.2 `FlowbackSettingsCard` & `FlowbackSettingsRow`
Emulates the best qualities of Vorssaint’s settings architecture:
- 28x28pt tinted SF Symbol icon tile.
- Bold primary title and descriptive secondary caption.
- Right-aligned interactive control (Toggle, Picker, Slider, or Button).
- Subtle divider line between items.

### 3.3 `FlowbackEmptyState`
Clean, structured empty state containing:
- 36pt centered SF Symbol with secondary tint.
- Headline and subheadline explanation.
- Actionable button (e.g. "Refresh Scan", "Add Application") for instant recovery.

### 3.4 `StatusBadge`
Capsule-style status indicator containing both the state's icon glyph and textual description, rendered with adaptive high-contrast borders.
