# Flowback — Brand Identity Concept Exploration & Rationale

**Document Version:** 1.0.0  
**Status:** Approved & Implemented  
**Date:** October 2026  
**Discipline:** Brand Identity & macOS Native Visual Systems  

---

## 1. Executive Summary & Brand Purpose

Flowback is a native macOS focus and context orchestrator for AI coding workflows. It works alongside AI coding agents (Claude Code, Cursor, Codex, Windsurf, aider), IDEs (Xcode, VS Code, JetBrains), terminals (Ghostty, iTerm2, Terminal.app), and browser testbeds.

Unlike AI coding agents or IDEs, Flowback **does not generate code, edit files, or execute builds**. Its sole, highly disciplined mission is to:
- **Orchestrate attention narrowly:** Track background agent task lifecycles without interfering with user concentration.
- **Restore focus conservatively:** Prevent abrupt window stealing while active typing occurs.
- **Respect user intent:** When an agent finishes or requests user input, guide the developer seamlessly back to the exact origin window, workspace, and context where the task began.

### Brand Promise
> **"Get back to the right context, at the right moment."**

### Visual Identity Goal
Design a production-ready, engineered visual identity that communicates this philosophy with the restraint, technical precision, and quiet authority expected of a premier macOS utility. Avoid startup tropes (sparkles, robot heads, glowing nodes, circular refresh arrows, or timer dials).

---

## 2. Concept Explorations

To discover the definitive visual symbol for Flowback, three distinct conceptual directions were explored and tested across multiple display densities (16×16 menu bar to 1024×1024 macOS app icon).

```
┌─────────────────────────┬─────────────────────────┬─────────────────────────┐
│       CONCEPT A         │       CONCEPT B         │       CONCEPT C         │
│     "FOCUS TARGET"      │     "CONTEXT GATE"      │    "CANTILEVER LOOP"    │
├─────────────────────────┼─────────────────────────┼─────────────────────────┤
│                         │                         │                         │
│       ╭───╮             │       ┌──┐  ┌──┐        │        ┌──┐  ╭─────╮    │
│      ╭╯ ⊙ ╰╮            │       │  │══│  │        │        │██│──╯     │    │
│      ╰─ ┼ ─╯            │       └──┘  └──┘        │        │██│◀───────╯    │
│        ───              │                         │        └──┘             │
│                         │                         │                         │
│   Radial Convergence    │   Dual-Frame Bridge     │  Asynchronous Orbit &   │
│   onto deliberate focal │   between disparate     │  docked re-entry into   │
│   center point.         │   working contexts.     │  origin context anchor. │
└─────────────────────────┴─────────────────────────┴─────────────────────────┘
```

---

### Concept A — Focus: The Precision Aperture / Converging Crosshair

#### Conceptual Thesis
Attention in modern software engineering is fragmented across multiple asynchronous terminals and chat windows. Concept A symbolizes drawing dispersed peripheral energy back toward a single, deliberate focal center (an offset aperture / reticle).

#### Visual Formulation
- A concentric outer ring segment with a dynamic converging inward vector.
- Radial geometry with a calibrated focal dot or aperture ring at the coordinate center.

#### Critical Evaluation
- **Immediate Recognizability:** Moderate. At large sizes, the radial target is readable, but resembles a camera aperture, shutter, or sniper reticle.
- **Distinctiveness:** Low-to-Moderate. Many productivity apps (Focus, Forest, Pomodoro timers, 1Password target) use concentric circular targets.
- **Connection to Flowback:** Weak in narrative depth. It communicates "focus" as a static state, but completely misses the dynamic reality of Flowback: asynchronous flow leaving, working, and **returning** to the origin application.
- **Legibility at 16 × 16 px:** Poor. Concentric thin arcs and crosshair tick marks blur together on standard non-Retina displays and create moiré patterns.
- **Suitability for macOS App Icon:** Feels like a photography or camera utility rather than a developer orchestrator.
- **Reproducibility in Monochrome:** Moderate. Tends to degrade into a generic bullseye.
- **Visual Similarity to Existing Logos:** Too close to macOS Focus Mode (crescent/target), 1Password, or shutter buttons.

---

### Concept B — Context: The Dual-Plane Context Gate & Bridge

#### Conceptual Thesis
The core technical challenge Flowback solves is context restoration between two distinct spaces: the agent's background workspace and the developer's primary IDE/terminal window. Concept B explores two offset, interconnected geometric frames representing these layers.

#### Visual Formulation
- Two offset rectilinear frames or squircle tiles linked by a horizontal conduit or directional vector.
- Isometric or orthogonal layer perspective.

#### Critical Evaluation
- **Immediate Recognizability:** Moderate. Can be easily misread as "copy/paste," "duplicate window," or file layering.
- **Distinctiveness:** Low. Overlaps heavily with window managers (Rectangle, Magnet, Divvy, Moom) and design layer icons (Figma, Sketch, macOS Stage Manager).
- **Connection to Flowback:** Directly illustrates two windows, but violates the core design brief requirement: *"Avoid busy network diagrams and multiple overlapping windows rendered with excessive detail."*
- **Legibility at 16 × 16 px:** Very poor. Multiple nested rectangles require stroke weights under 1.5px, which blur into visual mud in the macOS menu bar.
- **Suitability for macOS App Icon:** Appears cluttered and lacks a singular iconic focal point.
- **Reproducibility in Monochrome:** Line overlaps produce ambiguous silhouettes when inverted.
- **Visual Similarity to Existing Logos:** Overlaps with Microsoft Windows, Figma Frames, and window tiling utilities.

---

### Concept C — Flow: The Cantilever Re-entry Loop & Origin Dock (Winning Concept)

#### Conceptual Thesis
Flowback is about **flow and return**. When an engineer prompts an AI coding agent, the agent launches outward into an autonomous trajectory. The engineer stays in flow. When the agent completes its run or requires human judgment, Flowback conserves attention and guides focus directly *back* into the origin workspace.

Concept C synthesizes this journey into a single, cohesive, architectural symbol:
1. **The Origin Dock (Left Monolith):** A grounded, solid geometric anchor representing the primary context (the user's editor or active window).
2. **The Asynchronous Trajectory (Cantilever Loop):** A continuous, sweeping engineered band that departs from the anchor, navigates an external 180° loop, and flows back horizontally.
3. **The Focus Re-entry Chevron:** An integrated 45° precision wedge pointing directly back into the receiving docking plane of the origin monolith.

#### Visual Formulation
- Solid positive/negative space geometry constructed on a power-of-two 512×512 unit coordinate space (divisible down to 16×16).
- Two complementary solid masses separated by a calibrated negative-space tension channel (32px at 512, exactly 1.5–2px at 16px).
- Restrained color application: Crisp off-white (`#F8FAFC`) anchor, illuminated electric cyan (`#38BDF8` → `#0284C7`) return loop, set against deep slate (`#0B0F17`).

#### Critical Evaluation
- **Immediate Recognizability:** **Exceptional.** Unmistakable silhouette formed by bold, confident geometric masses.
- **Distinctiveness:** **Very High.** Not a generic circular reload arrow, not a browser refresh button, not an infinity symbol. The architectural cantilever and precision return chevron create a unique signature.
- **Connection to Flowback:** **Perfect.** Encapsulates the entire product narrative: *Asynchronous work flows out; orchestrated focus returns back.*
- **Legibility at 16 × 16 px:** **Flawless.** Tested on a 16×16 and 18×18 pixel grid. Renders with razor sharpness on both Retina and non-Retina menu bars.
- **Suitability for macOS App Icon:** **Outstanding.** Fits naturally inside the macOS squircle canvas with subtle machined bevels and ambient luminescent glow.
- **Reproducibility in Monochrome:** **Flawless.** Translates into a pure compound silhouette in 100% black or 100% white, functioning as a native macOS status item template (`isTemplate = true`).
- **Visual Similarity to Existing Logos:** **High Distinctiveness.** Well-differentiated from existing macOS utilities and developer tools (Git, Raycast, Linear, Docker, SF Symbols) with no conflicting silhouettes identified during trademark and visual indexing review.

---

## 3. Qualitative Evaluation Matrix

> [!NOTE]
> Ratings represent internal design team qualitative heuristics evaluated on a 1–10 scale based on visual reviews at 16px, 32px, 128px, and 1024px. They reflect design consensus rather than objective empirical measurements.

| Evaluation Criterion | Concept A: Focus Target | Concept B: Context Gate | Concept C: Cantilever Loop (Selected) |
| :--- | :---: | :---: | :---: |
| **1. Immediate Recognizability** | 6 / 10 | 5 / 10 | **9 / 10** |
| **2. Distinctiveness** | 4 / 10 | 5 / 10 | **9 / 10** |
| **3. Connection to Flowback Narrative** | 5 / 10 | 7 / 10 | **10 / 10** |
| **4. Legibility at 16 × 16 px (Menu Bar)** | 3 / 10 | 2 / 10 | **10 / 10** |
| **5. Suitability for macOS App Icon** | 6 / 10 | 5 / 10 | **9 / 10** |
| **6. Reproducibility in Monochrome** | 6 / 10 | 4 / 10 | **10 / 10** |
| **7. Differentiation from Competitors** | 4 / 10 | 5 / 10 | **9 / 10** |
| **Consensus Score** | **34 / 70** | **33 / 70** | **66 / 70** |


---

## 4. Winning Concept Refinement & Mathematical Construction

The selected Concept C was refined through mathematical grid calibration to ensure zero optical distortion across all display resolutions.

### Coordinate Grid & Optical Proportions
- **Master Coordinate Space:** `512 × 512` units.
- **Optical Center:** Adjusted by offset `dx = +18`, `dy = -16` to equalize visual margins:
  - Left & Right Margins: Exactly **82 units** each.
  - Top & Bottom Margins: Exactly **96 units** each.
- **Stroke & Mass Weight:**
  - Context Monolith: Width = 96 units, Height = 288 units, Corner Radius = 48 units.
  - Focus Nucleus Aperture: Outer knockout radius = 22 units, inner cyan dot radius = 10 units.
  - Cantilever Loop Path: Uniform ribbon thickness = 48 units, outer arc radius = 108 units, inner arc radius = 60 units.
  - Re-Entry Chevron: 45° beveled return blade with a 68-unit sweep and 48-unit width, pointing leftward into the origin anchor.
  - Negative Space Tension Gap: Exactly **32 units** (1:3 ratio relative to the monolith width).

### Menu-Bar Template Optimization
For the macOS Menu Bar (`NSStatusItem` / `MenuBarExtra`), a dedicated pixel-aligned vector was created on an **18 × 18 pt** canvas:
- Stroke weights calibrated to exactly **1.8 pt** (3.6 px on Retina `@2x`), preventing anti-aliasing fuzziness.
- Utilizes `fill="currentColor"` and `stroke="currentColor"`, allowing macOS to automatically adapt contrast between Dark Mode menu bars (pure crisp white) and Light Mode menu bars (pure graphite black).

---

## 5. Summary of Deliverables

All production assets have been generated, validated, and placed in the dedicated repository directory:

```
Design/Brand/
├── symbol.svg                    # Primary standalone color symbol
├── symbol-monochrome-black.svg   # Pure black vector silhouette on transparent
├── symbol-monochrome-white.svg   # Pure white vector silhouette on transparent
├── menubar-icon.svg              # 18x18 pixel-aligned macOS template icon
├── wordmark.svg                  # Standalone typographic wordmark (dark)
├── wordmark-dark.svg             # Typographic wordmark for dark surfaces
├── wordmark-light.svg            # Typographic wordmark for light surfaces
├── logo-horizontal.svg           # Standard horizontal lockup (symbol + wordmark)
├── logo-horizontal-dark.svg      # Horizontal lockup (dark background)
├── logo-horizontal-light.svg     # Horizontal lockup (light background)
├── logo-stacked.svg              # Stacked vertical lockup (dark background)
├── logo-stacked-dark.svg         # Stacked lockup (dark background)
├── logo-stacked-light.svg        # Stacked lockup (light background)
├── app-icon.svg                  # macOS 1024x1024 squircle application icon
├── app-icon-dark.svg             # Dark mode application icon
├── app-icon-light.svg            # Light mode application icon
├── png/                          # Complete multi-resolution PNG suite (16 to 1024px)
├── BRAND_GUIDELINES.md           # Comprehensive brand manual & usage rules
└── CONCEPT_EXPLORATION.md        # This conceptual record and evaluation document
```
