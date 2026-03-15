import XCTest
@testable import Marker

final class TabManagerTests: XCTestCase {
    var manager: TabManager!

    override func setUp() {
        super.setUp()
        manager = TabManager()
    }

    // MARK: - Add

    func testAddTabAppendsAndActivates() {
        manager.addTab(id: "t1", title: "Welcome")
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.activeTabId, "t1")
    }

    func testAddSecondTabSwitchesToIt() {
        manager.addTab(id: "t1", title: "One")
        manager.addTab(id: "t2", title: "Two")
        XCTAssertEqual(manager.count, 2)
        XCTAssertEqual(manager.activeTabId, "t2")
    }

    func testAddDuplicateIdIsIgnored() {
        manager.addTab(id: "t1", title: "One")
        manager.addTab(id: "t1", title: "Duplicate")
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.tab(for: "t1")?.title, "One")
    }

    // MARK: - Switch

    func testSwitchToExistingTab() {
        manager.addTab(id: "t1", title: "One")
        manager.addTab(id: "t2", title: "Two")
        manager.switchTo(id: "t1")
        XCTAssertEqual(manager.activeTabId, "t1")
    }

    func testSwitchToNonexistentTabIsNoOp() {
        manager.addTab(id: "t1", title: "One")
        manager.switchTo(id: "bogus")
        XCTAssertEqual(manager.activeTabId, "t1")
    }

    // MARK: - Close

    func testCloseTabRemovesIt() {
        manager.addTab(id: "t1", title: "One")
        manager.addTab(id: "t2", title: "Two")
        manager.closeTab(id: "t1")
        XCTAssertEqual(manager.count, 1)
        XCTAssertNil(manager.tab(for: "t1"))
    }

    func testCloseActiveTabSwitchesToAdjacentRight() {
        manager.addTab(id: "t1", title: "One")
        manager.addTab(id: "t2", title: "Two")
        manager.addTab(id: "t3", title: "Three")
        manager.switchTo(id: "t2")
        manager.closeTab(id: "t2")
        XCTAssertEqual(manager.activeTabId, "t3")
    }

    func testCloseLastTabSwitchesToLeft() {
        manager.addTab(id: "t1", title: "One")
        manager.addTab(id: "t2", title: "Two")
        manager.closeTab(id: "t2")
        XCTAssertEqual(manager.activeTabId, "t1")
    }

    func testCloseOnlyTabClearsActive() {
        manager.addTab(id: "t1", title: "One")
        manager.closeTab(id: "t1")
        XCTAssertNil(manager.activeTabId)
        XCTAssertEqual(manager.count, 0)
    }

    func testClosedTabGoesToRecentlyClosed() {
        manager.addTab(id: "t1", title: "One")
        manager.closeTab(id: "t1")
        XCTAssertEqual(manager.recentlyClosed.count, 1)
        XCTAssertEqual(manager.recentlyClosed.first?.id, "t1")
    }

    func testRecentlyClosedCapsAt10() {
        for i in 1...12 {
            manager.addTab(id: "t\(i)", title: "Tab \(i)")
        }
        for i in 1...12 {
            manager.closeTab(id: "t\(i)")
        }
        XCTAssertEqual(manager.recentlyClosed.count, 10)
        XCTAssertNil(manager.recentlyClosed.first(where: { $0.id == "t1" }))
        XCTAssertNil(manager.recentlyClosed.first(where: { $0.id == "t2" }))
        XCTAssertEqual(manager.recentlyClosed.first?.id, "t3")
    }

    // MARK: - Dirty

    func testSetDirtyUpdatesTab() {
        manager.addTab(id: "t1", title: "One")
        manager.setDirty(id: "t1", isDirty: true)
        XCTAssertTrue(manager.tab(for: "t1")!.isDirty)
        manager.setDirty(id: "t1", isDirty: false)
        XCTAssertFalse(manager.tab(for: "t1")!.isDirty)
    }

    // MARK: - Lookup

    func testTabByFilePath() {
        manager.addTab(id: "t1", title: "readme", filePath: "/docs/readme.md")
        let found = manager.tabByFilePath("/docs/readme.md")
        XCTAssertEqual(found?.id, "t1")
    }

    func testTabByFilePathReturnsNilWhenNotFound() {
        XCTAssertNil(manager.tabByFilePath("/nope"))
    }
}
