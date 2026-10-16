#!/usr/bin/env swift
import Foundation
import AppKit
import PDFKit

// ==============================================================================
// Flowback Brand Identity Asset Generator
// ==============================================================================
// Generates all production vector SVGs, vector PDF templates, multi-resolution
// PNG previews, and Apple AppIcon.icns from exact mathematical geometry.
// ==============================================================================

let fileManager = FileManager.default
let projectRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let brandDir = projectRoot.appendingPathComponent("Design/Brand")
let pngDir = brandDir.appendingPathComponent("png")
let docsAssetsDir = projectRoot.appendingPathComponent("Docs/assets")
let websiteAssetsDir = projectRoot.appendingPathComponent("Website/assets")

try? fileManager.createDirectory(at: pngDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: docsAssetsDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: websiteAssetsDir, withIntermediateDirectories: true)

print("==================================================")
print("Flowback Brand Identity Asset Generator")
print("==================================================")

// ------------------------------------------------------------------------------
// 1. Vector Geometry Definitions
// ------------------------------------------------------------------------------

// Compound Anchor Monolith with Center Hole (evenodd fill rule)
// Monolith bounds in local coordinates: x: 64..160 (w:96), y: 112..400 (h:288), rx: 48
// Center Hole: cx: 112, cy: 256, r: 22
let anchorCompoundPathData = """
M 112 112
A 48 48 0 0 1 160 160
L 160 352
A 48 48 0 0 1 112 400
A 48 48 0 0 1 64 352
L 64 160
A 48 48 0 0 1 112 112
Z
M 112 256
m -22, 0
a 22 22 0 0 1 44 0
a 22 22 0 0 1 -44 0
Z

"""

// Cantilever Return Loop Ribbon (Solid Path)
let loopPathData = """
M 160 148
L 304 148
C 363.6 148 412 196.4 412 256
C 412 315.6 363.6 364 304 364
L 244 364
L 244 316
L 304 316
C 337.1 316 364 289.1 364 256
C 364 222.9 337.1 196 304 196
L 160 196
Z
"""

// Precision Re-Entry Chevron (Solid Path)
let chevronPathData = """
M 264 296
L 196 364
L 264 432
L 284 412
L 236 364
L 284 316
Z
"""

// ------------------------------------------------------------------------------
// 2. Master SVG Templates
// ------------------------------------------------------------------------------

// A. Primary Standalone Symbol (Color, Transparent Canvas)
let symbolColorSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <linearGradient id="fbFlowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#38BDF8"/>
      <stop offset="100%" stop-color="#0284C7"/>
    </linearGradient>
    <linearGradient id="fbAnchorGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#E2E8F0"/>
    </linearGradient>
    <filter id="fbSymbolShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="6" stdDeviation="12" flood-color="#0284C7" flood-opacity="0.25"/>
    </filter>
  </defs>
  <g transform="translate(18, -16)">
    <!-- Origin Context Anchor with Compound Focus Aperture -->
    <path fill-rule="evenodd" fill="url(#fbAnchorGrad)" d="\(anchorCompoundPathData)"/>
    <!-- Illuminated Focus Dot inside Aperture -->
    <circle cx="112" cy="256" r="10" fill="#38BDF8"/>
    <!-- Asynchronous Return Loop -->
    <path d="\(loopPathData)" fill="url(#fbFlowGrad)" filter="url(#fbSymbolShadow)"/>
    <!-- Precision Re-Entry Chevron -->
    <path d="\(chevronPathData)" fill="#38BDF8"/>
  </g>
</svg>
"""

// B. Monochrome Black Symbol (Pure Black on Transparent)
let symbolMonoBlackSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <g transform="translate(18, -16)" fill="#000000">
    <!-- Anchor with Compound Knockout Hole (Zero Mask Dependency) -->
    <path fill-rule="evenodd" d="\(anchorCompoundPathData)"/>
    <path d="\(loopPathData)"/>
    <path d="\(chevronPathData)"/>
  </g>
</svg>
"""

// C. Monochrome White Symbol (Pure White on Transparent)
let symbolMonoWhiteSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <g transform="translate(18, -16)" fill="#FFFFFF">
    <!-- Anchor with Compound Knockout Hole (Zero Mask Dependency) -->
    <path fill-rule="evenodd" d="\(anchorCompoundPathData)"/>
    <path d="\(loopPathData)"/>
    <path d="\(chevronPathData)"/>
  </g>
</svg>
"""

// D. Dedicated macOS Menu Bar Icon (18x18 pt Template Canvas)
// Pillar: x=2.5..6.0, y=3.5..14.5, rx=1.75; Aperture hole: cx=4.25, cy=9.0, r=0.9
let menubarIconSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18">
  <!-- Context Pillar with Compound Hole (evenodd) -->
  <path fill-rule="evenodd" fill="#000000" d="
    M 4.25 3.5
    A 1.75 1.75 0 0 1 6.0 5.25
    L 6.0 12.75
    A 1.75 1.75 0 0 1 4.25 14.5
    A 1.75 1.75 0 0 1 2.5 12.75
    L 2.5 5.25
    A 1.75 1.75 0 0 1 4.25 3.5
    Z
    M 4.25 9.0
    m -0.9, 0
    a 0.9 0.9 0 0 1 1.8 0
    a 0.9 0.9 0 0 1 -1.8 0
    Z"/>

  <!-- Return Trajectory Loop -->
  <path d="M 6 5 L 11.5 5 C 13.7 5 15.5 6.8 15.5 9 C 15.5 11.2 13.7 13 11.5 13 L 7.5 13" 
        fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
  <!-- Focus Re-Entry Chevron -->
  <path d="M 9.5 11 L 7 13 L 9.5 15" 
        fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
"""

// E. macOS Application Icon (1024x1024 Canvas, 824x824 Squircle Base, 1.55x Scaled Mark)
let appIconSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <!-- Background Slate Gradient (macOS Upper Lighting) -->
    <linearGradient id="bodyGrad" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#1E2638"/>
      <stop offset="40%" stop-color="#141B29"/>
      <stop offset="100%" stop-color="#0A0E17"/>
    </linearGradient>

    <!-- Beveled Outer Rim Highlight -->
    <linearGradient id="rimGrad" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.32"/>
      <stop offset="30%" stop-color="#94A3B8" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.6"/>
    </linearGradient>

    <!-- Flow Loop Electric Gradient -->
    <linearGradient id="cyanFlow" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#38BDF8"/>
      <stop offset="50%" stop-color="#0EA5E9"/>
      <stop offset="100%" stop-color="#0284C7"/>
    </linearGradient>

    <!-- Anchor Solid Monolith Gradient -->
    <linearGradient id="anchorMetal" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="60%" stop-color="#F1F5F9"/>
      <stop offset="100%" stop-color="#CBD5E1"/>
    </linearGradient>

    <!-- Ambient Glow from Return Loop -->
    <filter id="ambientGlow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="36" result="blur"/>
      <feComposite in="SourceGraphic" in2="blur" operator="over"/>
    </filter>

    <!-- macOS Icon Drop Shadow (Apple Sonoma/Sequoia HIG Spec) -->
    <filter id="macosShadow" x="-10%" y="-10%" width="125%" height="130%">
      <feDropShadow dx="0" dy="28" stdDeviation="32" flood-color="#000000" flood-opacity="0.55"/>
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>

  <!-- 1. Native macOS Squircle Base (824x824 centered at 512,512, rx/ry 185) -->
  <rect x="100" y="100" width="824" height="824" rx="185" ry="185" 
        fill="url(#bodyGrad)" 
        stroke="url(#rimGrad)" 
        stroke-width="3" 
        filter="url(#macosShadow)"/>

  <!-- 2. Subtle Precision Alignment Guides (Technical macOS Instrument aesthetic) -->
  <circle cx="512" cy="512" r="300" fill="none" stroke="#334155" stroke-width="1.5" stroke-dasharray="4 8" opacity="0.35"/>
  <circle cx="512" cy="512" r="200" fill="none" stroke="#334155" stroke-width="1.5" stroke-dasharray="6 6" opacity="0.25"/>
  <line x1="212" y1="512" x2="812" y2="512" stroke="#334155" stroke-width="1" stroke-dasharray="3 9" opacity="0.2"/>
  <line x1="512" y1="212" x2="512" y2="812" stroke="#334155" stroke-width="1" stroke-dasharray="3 9" opacity="0.2"/>

  <!-- 3. Primary Flowback Mark (Scaled 1.55x for 65% Squircle Width Occupancy) -->
  <g transform="translate(512, 512) scale(1.55) translate(-238, -272)">
    <!-- Ambient cyan back-glow -->
    <path d="\(loopPathData)" fill="#38BDF8" opacity="0.25" filter="url(#ambientGlow)"/>

    <!-- Left Context Anchor with Focus Aperture -->
    <path fill-rule="evenodd" fill="url(#anchorMetal)" d="\(anchorCompoundPathData)"/>
    <circle cx="112" cy="256" r="10" fill="#38BDF8"/>
    
    <!-- Sweeping Cantilever Loop (Flow) -->
    <path d="\(loopPathData)" fill="url(#cyanFlow)"/>
          
    <!-- Precision Return Chevron (Re-entry Vector) -->
    <path d="\(chevronPathData)" fill="#38BDF8"/>
  </g>
</svg>
"""

// F. macOS Light Mode Application Icon
let appIconLightSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="bodyGradLight" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="50%" stop-color="#F8FAFC"/>
      <stop offset="100%" stop-color="#E2E8F0"/>
    </linearGradient>
    <linearGradient id="rimGradLight" x1="50%" y1="0%" x2="50%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.8"/>
      <stop offset="100%" stop-color="#CBD5E1" stop-opacity="0.4"/>
    </linearGradient>
    <filter id="macosShadowLight" x="-10%" y="-10%" width="125%" height="130%">
      <feDropShadow dx="0" dy="24" stdDeviation="28" flood-color="#0F172A" flood-opacity="0.18"/>
      <feDropShadow dx="0" dy="6" stdDeviation="10" flood-color="#0F172A" flood-opacity="0.12"/>
    </filter>
  </defs>

  <rect x="100" y="100" width="824" height="824" rx="185" ry="185" 
        fill="url(#bodyGradLight)" 
        stroke="url(#rimGradLight)" 
        stroke-width="3" 
        filter="url(#macosShadowLight)"/>

  <circle cx="512" cy="512" r="300" fill="none" stroke="#E2E8F0" stroke-width="1.5" stroke-dasharray="4 8"/>
  <circle cx="512" cy="512" r="200" fill="none" stroke="#E2E8F0" stroke-width="1.5" stroke-dasharray="6 6"/>

  <g transform="translate(512, 512) scale(1.55) translate(-238, -272)">
    <path fill-rule="evenodd" fill="#0F172A" d="\(anchorCompoundPathData)"/>
    <circle cx="112" cy="256" r="10" fill="#0284C7"/>
    <path d="\(loopPathData)" fill="#0284C7"/>
    <path d="\(chevronPathData)" fill="#0284C7"/>
  </g>
</svg>
"""

// G. Wordmarks & Centered Lockups
let wordmarkDarkSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 110" width="460" height="110">
  <defs>
    <linearGradient id="wmGradDark" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#E2E8F0"/>
    </linearGradient>
  </defs>
  <text x="0" y="80" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', 'Segoe UI', system-ui, sans-serif" 
        font-size="88" 
        font-weight="650" 
        letter-spacing="-2.2" 
        fill="url(#wmGradDark)">Flowback</text>
</svg>
"""

let wordmarkLightSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 110" width="460" height="110">
  <text x="0" y="80" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', 'Segoe UI', system-ui, sans-serif" 
        font-size="88" 
        font-weight="650" 
        letter-spacing="-2.2" 
        fill="#0B0F17">Flowback</text>
</svg>
"""

let logoHorizontalDarkSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 160" width="640" height="160">
  <defs>
    <linearGradient id="hFlowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#38BDF8"/>
      <stop offset="100%" stop-color="#0284C7"/>
    </linearGradient>
    <linearGradient id="hTextGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#E2E8F0"/>
    </linearGradient>
    <filter id="hShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#0284C7" flood-opacity="0.3"/>
    </filter>
  </defs>
  
  <!-- Centered Lockup Group: Content Width = 520px, Canvas = 640px (Offset dx=60) -->
  <g transform="translate(60, 0)">
    <!-- Primary Symbol (Height: 104, Width: 104 at x=0, y=28) -->
    <g transform="translate(0, 28) scale(0.2031)">
      <g transform="translate(18, -16)">
        <path fill-rule="evenodd" fill="#FFFFFF" d="\(anchorCompoundPathData)"/>
        <circle cx="112" cy="256" r="10" fill="#38BDF8"/>
        <path d="\(loopPathData)" fill="url(#hFlowGrad)" filter="url(#hShadow)"/>
        <path d="\(chevronPathData)" fill="#38BDF8"/>
      </g>
    </g>
    
    <!-- Wordmark -->
    <text x="132" y="103" 
          font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', system-ui, sans-serif" 
          font-size="64" 
          font-weight="650" 
          letter-spacing="-1.8" 
          fill="url(#hTextGrad)">Flowback</text>
          
    <!-- Subtitle Tag -->
    <rect x="440" y="70" width="72" height="26" rx="6" fill="#1E293B" stroke="#334155" stroke-width="1"/>
    <text x="476" y="87" 
          font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif" 
          font-size="11" 
          font-weight="700" 
          letter-spacing="0.8" 
          fill="#38BDF8" 
          text-anchor="middle">macOS</text>
  </g>
</svg>
"""

let logoHorizontalLightSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 160" width="640" height="160">
  <defs>
    <linearGradient id="hlFlowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0284C7"/>
      <stop offset="100%" stop-color="#0369A1"/>
    </linearGradient>
    <filter id="hlShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#0284C7" flood-opacity="0.2"/>
    </filter>
  </defs>
  
  <g transform="translate(60, 0)">
    <g transform="translate(0, 28) scale(0.2031)">
      <g transform="translate(18, -16)">
        <path fill-rule="evenodd" fill="#0F172A" d="\(anchorCompoundPathData)"/>
        <circle cx="112" cy="256" r="10" fill="#0284C7"/>
        <path d="\(loopPathData)" fill="url(#hlFlowGrad)" filter="url(#hlShadow)"/>
        <path d="\(chevronPathData)" fill="#0284C7"/>
      </g>
    </g>
    
    <text x="132" y="103" 
          font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', system-ui, sans-serif" 
          font-size="64" 
          font-weight="650" 
          letter-spacing="-1.8" 
          fill="#0F172A">Flowback</text>
          
    <rect x="440" y="70" width="72" height="26" rx="6" fill="#F1F5F9" stroke="#CBD5E1" stroke-width="1"/>
    <text x="476" y="87" 
          font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif" 
          font-size="11" 
          font-weight="700" 
          letter-spacing="0.8" 
          fill="#0284C7" 
          text-anchor="middle">macOS</text>
  </g>
</svg>
"""

let logoStackedDarkSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 400" width="360" height="400">
  <defs>
    <linearGradient id="stFlowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#38BDF8"/>
      <stop offset="100%" stop-color="#0284C7"/>
    </linearGradient>
    <linearGradient id="stTextGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#E2E8F0"/>
    </linearGradient>
    <filter id="stShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="8" stdDeviation="16" flood-color="#0284C7" flood-opacity="0.3"/>
    </filter>
  </defs>
  
  <g transform="translate(80, 40) scale(0.3906)">
    <g transform="translate(18, -16)">
      <path fill-rule="evenodd" fill="#FFFFFF" d="\(anchorCompoundPathData)"/>
      <circle cx="112" cy="256" r="10" fill="#38BDF8"/>
      <path d="\(loopPathData)" fill="url(#stFlowGrad)" filter="url(#stShadow)"/>
      <path d="\(chevronPathData)" fill="#38BDF8"/>
    </g>
  </g>
  
  <text x="180" y="300" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', system-ui, sans-serif" 
        font-size="52" 
        font-weight="650" 
        letter-spacing="-1.4" 
        text-anchor="middle"
        fill="url(#stTextGrad)">Flowback</text>
        
  <text x="180" y="334" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif" 
        font-size="14" 
        font-weight="500" 
        letter-spacing="0.5" 
        text-anchor="middle"
        fill="#94A3B8">Focus &amp; Context Orchestrator</text>
</svg>
"""

let logoStackedLightSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 400" width="360" height="400">
  <defs>
    <linearGradient id="stlFlowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0284C7"/>
      <stop offset="100%" stop-color="#0369A1"/>
    </linearGradient>
    <filter id="stlShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="6" stdDeviation="12" flood-color="#0284C7" flood-opacity="0.2"/>
    </filter>
  </defs>
  
  <g transform="translate(80, 40) scale(0.3906)">
    <g transform="translate(18, -16)">
      <path fill-rule="evenodd" fill="#0F172A" d="\(anchorCompoundPathData)"/>
      <circle cx="112" cy="256" r="10" fill="#0284C7"/>
      <path d="\(loopPathData)" fill="url(#stlFlowGrad)" filter="url(#stlShadow)"/>
      <path d="\(chevronPathData)" fill="#0284C7"/>
    </g>
  </g>
  
  <text x="180" y="300" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter', system-ui, sans-serif" 
        font-size="52" 
        font-weight="650" 
        letter-spacing="-1.4" 
        text-anchor="middle"
        fill="#0F172A">Flowback</text>
        
  <text x="180" y="334" 
        font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif" 
        font-size="14" 
        font-weight="500" 
        letter-spacing="0.5" 
        text-anchor="middle"
        fill="#64748B">Focus &amp; Context Orchestrator</text>
</svg>
"""

// ------------------------------------------------------------------------------
// 3. Write SVGs to Disk
// ------------------------------------------------------------------------------

let svgList: [(String, String)] = [
    ("symbol.svg", symbolColorSVG),
    ("symbol-monochrome-black.svg", symbolMonoBlackSVG),
    ("symbol-monochrome-white.svg", symbolMonoWhiteSVG),
    ("menubar-icon.svg", menubarIconSVG),
    ("wordmark.svg", wordmarkDarkSVG),
    ("wordmark-dark.svg", wordmarkDarkSVG),
    ("wordmark-light.svg", wordmarkLightSVG),
    ("logo-horizontal.svg", logoHorizontalDarkSVG),
    ("logo-horizontal-dark.svg", logoHorizontalDarkSVG),
    ("logo-horizontal-light.svg", logoHorizontalLightSVG),
    ("logo-stacked.svg", logoStackedDarkSVG),
    ("logo-stacked-dark.svg", logoStackedDarkSVG),
    ("logo-stacked-light.svg", logoStackedLightSVG),
    ("app-icon.svg", appIconSVG),
    ("app-icon-dark.svg", appIconSVG),
    ("app-icon-light.svg", appIconLightSVG)
]

for (name, content) in svgList {
    let url = brandDir.appendingPathComponent(name)
    do {
        try content.write(to: url, atomically: true, encoding: .utf8)
        print("✓ Wrote SVG: \(name)")
    } catch {
        fputs("ERROR writing \(name): \(error)\n", stderr)
        exit(1)
    }
}

// ------------------------------------------------------------------------------
// 4. Generate Native PDF Vector Template for Menu Bar
// ------------------------------------------------------------------------------
func generatePDF(svgContent: String, outputUrl: URL, width: Double, height: Double) {
    guard let data = svgContent.data(using: .utf8),
          let img = NSImage(data: data) else {
        fputs("ERROR creating NSImage for PDF\n", stderr)
        exit(1)
    }
    
    let pdfData = NSMutableData()
    var mediaBox = NSRect(x: 0, y: 0, width: width, height: height)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fputs("ERROR creating PDF CGContext\n", stderr)
        exit(1)
    }
    
    let nsc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsc
    ctx.beginPDFPage(nil)
    img.draw(in: mediaBox)
    ctx.endPDFPage()
    ctx.closePDF()
    NSGraphicsContext.restoreGraphicsState()
    
    pdfData.write(to: outputUrl, atomically: true)
    print("✓ Wrote Vector PDF Template: \(outputUrl.lastPathComponent) (\(pdfData.length) bytes)")
}

generatePDF(svgContent: menubarIconSVG, outputUrl: brandDir.appendingPathComponent("menubar-icon.pdf"), width: 18, height: 18)

// ------------------------------------------------------------------------------
// 5. Render Multi-Resolution PNG Previews Directly from Vectors
// ------------------------------------------------------------------------------
func renderPNG(svgString: String, width: Int, height: Int, outputUrl: URL) {
    guard let data = svgString.data(using: .utf8),
          let image = NSImage(data: data) else {
        fputs("ERROR: Failed to parse SVG for \(outputUrl.lastPathComponent)\n", stderr)
        exit(1)
    }
    
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("ERROR: Failed to allocate NSBitmapImageRep for \(outputUrl.lastPathComponent)\n", stderr)
        exit(1)
    }
    
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fputs("ERROR: Failed to get NSGraphicsContext for \(outputUrl.lastPathComponent)\n", stderr)
        exit(1)
    }
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("ERROR: Failed to encode PNG for \(outputUrl.lastPathComponent)\n", stderr)
        exit(1)
    }
    
    do {
        try pngData.write(to: outputUrl)
    } catch {
        fputs("ERROR: Failed to write PNG \(outputUrl.lastPathComponent): \(error)\n", stderr)
        exit(1)
    }
}

print("\n--- Generating Multi-Resolution PNGs ---")
let standardSizes = [16, 32, 64, 128, 256, 512, 1024]

// Standalone Symbol PNGs
for s in standardSizes {
    renderPNG(svgString: symbolColorSVG, width: s, height: s, outputUrl: pngDir.appendingPathComponent("symbol-\(s).png"))
    renderPNG(svgString: symbolMonoBlackSVG, width: s, height: s, outputUrl: pngDir.appendingPathComponent("symbol-mono-black-\(s).png"))
    renderPNG(svgString: symbolMonoWhiteSVG, width: s, height: s, outputUrl: pngDir.appendingPathComponent("symbol-mono-white-\(s).png"))
}

// App Icon PNGs (1.55x scaled mark)
for s in standardSizes {
    renderPNG(svgString: appIconSVG, width: s, height: s, outputUrl: pngDir.appendingPathComponent("app-icon-\(s).png"))
    renderPNG(svgString: appIconLightSVG, width: s, height: s, outputUrl: pngDir.appendingPathComponent("app-icon-light-\(s).png"))
}

// Menu Bar Icon PNGs
for s in [16, 18, 24, 32, 36, 48] {
    renderPNG(svgString: menubarIconSVG, width: s, height: s, outputUrl: pngDir.appendingPathComponent("menubar-icon-black-\(s).png"))
    renderPNG(svgString: menubarIconSVG.replacingOccurrences(of: "#000000", with: "#FFFFFF"), 
              width: s, height: s, outputUrl: pngDir.appendingPathComponent("menubar-icon-white-\(s).png"))
}

// Lockup PNGs
for s in [256, 512, 1024, 2048] {
    let h = s * 160 / 640
    renderPNG(svgString: logoHorizontalDarkSVG, width: s, height: h, outputUrl: pngDir.appendingPathComponent("logo-horizontal-dark-\(s).png"))
    renderPNG(svgString: logoHorizontalLightSVG, width: s, height: h, outputUrl: pngDir.appendingPathComponent("logo-horizontal-light-\(s).png"))
}

for s in [256, 512, 1024] {
    let h = s * 400 / 360
    renderPNG(svgString: logoStackedDarkSVG, width: s, height: h, outputUrl: pngDir.appendingPathComponent("logo-stacked-dark-\(s).png"))
    renderPNG(svgString: logoStackedLightSVG, width: s, height: h, outputUrl: pngDir.appendingPathComponent("logo-stacked-light-\(s).png"))
}
print("✓ Rendered 61 multi-resolution PNG assets.")

// ------------------------------------------------------------------------------
// 6. Compile Native Apple ICNS
// ------------------------------------------------------------------------------
print("\n--- Compiling Apple AppIcon.icns ---")
let iconsetDir = projectRoot.appendingPathComponent("Flowback.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSpecs: [(String, Int, Int)] = [
    ("icon_16x16.png", 16, 16),
    ("icon_16x16@2x.png", 32, 32),
    ("icon_32x32.png", 32, 32),
    ("icon_32x32@2x.png", 64, 64),
    ("icon_128x128.png", 128, 128),
    ("icon_128x128@2x.png", 256, 256),
    ("icon_256x256.png", 256, 256),
    ("icon_256x256@2x.png", 512, 512),
    ("icon_512x512.png", 512, 512),
    ("icon_512x512@2x.png", 1024, 1024)
]

for (filename, w, h) in iconSpecs {
    let target = iconsetDir.appendingPathComponent(filename)
    renderPNG(svgString: appIconSVG, width: w, height: h, outputUrl: target)
}

let icnsTarget = brandDir.appendingPathComponent("AppIcon.icns")
let iconutilTask = Process()
iconutilTask.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilTask.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsTarget.path]
do {
    try iconutilTask.run()
    iconutilTask.waitUntilExit()
    if iconutilTask.terminationStatus != 0 {
        fputs("ERROR: iconutil failed with code \(iconutilTask.terminationStatus)\n", stderr)
        exit(1)
    }
    print("✓ Successfully compiled: \(icnsTarget.lastPathComponent)")
} catch {
    fputs("ERROR running iconutil: \(error)\n", stderr)
    exit(1)
}
try? fileManager.removeItem(at: iconsetDir)

// ------------------------------------------------------------------------------
// 7. Update Docs and Website Assets
// ------------------------------------------------------------------------------
print("\n--- Updating Docs and Website Assets ---")
try? fileManager.copyItem(at: brandDir.appendingPathComponent("app-icon.svg"), to: docsAssetsDir.appendingPathComponent("flowback-icon.svg"))
if fileManager.fileExists(atPath: docsAssetsDir.appendingPathComponent("flowback-icon.svg").path) {
    try? fileManager.removeItem(at: docsAssetsDir.appendingPathComponent("flowback-icon.svg"))
    try? fileManager.copyItem(at: brandDir.appendingPathComponent("app-icon.svg"), to: docsAssetsDir.appendingPathComponent("flowback-icon.svg"))
}
if fileManager.fileExists(atPath: websiteAssetsDir.appendingPathComponent("flowback-icon.svg").path) {
    try? fileManager.removeItem(at: websiteAssetsDir.appendingPathComponent("flowback-icon.svg"))
    try? fileManager.copyItem(at: brandDir.appendingPathComponent("app-icon.svg"), to: websiteAssetsDir.appendingPathComponent("flowback-icon.svg"))
}
print("✓ Synced app-icon.svg to Docs/assets and Website/assets.")

print("\n==================================================")
print("Asset generation complete with ZERO errors.")
print("==================================================")
