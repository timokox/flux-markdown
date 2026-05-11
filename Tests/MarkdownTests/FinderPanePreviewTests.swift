import XCTest
@testable import Markdown

final class FinderPanePreviewTests: XCTestCase {
    
    func testFinderPaneFontSizeDefaultIs13() {
        let pref = AppearancePreference.shared
        XCTAssertEqual(pref.finderPaneFontSize, 13)
    }
    
    func testFinderPaneFontSizePersistsRoundTrip() {
        let pref = AppearancePreference.shared
        let original = pref.finderPaneFontSize
        defer { pref.finderPaneFontSize = original }
        
        pref.finderPaneFontSize = 18
        XCTAssertEqual(pref.finderPaneFontSize, 18)
    }
}
