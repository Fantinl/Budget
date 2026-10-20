import XCTest
import SwiftUI
import AppKit
@testable import Budget

final class ThemeTests: XCTestCase {
    func testAllThemesRegistered() {
        XCTAssertEqual(Theme.all.count, 6)
        XCTAssertEqual(Set(Theme.all.map(\.id)).count, 6)
        for theme in Theme.all {
            XCTAssertEqual(Theme.named(theme.id).id, theme.id)
            XCTAssertEqual(theme.categoryPalette.count, 12, theme.name)
        }
    }

    func testUnknownIDFallsBackToCurrent() {
        XCTAssertEqual(Theme.named("inconnu").id, Theme.current.id)
    }

    func testTextContrastOnBackground() {
        for theme in Theme.all {
            for (name, appearance) in [("clair", NSAppearance.Name.aqua), ("sombre", .darkAqua)] {
                let ratio = contrast(theme.textPrimary, theme.background, appearance)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme.name) \(name) texte/fond")
                let onSurface = contrast(theme.textPrimary, theme.surface, appearance)
                XCTAssertGreaterThanOrEqual(onSurface, 4.5, "\(theme.name) \(name) texte/carte")
                let secondary = contrast(theme.textSecondary, theme.surface, appearance)
                XCTAssertGreaterThanOrEqual(secondary, 4.5, "\(theme.name) \(name) secondaire/carte")
                let hero = min(
                    contrast(theme.heroTextPrimary, theme.heroGradientStart, appearance),
                    contrast(theme.heroTextPrimary, theme.heroGradientEnd, appearance))
                XCTAssertGreaterThanOrEqual(hero, 3.0, "\(theme.name) \(name) texte/héros")
                let button = contrast(theme.onAccent, theme.accent, appearance)
                XCTAssertGreaterThanOrEqual(button, 3.0, "\(theme.name) \(name) bouton")
            }
        }
    }

    // MARK: Aides

    private func rgb(_ color: Color, _ name: NSAppearance.Name) -> (Double, Double, Double) {
        var result: (Double, Double, Double) = (0, 0, 0)
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
            result = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        }
        return result
    }

    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    private func contrast(_ a: Color, _ b: Color, _ name: NSAppearance.Name) -> Double {
        let la = luminance(rgb(a, name)), lb = luminance(rgb(b, name))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
