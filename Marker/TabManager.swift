import Foundation

struct Tab: Identifiable, Equatable {
    let id: String
    var title: String
    var filePath: String?  // nil for untitled/welcome tabs
    var isDirty: Bool = false

    static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id
    }
}

protocol TabManagerDelegate: AnyObject {
    func tabManager(_ manager: TabManager, didSwitchTo tab: Tab)
    func tabManager(_ manager: TabManager, didClose tab: Tab)
    func tabManager(_ manager: TabManager, didAdd tab: Tab)
    func tabManager(_ manager: TabManager, didUpdateDirty tab: Tab)
}

class TabManager {
    private(set) var tabs: [Tab] = []
    private(set) var activeTabId: String?
    private(set) var recentlyClosed: [Tab] = []  // max 10
    weak var delegate: TabManagerDelegate?

    private let maxRecentlyClosed = 10

    var activeTab: Tab? {
        guard let id = activeTabId else { return nil }
        return tabs.first { $0.id == id }
    }

    var count: Int { tabs.count }

    // MARK: - Add

    func addTab(id: String, title: String, filePath: String? = nil) {
        let tab = Tab(id: id, title: title, filePath: filePath)
        tabs.append(tab)
        activeTabId = id
        delegate?.tabManager(self, didAdd: tab)
        delegate?.tabManager(self, didSwitchTo: tab)
    }

    // MARK: - Switch

    func switchTo(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        if let tab = activeTab {
            delegate?.tabManager(self, didSwitchTo: tab)
        }
    }

    // MARK: - Close

    func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closed = tabs.remove(at: index)

        // Push to recently closed
        recentlyClosed.append(closed)
        if recentlyClosed.count > maxRecentlyClosed {
            recentlyClosed.removeFirst()
        }

        delegate?.tabManager(self, didClose: closed)

        // Switch to adjacent tab
        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
                if let tab = activeTab {
                    delegate?.tabManager(self, didSwitchTo: tab)
                }
            }
        }
    }

    // MARK: - Dirty

    func setDirty(id: String, isDirty: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isDirty = isDirty
        delegate?.tabManager(self, didUpdateDirty: tabs[index])
    }

    // MARK: - Lookup

    func tab(for id: String) -> Tab? {
        tabs.first { $0.id == id }
    }

    func tabByFilePath(_ path: String) -> Tab? {
        tabs.first { $0.filePath == path }
    }
}
