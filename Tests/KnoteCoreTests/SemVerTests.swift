import XCTest
@testable import KnoteCore

final class SemVerTests: XCTestCase {

    // MARK: - Ordering

    func testMinorIncrement() {
        XCTAssertLessThan(SemVer("0.1.0")!, SemVer("0.2.0")!)
    }

    func testPatchIncrement() {
        XCTAssertLessThan(SemVer("0.2.0")!, SemVer("0.2.1")!)
    }

    func testMajorRollover() {
        XCTAssertGreaterThan(SemVer("1.0.0")!, SemVer("0.9.9")!)
    }

    func testEqualVersionsNotNewer() {
        XCTAssertFalse(SemVer.isNewer("1.0.0", than: "1.0.0"))
    }

    // MARK: - Prerelease ordering

    func testPrereleaseIsOlderThanRelease() {
        XCTAssertLessThan(SemVer("0.2.0-beta")!, SemVer("0.2.0")!)
    }

    func testPrereleaseIsNewerFalse() {
        XCTAssertFalse(SemVer.isNewer("0.2.0-beta", than: "0.2.0"))
    }

    // MARK: - Leading "v" prefix

    func testLeadingVPrefix() {
        let v = SemVer("v1.0.0")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 0)
        XCTAssertNil(v?.prerelease)
    }

    func testLeadingVIsNewer() {
        XCTAssertTrue(SemVer.isNewer("v1.1.0", than: "v1.0.0"))
    }

    // MARK: - Unparseable input

    func testUnparseableIsNewerFalse() {
        XCTAssertFalse(SemVer.isNewer("not-a-version", than: "1.0.0"))
    }

    func testUnparseableCurrent() {
        XCTAssertFalse(SemVer.isNewer("1.1.0", than: "garbage"))
    }

    func testBothUnparseable() {
        XCTAssertFalse(SemVer.isNewer("foo", than: "bar"))
    }

    func testNilInit() {
        XCTAssertNil(SemVer(""))
        XCTAssertNil(SemVer("1.2"))
        XCTAssertNil(SemVer("1.2.3.4"))
        XCTAssertNil(SemVer("a.b.c"))
    }

    // MARK: - isNewer

    func testIsNewerTrue() {
        XCTAssertTrue(SemVer.isNewer("2.0.0", than: "1.9.9"))
    }

    func testIsNewerFalseWhenOlder() {
        XCTAssertFalse(SemVer.isNewer("1.0.0", than: "1.0.1"))
    }

    // MARK: - pickNewest (the update-selection logic)

    func testPickNewestFindsBetaWhenAllowed() {
        // The real bug: a beta build must see a newer beta.
        let versions = ["v0.1.0", "v0.2.0-beta", "v0.2.1-beta"]
        XCTAssertEqual(
            SemVer.pickNewest(from: versions, allowPrerelease: true, newerThan: "0.2.0-beta"),
            "v0.2.1-beta")
    }

    func testPickNewestExcludesPrereleasesWhenNotAllowed() {
        let versions = ["v0.1.0", "v0.2.0-beta", "v0.2.1-beta"]
        XCTAssertNil(
            SemVer.pickNewest(from: versions, allowPrerelease: false, newerThan: "0.2.0-beta"))
        XCTAssertEqual(
            SemVer.pickNewest(from: ["v0.1.0", "v0.3.0"], allowPrerelease: false, newerThan: "0.1.0"),
            "v0.3.0")
    }

    func testPickNewestNilWhenNothingNewer() {
        XCTAssertNil(
            SemVer.pickNewest(from: ["v0.1.0", "v0.2.1-beta"], allowPrerelease: true, newerThan: "0.2.1-beta"))
    }

    func testPickNewestPicksHighestNotFirst() {
        let versions = ["v0.2.1-beta", "v0.2.10-beta", "v0.2.2-beta"]
        XCTAssertEqual(
            SemVer.pickNewest(from: versions, allowPrerelease: true, newerThan: "0.2.0"),
            "v0.2.10-beta")
    }
}
