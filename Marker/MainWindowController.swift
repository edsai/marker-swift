import Cocoa
import WebKit

class MainWindowController: NSWindowController, NSSplitViewDelegate {
    let tabManager = TabManager()
    let tabBarView = TabBarView()
    private let splitView = NSSplitView()
    private let leftSidebar = SidebarPlaceholderView(title: "Files")
    let centerContainer = NSView()  // Public for B3 webview swap
    private let rightSidebar = SidebarPlaceholderView(title: "Outline")
    private let statusBar = NSTextField(labelWithString: "")

    // WKWebView is passed in from AppDelegate (will be extracted to EditorWebViewController in B3)
    var webView: WKWebView? {
        didSet {
            guard let webView = webView else { return }
            webView.translatesAutoresizingMaskIntoConstraints = false
            centerContainer.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                webView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            ])
        }
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Marker"
        window.minSize = NSSize(width: 600, height: 400)
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)
        window.setFrameAutosaveName("MainWindow")

        self.init(window: window)
        setupLayout()
        setupTabBar()
    }

    private func setupLayout() {
        guard let contentView = window!.contentView else {
            preconditionFailure("MainWindowController: window has no contentView")
        }
        contentView.wantsLayer = true

        // Manual Auto Layout: tabBar | splitView | statusBar
        // (NOT NSStackView — NSSplitView has no intrinsicContentSize and collapses to zero in stack views)

        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabBarView)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false

        leftSidebar.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.translatesAutoresizingMaskIntoConstraints = false
        rightSidebar.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(leftSidebar)
        splitView.addArrangedSubview(centerContainer)
        splitView.addArrangedSubview(rightSidebar)

        contentView.addSubview(splitView)

        // Status bar
        statusBar.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusBar.textColor = .tertiaryLabelColor
        statusBar.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        statusBar.drawsBackground = true
        statusBar.isBezeled = false
        statusBar.isEditable = false
        statusBar.stringValue = "  Ln 1, Col 1"
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusBar)

        // Pin all three vertically: tabBar(36) | splitView(fill) | statusBar(24)
        NSLayoutConstraint.activate([
            tabBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            statusBar.topAnchor.constraint(equalTo: splitView.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        // NO width constraints on split view subviews — NSSplitView manages sizes via dividers.
        // Min/max enforced only through NSSplitViewDelegate methods.
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        // Defer divider positioning to next run loop tick so the layout engine
        // has resolved the split view's frame (it may be zero at windowDidLoad time)
        DispatchQueue.main.async { [self] in
            splitView.setPosition(220, ofDividerAt: 0)
            splitView.setPosition(splitView.frame.width - 220, ofDividerAt: 1)
        }
    }

    private func setupTabBar() {
        tabBarView.delegate = self
        tabManager.delegate = self
    }

    // MARK: - Public API

    func toggleLeftSidebar() {
        let isCollapsed = splitView.isSubviewCollapsed(leftSidebar)
        splitView.setPosition(isCollapsed ? 220 : 0, ofDividerAt: 0)
    }

    func toggleRightSidebar() {
        let isCollapsed = splitView.isSubviewCollapsed(rightSidebar)
        let pos = isCollapsed ? splitView.bounds.width - 220 : splitView.bounds.width
        splitView.setPosition(pos, ofDividerAt: 1)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return subview === leftSidebar || subview === rightSidebar
    }

    func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        return true
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Return 0 for divider 0 to allow left sidebar to collapse
        // NSSplitView handles snap-to-collapse threshold internally
        if dividerIndex == 0 { return 0 }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 { return 400 }
        // Right sidebar: allow full collapse, but when open must be at least 140pt
        if dividerIndex == 1 { return proposedMaximumPosition - 140 }
        return proposedMaximumPosition
    }
}

// MARK: - TabBarViewDelegate

extension MainWindowController: TabBarViewDelegate {
    func tabBarDidSelectTab(id: String) {
        tabManager.switchTo(id: id)
    }

    func tabBarDidCloseTab(id: String) {
        tabManager.closeTab(id: id)
    }

    func tabBarDidRequestNewTab() {
        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        // Call JS first, register in Swift only on success
        webView?.callAsyncJavaScript(
            "await marker.openTab(tabId, content)",
            arguments: ["tabId": tabId, "content": ""],
            in: nil, in: .page
        ) { [weak self] result in
            if case .failure(let error) = result {
                NSLog("Marker: failed to open new tab: \(error)")
                return
            }
            self?.tabManager.addTab(id: tabId, title: "Untitled")
        }
    }
}

// MARK: - TabManagerDelegate

extension MainWindowController: TabManagerDelegate {
    func tabManager(_ manager: TabManager, didSwitchTo tab: Tab) {
        tabBarView.setActiveTab(id: tab.id)
        // switchTab is idempotent in JS — calling it after openTab is safe (just re-shows the tab)
        webView?.callAsyncJavaScript(
            "await marker.switchTab(tabId, content)",
            arguments: ["tabId": tab.id, "content": ""],
            in: nil, in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("Marker: failed to switch tab: \(error)")
            }
        }
    }

    func tabManager(_ manager: TabManager, didClose tab: Tab) {
        tabBarView.removeTab(id: tab.id)
        webView?.callAsyncJavaScript(
            "await marker.closeTab(tabId)",
            arguments: ["tabId": tab.id],
            in: nil, in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("Marker: failed to close tab: \(error)")
            }
        }
    }

    func tabManager(_ manager: TabManager, didAdd tab: Tab) {
        tabBarView.addTab(id: tab.id, title: tab.title, isDirty: tab.isDirty)
    }

    func tabManager(_ manager: TabManager, didUpdateDirty tab: Tab) {
        tabBarView.updateDirty(id: tab.id, isDirty: tab.isDirty)
    }
}
