//
//  iTermTabProjectGroupingTests.swift
//  iTerm2XCTests
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabProjectGroupingTests: XCTestCase {
    private var temporaryDirectory: String!

    override func setUp() {
        super.setUp()
        iTermTabProjectGrouping.resetCacheForTesting()
        temporaryDirectory = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("iTermTabProjectGroupingTests-" + UUID().uuidString)
        try! FileManager.default.createDirectory(atPath: temporaryDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: temporaryDirectory)
        iTermTabProjectGrouping.resetCacheForTesting()
        super.tearDown()
    }

    // Makes `relativePath` under the test's temporary directory and returns its
    // absolute path.
    @discardableResult
    private func makeDirectory(_ relativePath: String) -> String {
        let path = (temporaryDirectory as NSString).appendingPathComponent(relativePath)
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    // MARK: - Project root derivation

    func testRepositoryRootIsFoundFromANestedDirectory() {
        let root = makeDirectory("repo")
        makeDirectory("repo/.git")
        let nested = makeDirectory("repo/sources/TabGroups")
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: nested), root)
    }

    func testRepositoryRootIsFoundFromTheRootItself() {
        let root = makeDirectory("repo")
        makeDirectory("repo/.git")
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: root), root)
    }

    func testNearestRepositoryWinsOverAnOuterOne() {
        makeDirectory("outer/.git")
        let inner = makeDirectory("outer/vendor/inner")
        makeDirectory("outer/vendor/inner/.git")
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: inner), inner)
    }

    func testAGitFileCountsAsARepository() {
        // A submodule or worktree has a .git file, not a directory.
        let root = makeDirectory("worktree")
        let nested = makeDirectory("worktree/sub")
        try! "gitdir: /elsewhere".write(toFile: (root as NSString).appendingPathComponent(".git"),
                                        atomically: true,
                                        encoding: .utf8)
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: nested), root)
    }

    func testDirectoryWithNoRepositoryAboveItIsItsOwnProject() {
        let plain = makeDirectory("no-repo-here/deeper")
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: plain), plain)
    }

    func testProjectNameIsTheProjectFolderName() {
        // The group's name is the root's last path component (see
        // -[PseudoTerminal autoGroupTabByProject:]).
        let root = makeDirectory("phpvms")
        makeDirectory("phpvms/.git")
        let nested = makeDirectory("phpvms/app/Models")
        let derived = iTermTabProjectGrouping.projectRoot(forPath: nested)
        XCTAssertEqual((derived! as NSString).lastPathComponent, "phpvms")
    }

    func testRelativePathHasNoProjectRoot() {
        XCTAssertNil(iTermTabProjectGrouping.projectRoot(forPath: "sources/TabGroups"))
        XCTAssertNil(iTermTabProjectGrouping.projectRoot(forPath: ""))
    }

    func testResultIsCachedPerPath() {
        let root = makeDirectory("cached")
        makeDirectory("cached/.git")
        let nested = makeDirectory("cached/a/b")
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: nested), root)
        // Removing the repository does not change the answer: the cache is
        // deliberately never invalidated.
        try! FileManager.default.removeItem(atPath: (root as NSString).appendingPathComponent(".git"))
        XCTAssertEqual(iTermTabProjectGrouping.projectRoot(forPath: nested), root)
    }

    // MARK: - Stable color mapping

    func testColorIndexIsStableForTheSameProject() {
        let first = iTermTabProjectGrouping.colorIndex(forProjectRoot: "/Users/gn/phpvms", count: 7)
        let second = iTermTabProjectGrouping.colorIndex(forProjectRoot: "/Users/gn/phpvms", count: 7)
        XCTAssertEqual(first, second)
    }

    func testColorIndexIsInRange() {
        for root in ["/", "/a", "/Users/gn/iTerm2", "/tmp/x/y/z", String(repeating: "/q", count: 200)] {
            let index = iTermTabProjectGrouping.colorIndex(forProjectRoot: root, count: 7)
            XCTAssertTrue(index >= 0 && index < 7, "index \(index) out of range for \(root)")
        }
    }

    func testColorIndexDistinguishesNearbyProjects() {
        // Sibling projects under one parent are the common case; they should not
        // all land on the same color.
        let indexes = (0..<7).map {
            iTermTabProjectGrouping.colorIndex(forProjectRoot: "/Users/gn/project\($0)", count: 7)
        }
        XCTAssertGreaterThan(Set(indexes).count, 1)
    }

    func testColorIndexIsSafeWithAnEmptyPalette() {
        XCTAssertEqual(iTermTabProjectGrouping.colorIndex(forProjectRoot: "/a", count: 0), 0)
    }

    // MARK: - “The user owns this tab’s group”

    func testPinnedTabIsNeverAutoGrouped() {
        // A tab the user moved into/out of a group, renamed or recolored stays
        // put even when its project changed.
        XCTAssertFalse(iTermTabProjectGrouping.shouldAutoGroup(pinnedByUser: true,
                                                              projectRoot: "/a",
                                                              currentProjectRoot: nil))
        XCTAssertFalse(iTermTabProjectGrouping.shouldAutoGroup(pinnedByUser: true,
                                                              projectRoot: "/a",
                                                              currentProjectRoot: "/b"))
    }

    func testUnpinnedTabWithANewProjectIsAutoGrouped() {
        XCTAssertTrue(iTermTabProjectGrouping.shouldAutoGroup(pinnedByUser: false,
                                                             projectRoot: "/a",
                                                             currentProjectRoot: nil))
        XCTAssertTrue(iTermTabProjectGrouping.shouldAutoGroup(pinnedByUser: false,
                                                             projectRoot: "/a",
                                                             currentProjectRoot: "/b"))
    }

    func testUnchangedProjectIsANoOp() {
        // A shell pushes its directory after every command, so this is the case
        // that runs most often.
        XCTAssertFalse(iTermTabProjectGrouping.shouldAutoGroup(pinnedByUser: false,
                                                              projectRoot: "/a",
                                                              currentProjectRoot: "/a"))
    }

    func testUnknownProjectIsANoOp() {
        XCTAssertFalse(iTermTabProjectGrouping.shouldAutoGroup(pinnedByUser: false,
                                                              projectRoot: nil,
                                                              currentProjectRoot: nil))
    }
}
