import XCTest
@testable import GlassDock

final class ClipboardTransformTests: XCTestCase {
    private func output(_ transform: ClipboardTransform, _ text: String) -> String? {
        try? transform.apply(to: text).get()
    }

    func testFormatJSONKeepsKeyOrderAndNumbers() {
        XCTAssertEqual(
            output(.formatJSON, #"{"b":[1,2.50,{}],"a":"x, y: z"}"#),
            "{\n  \"b\": [\n    1,\n    2.50,\n    {}\n  ],\n  \"a\": \"x, y: z\"\n}")
    }

    func testMinifyJSONKeepsStringContents() {
        XCTAssertEqual(output(.minifyJSON, "{\n  \"a\" : \"x  \\\" y\",\n  \"b\": [ ]\n}"), #"{"a":"x  \" y","b":[]}"#)
    }

    func testInvalidJSONFailsAndIsFlagged() {
        let text = #"{"a": 1,}"#
        XCTAssertNil(output(.formatJSON, text))
        XCTAssertTrue(ClipboardTransform.looksLikeInvalidJSON(text))
        XCTAssertFalse(ClipboardTransform.applicable(to: text).contains(.formatJSON))
        XCTAssertFalse(ClipboardTransform.looksLikeInvalidJSON("[INFO] started"))
        XCTAssertFalse(ClipboardTransform.looksLikeInvalidJSON(#"{"a": 1}"#))
        XCTAssertFalse(ClipboardTransform.looksLikeInvalidJSON(#"["a,]", "b\\", 2]"#))
    }

    func testJSONScalarsAreNotJSONTransforms() {
        XCTAssertNil(output(.formatJSON, "42"))
    }

    func testStripTrackingParametersKeepsOthers() {
        XCTAssertEqual(
            output(.stripTrackingParameters, "https://example.com/p?id=7&utm_source=x&fbclid=1&q=a%20b&REF=tw#top"),
            "https://example.com/p?id=7&q=a%20b#top")
        XCTAssertEqual(output(.stripTrackingParameters, "https://example.com/p?utm_medium=x"), "https://example.com/p")
    }

    func testStripTrackingParametersOnlyAppliesToURLsWithTracking() {
        XCTAssertNil(output(.stripTrackingParameters, "not a url"))
        let clean = "https://example.com/p?id=7"
        XCTAssertFalse(ClipboardTransform.applicable(to: clean).contains(.stripTrackingParameters))
        XCTAssertTrue(ClipboardTransform.applicable(to: clean + "&gclid=9").contains(.stripTrackingParameters))
    }

    func testTrimWhitespace() {
        XCTAssertEqual(output(.trimWhitespace, "  a  \r\n   b\t\n\n"), "a\n   b")
    }

    func testCollapseBlankLines() {
        XCTAssertEqual(output(.collapseBlankLines, "a\n\n \n\t\n\nb\n"), "a\n\nb\n")
    }

    func testCase() {
        XCTAssertEqual(output(.uppercase, "Hello"), "HELLO")
        XCTAssertEqual(output(.lowercase, "Hello"), "hello")
        XCTAssertEqual(output(.titleCase, "hello WORLD"), "Hello World")
    }

    func testBase64RoundTrip() {
        XCTAssertEqual(output(.base64Encode, "héllo"), "aMOpbGxv")
        XCTAssertEqual(output(.base64Decode, "aMOpbGxv"), "héllo")
        XCTAssertNil(output(.base64Decode, "not base64!"))
        XCTAssertNil(output(.base64Decode, "/+8="))
    }

    func testURLEncodeDecode() {
        XCTAssertEqual(output(.urlEncode, "a b&c=é"), "a%20b%26c%3D%C3%A9")
        XCTAssertEqual(output(.urlDecode, "a%20b%26c%3D%C3%A9"), "a b&c=é")
        XCTAssertNil(output(.urlDecode, "100%"))
    }

    func testApplicableHidesTransformsThatChangeNothing() {
        XCTAssertEqual(ClipboardTransform.applicable(to: "123"), [.base64Encode])
        XCTAssertTrue(ClipboardTransform.applicable(to: "").isEmpty)
    }
}
