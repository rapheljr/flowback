#!/usr/bin/env swift
import Foundation
import AppKit
import PDFKit

// ==============================================================================
// Flowback Brand Identity Asset Integrity Verifier
// ==============================================================================
// Audits all brand assets against Apple HIG, WCAG 2.1 contrast formulas,
// bitmap dimensions, vector geometry alignment, and file integrity.
// ==============================================================================

let fileManager = FileManager.default
let projectRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let brandDir = projectRoot.appendingPathComponent("Design/Brand")
let pngDir = brandDir.appendingPathComponent("png")

var failures = 0
var passes = 0

func assertTest(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
        passes += 1
    } else {
        fputs("  ✗ FAILED: \(message)\n", stderr)
        failures += 1
    }
}

print("==================================================")
print("Flowback Brand Identity Verification Suite")
print("==================================================")

// ------------------------------------------------------------------------------
// Test Suite 1: Vector SVGs & XML Parsing
// ------------------------------------------------------------------------------
print("\n[TEST SUITE 1] Vector SVG Files & XML Syntax")
let requiredSVGs = [
    "symbol.svg",
    "symbol-monochrome-black.svg",
    "symbol-monochrome-white.svg",
    "menubar-icon.svg",
    "wordmark.svg",
    "wordmark-dark.svg",
    "wordmark-light.svg",
    "logo-horizontal.svg",
    "logo-horizontal-dark.svg",
    "logo-horizontal-light.svg",
    "logo-stacked.svg",
    "logo-stacked-dark.svg",
    "logo-stacked-light.svg",
    "app-icon.svg",
    "app-icon-dark.svg",
    "app-icon-light.svg"
]

for name in requiredSVGs {
    let fileUrl = brandDir.appendingPathComponent(name)
    assertTest(fileManager.fileExists(atPath: fileUrl.path), "File exists: \(name)")
    
    if let data = try? Data(contentsOf: fileUrl) {
        assertTest(!data.isEmpty, "\(name) has non-zero byte size (\(data.count) bytes)")
        
        // Parse with XMLParser to verify valid XML
        let parser = XMLParser(data: data)
        let parsed = parser.parse()
        assertTest(parsed, "\(name) parses as valid well-formed XML/SVG")
        
        // Load into NSImage
        let image = NSImage(data: data)
        assertTest(image != nil, "\(name) successfully decodes via NSImage vector engine")
    } else {
        assertTest(false, "\(name) could not be read from disk")
    }
}

// ------------------------------------------------------------------------------
// Test Suite 2: Vector PDF Template for Menu Bar
// ------------------------------------------------------------------------------
print("\n[TEST SUITE 2] Native Vector PDF Menu Bar Template")
let pdfUrl = brandDir.appendingPathComponent("menubar-icon.pdf")
assertTest(fileManager.fileExists(atPath: pdfUrl.path), "menubar-icon.pdf exists")
if let pdfDoc = PDFDocument(url: pdfUrl) {
    assertTest(pdfDoc.pageCount == 1, "menubar-icon.pdf contains exactly 1 page")
    if let page = pdfDoc.page(at: 0) {
        let bounds = page.bounds(for: .mediaBox)
        assertTest(bounds.width == 18.0 && bounds.height == 18.0, "menubar-icon.pdf mediaBox is exactly 18x18 pt")
    }
} else {
    assertTest(false, "menubar-icon.pdf could not be decoded as PDFDocument")
}

// ------------------------------------------------------------------------------
// Test Suite 3: Geometry & Silhouette Alignment Across Symbol Variants
// ------------------------------------------------------------------------------
print("\n[TEST SUITE 3] Geometric Consistency & Aperture Hole Alignment")
func getHoleCenter(svgName: String) -> (Int, Int)? {
    let url = brandDir.appendingPathComponent(svgName)
    guard let data = try? Data(contentsOf: url),
          let img = NSImage(data: data) else { return nil }
    
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 512,
        pixelsHigh: 512,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    img.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
    NSGraphicsContext.restoreGraphicsState()
    
    var holePoints: [(Int, Int)] = []
    // scan inside aperture window (expected center at x=130, y=240)
    for y in 200...280 {
        for x in 95...165 {
            if let c = rep.colorAt(x: x, y: y), c.alphaComponent < 0.2 {
                holePoints.append((x, y))
            }
        }
    }
    guard !holePoints.isEmpty else { return nil }
    let avgX = holePoints.map(\.0).reduce(0, +) / holePoints.count
    let avgY = holePoints.map(\.1).reduce(0, +) / holePoints.count
    return (avgX, avgY)
}

let blackHole = getHoleCenter(svgName: "symbol-monochrome-black.svg")
let whiteHole = getHoleCenter(svgName: "symbol-monochrome-white.svg")

assertTest(blackHole != nil, "symbol-monochrome-black.svg has transparent knockout aperture hole")
assertTest(whiteHole != nil, "symbol-monochrome-white.svg has transparent knockout aperture hole")

if let bh = blackHole, let wh = whiteHole {
    assertTest(bh.0 == wh.0 && bh.1 == wh.1, "Black and White marks have identically aligned hole coordinates (\(bh.0), \(bh.1))")
    // Expected center in canvas coordinates (translate +18, -16): x = 112 + 18 = 130, y = 256 - 16 = 240
    assertTest(abs(bh.0 - 130) <= 3, "Aperture X center aligns with mathematical anchor axis (\(bh.0) ≈ 130)")
    assertTest(abs(bh.1 - 240) <= 4, "Aperture Y center aligns with mathematical anchor midline (\(bh.1) ≈ 240)")
}



// ------------------------------------------------------------------------------
// Test Suite 4: Multi-Resolution PNG Deliverables
// ------------------------------------------------------------------------------
print("\n[TEST SUITE 4] Multi-Resolution PNG Previews & Bitmap Dimensions")

let pngSpecs: [(String, Int, Int)] = [
    // Symbol
    ("symbol-16.png", 16, 16),
    ("symbol-32.png", 32, 32),
    ("symbol-64.png", 64, 64),
    ("symbol-128.png", 128, 128),
    ("symbol-256.png", 256, 256),
    ("symbol-512.png", 512, 512),
    ("symbol-1024.png", 1024, 1024),
    // Mono Black
    ("symbol-mono-black-16.png", 16, 16),
    ("symbol-mono-black-32.png", 32, 32),
    ("symbol-mono-black-64.png", 64, 64),
    ("symbol-mono-black-128.png", 128, 128),
    ("symbol-mono-black-256.png", 256, 256),
    ("symbol-mono-black-512.png", 512, 512),
    ("symbol-mono-black-1024.png", 1024, 1024),
    // Mono White
    ("symbol-mono-white-16.png", 16, 16),
    ("symbol-mono-white-32.png", 32, 32),
    ("symbol-mono-white-64.png", 64, 64),
    ("symbol-mono-white-128.png", 128, 128),
    ("symbol-mono-white-256.png", 256, 256),
    ("symbol-mono-white-512.png", 512, 512),
    ("symbol-mono-white-1024.png", 1024, 1024),
    // App Icon
    ("app-icon-16.png", 16, 16),
    ("app-icon-32.png", 32, 32),
    ("app-icon-64.png", 64, 64),
    ("app-icon-128.png", 128, 128),
    ("app-icon-256.png", 256, 256),
    ("app-icon-512.png", 512, 512),
    ("app-icon-1024.png", 1024, 1024),
    // App Icon Light
    ("app-icon-light-16.png", 16, 16),
    ("app-icon-light-32.png", 32, 32),
    ("app-icon-light-64.png", 64, 64),
    ("app-icon-light-128.png", 128, 128),
    ("app-icon-light-256.png", 256, 256),
    ("app-icon-light-512.png", 512, 512),
    ("app-icon-light-1024.png", 1024, 1024),
    // Menu Bar Icon
    ("menubar-icon-black-16.png", 16, 16),
    ("menubar-icon-black-18.png", 18, 18),
    ("menubar-icon-black-24.png", 24, 24),
    ("menubar-icon-black-32.png", 32, 32),
    ("menubar-icon-black-36.png", 36, 36),
    ("menubar-icon-black-48.png", 48, 48),
    ("menubar-icon-white-16.png", 16, 16),
    ("menubar-icon-white-18.png", 18, 18),
    ("menubar-icon-white-24.png", 24, 24),
    ("menubar-icon-white-32.png", 32, 32),
    ("menubar-icon-white-36.png", 36, 36),
    ("menubar-icon-white-48.png", 48, 48),
    // Lockups
    ("logo-horizontal-dark-256.png", 256, 64),
    ("logo-horizontal-dark-512.png", 512, 128),
    ("logo-horizontal-dark-1024.png", 1024, 256),
    ("logo-horizontal-dark-2048.png", 2048, 512),
    ("logo-horizontal-light-256.png", 256, 64),
    ("logo-horizontal-light-512.png", 512, 128),
    ("logo-horizontal-light-1024.png", 1024, 256),
    ("logo-horizontal-light-2048.png", 2048, 512),
    ("logo-stacked-dark-256.png", 256, 284),
    ("logo-stacked-dark-512.png", 512, 568),
    ("logo-stacked-dark-1024.png", 1024, 1137),
    ("logo-stacked-light-256.png", 256, 284),
    ("logo-stacked-light-512.png", 512, 568),
    ("logo-stacked-light-1024.png", 1024, 1137)
]

for (filename, expectedW, expectedH) in pngSpecs {
    let url = pngDir.appendingPathComponent(filename)
    if let img = NSImage(contentsOf: url),
       let rep = img.representations.first as? NSBitmapImageRep {
        let actualW = rep.pixelsWide
        let actualH = rep.pixelsHigh
        assertTest(actualW == expectedW && actualH == expectedH,
                   "\(filename) matches target dimensions (\(actualW)x\(actualH))")
    } else {
        assertTest(false, "\(filename) could not be loaded as PNG")
    }
}

// ------------------------------------------------------------------------------
// Test Suite 5: Apple AppIcon.icns Structure
// ------------------------------------------------------------------------------
print("\n[TEST SUITE 5] Apple AppIcon.icns Representation Architecture")
let icnsUrl = brandDir.appendingPathComponent("AppIcon.icns")
assertTest(fileManager.fileExists(atPath: icnsUrl.path), "AppIcon.icns exists in Design/Brand/")

if let icnsImg = NSImage(contentsOf: icnsUrl) {
    let repSizes = icnsImg.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" }
    assertTest(icnsImg.representations.count >= 10, "AppIcon.icns contains at least 10 icon layers (found \(icnsImg.representations.count))")
    
    let requiredResolutions = ["16x16", "32x32", "64x64", "128x128", "256x256", "512x512", "1024x1024"]
    for res in requiredResolutions {
        assertTest(repSizes.contains(res), "AppIcon.icns includes resolution \(res)")
    }
} else {
    assertTest(false, "AppIcon.icns could not be decoded by AppKit")
}

// ------------------------------------------------------------------------------
// Test Suite 6: WCAG 2.1 Contrast Mathematics
// ------------------------------------------------------------------------------
print("\n[TEST SUITE 6] WCAG 2.1 Contrast Ratios & Accessibility Compliance")
func sRGBtoLinear(_ val: Double) -> Double {
    let v = val / 255.0
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    return 0.2126 * sRGBtoLinear(r) + 0.7152 * sRGBtoLinear(g) + 0.0722 * sRGBtoLinear(b)
}

func contrastRatio(l1: Double, l2: Double) -> Double {
    let lighter = max(l1, l2)
    let darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}

let lumGraphite = relativeLuminance(r: 11, g: 15, b: 23)      // #0B0F17
let lumSlateCard = relativeLuminance(r: 20, g: 27, b: 41)     // #141B29
let lumOffWhite = relativeLuminance(r: 248, g: 250, b: 252)   // #F8FAFC
let lumCyan = relativeLuminance(r: 56, g: 189, b: 248)        // #38BDF8
let lumLightCanvas = relativeLuminance(r: 255, g: 255, b: 255)// #FFFFFF
let lumDarkText = relativeLuminance(r: 15, g: 23, b: 42)      // #0F172A

let offWhiteOnGraphite = contrastRatio(l1: lumOffWhite, l2: lumGraphite)
let cyanOnGraphite = contrastRatio(l1: lumCyan, l2: lumGraphite)
let cyanOnSlateCard = contrastRatio(l1: lumCyan, l2: lumSlateCard)
let darkTextOnLightCanvas = contrastRatio(l1: lumDarkText, l2: lumLightCanvas)

assertTest(offWhiteOnGraphite >= 18.0, String(format: "Crisp Off-White on Deep Graphite exceeds 18:1 (actual: %.2f:1 - WCAG AAA)", offWhiteOnGraphite))
assertTest(cyanOnGraphite >= 8.5, String(format: "Electric Cyan on Deep Graphite exceeds 8.5:1 (actual: %.2f:1 - WCAG AAA)", cyanOnGraphite))
assertTest(cyanOnSlateCard >= 8.0, String(format: "Electric Cyan on Slate Card exceeds 8.0:1 (actual: %.2f:1 - WCAG AAA)", cyanOnSlateCard))
assertTest(darkTextOnLightCanvas >= 17.0, String(format: "Deep Slate text on Light Canvas exceeds 17:1 (actual: %.2f:1 - WCAG AAA)", darkTextOnLightCanvas))

// ------------------------------------------------------------------------------
// Summary & Final Exit
// ------------------------------------------------------------------------------
print("\n==================================================")
print("VERIFICATION RESULTS SUMMARY")
print("Total checks executed: \(passes + failures)")
print("Passed: \(passes)")
print("Failed: \(failures)")
print("==================================================")

if failures == 0 {
    print("ALL BRAND ASSET INTEGRITY CHECKS PASSED! ✓\n")
    exit(0)
} else {
    fputs("AUDIT FAILED with \(failures) defect(s).\n", stderr)
    exit(1)
}
