import XCTest

final class ToolbarButtonHitAreaTests: XCTestCase {
    func testFloatingToolbarButtonsUseAppKitBoundsBasedHitControls() throws {
        let toolbarSourcePath = try projectRoot().appendingPathComponent("Sources/Markdown/MarkdownApp.swift").path
        let source = try String(contentsOfFile: toolbarSourcePath, encoding: .utf8)
        let toolbarRange = try XCTUnwrap(
            source.range(of: "HStack(spacing: 8) {"),
            "Floating toolbar HStack should exist"
        )
        let toolbarSource = String(source[toolbarRange.lowerBound...])
        let toolbarEndRange = try XCTUnwrap(
            toolbarSource.range(of: "                .padding([.top, .trailing], 10)"),
            "Floating toolbar should end at its top/trailing padding"
        )
        let floatingToolbarSource = String(toolbarSource[..<toolbarEndRange.lowerBound])

        let helperRange = try XCTUnwrap(
            source.range(of: "private struct ToolbarIconButton: View"),
            "Floating toolbar buttons should use a shared helper so hit-area modifiers cannot drift per button"
        )
        let helperSource = String(source[helperRange.lowerBound...])

        XCTAssertEqual(
            floatingToolbarSource.components(separatedBy: "ToolbarIconButton(").count - 1,
            7,
            "Every visible circular toolbar control should use the shared AppKit-backed hit-area helper."
        )
        XCTAssertTrue(
            helperSource.contains("NSViewRepresentable")
                && helperSource.contains("NSButton")
                && helperSource.contains("ToolbarIconNSButton"),
            "SwiftUI-only hit expansion failed over WKWebView; toolbar buttons need an AppKit-backed 30x30 control with bounds-based hit testing."
        )
        XCTAssertTrue(
            helperSource.contains("override func hitTest(_ point: NSPoint) -> NSView?")
                && helperSource.contains("bounds.contains(point) ? self : nil"),
            "The AppKit control must explicitly claim every point inside its 30x30 bounds so perimeter clicks cannot pass through to the web view."
        )
        XCTAssertTrue(
            helperSource.contains("NSImage(systemSymbolName: systemName")
                && helperSource.contains(".frame(width: 30, height: 30)")
                && helperSource.contains("NSBezierPath(ovalIn: bounds).fill()"),
            "The helper must keep the same 30x30 circular visual while moving real hit testing to AppKit bounds."
        )
    }

    private func projectRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("project.yml")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(domain: "ToolbarButtonHitAreaTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate project root from \(#filePath)"])
    }
}
