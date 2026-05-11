import XCTest

final class LocalSchemeHandlerTests: XCTestCase {

    func testResolveFilePathStripsQueryParameters() {
        let handler = LocalSchemeHandler()
        let url = URL(string: "local-md:///Users/me/docs/image.png?v=42")!
        let resolved = handler.resolveFilePath(from: url)
        XCTAssertEqual(resolved, "/Users/me/docs/image.png")
    }

    func testResolveFilePathPreservesPathWithoutQuery() {
        let handler = LocalSchemeHandler()
        let url = URL(string: "local-md:///Users/me/docs/image.png")!
        let resolved = handler.resolveFilePath(from: url)
        XCTAssertEqual(resolved, "/Users/me/docs/image.png")
    }

    func testResolveFilePathHandlesHostBasedURL() {
        let handler = LocalSchemeHandler()
        let url = URL(string: "local-md://Users/me/docs/image.png?v=1")!
        let resolved = handler.resolveFilePath(from: url)
        XCTAssertEqual(resolved, "/Users/me/docs/image.png")
    }

    func testBuildResponseIncludesCacheControlHeader() {
        let handler = LocalSchemeHandler()
        let url = URL(string: "local-md:///Users/me/docs/image.png?v=42")!
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let response = handler.buildResponse(for: url, data: data)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Expected HTTPURLResponse")
            return
        }

        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Cache-Control"), "no-cache, no-store, must-revalidate")
    }

    func testBuildResponseSetsMimeType() {
        let handler = LocalSchemeHandler()
        let pngURL = URL(string: "local-md:///image.png")!
        let jpgURL = URL(string: "local-md:///photo.jpg")!
        let svgURL = URL(string: "local-md:///icon.svg")!

        let pngResp = handler.buildResponse(for: pngURL, data: Data()) as? HTTPURLResponse
        let jpgResp = handler.buildResponse(for: jpgURL, data: Data()) as? HTTPURLResponse
        let svgResp = handler.buildResponse(for: svgURL, data: Data()) as? HTTPURLResponse

        XCTAssertEqual(pngResp?.mimeType, "image/png")
        XCTAssertEqual(jpgResp?.mimeType, "image/jpeg")
        XCTAssertEqual(svgResp?.mimeType, "image/svg+xml")
    }
}
