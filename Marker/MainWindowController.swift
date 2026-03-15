import Cocoa

class MainWindowController: NSWindowController, NSSplitViewDelegate {
    let tabManager = TabManager()
    let tabBarView = TabBarView()
    private let splitView = NSSplitView()
    let fileTreeVC = FileTreeViewController()
    let centerContainer = NSView()  // Public for B3 webview swap
    let outlineVC = OutlineViewController()
    let statusBarView = StatusBarView()

    // EditorWebViewController whose view is embedded in centerContainer.
    // Note: Not added via addChild — NSWindowController is not NSViewController.
    // VC lifecycle methods (viewWillAppear etc.) are not needed for this use case.
    var editorVC: EditorWebViewController? {
        didSet {
            oldValue?.view.removeFromSuperview()
            guard let editorVC = editorVC else { return }
            let editorView = editorVC.view
            editorView.translatesAutoresizingMaskIntoConstraints = false
            centerContainer.addSubview(editorView)
            NSLayoutConstraint.activate([
                editorView.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                editorView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
                editorView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                editorView.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            ])
            outlineVC.bridge = editorVC.bridge
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

        fileTreeVC.view.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.translatesAutoresizingMaskIntoConstraints = false
        outlineVC.view.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(fileTreeVC.view)
        splitView.addArrangedSubview(centerContainer)
        splitView.addArrangedSubview(outlineVC.view)

        contentView.addSubview(splitView)

        // Status bar
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusBarView)

        // Pin all three vertically: tabBar(36) | splitView(fill) | statusBar(24)
        NSLayoutConstraint.activate([
            tabBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            statusBarView.topAnchor.constraint(equalTo: splitView.bottomAnchor),
            statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 24),
        ])

        // NO width constraints on split view subviews — NSSplitView manages sizes via dividers.
        // Min/max enforced only through NSSplitViewDelegate methods.
    }

    /// Call after showWindow to set initial divider positions.
    /// windowDidLoad is NOT called for programmatically created windows.
    func setInitialDividerPositions() {
        DispatchQueue.main.async { [self] in
            splitView.setPosition(220, ofDividerAt: 0)
            splitView.setPosition(splitView.frame.width - 220, ofDividerAt: 1)
        }
    }

    private func setupTabBar() {
        tabBarView.delegate = self
        tabManager.delegate = self
        fileTreeVC.delegate = self
    }

    // MARK: - Public API

    func updateCursorPosition(line: Int, col: Int) {
        statusBarView.updateCursor(line: line, col: col)
    }

    func updateStatusBarFilePath(_ path: String?) {
        statusBarView.updateFilePath(path)
    }

    func updateWordCount(_ count: Int) {
        statusBarView.updateWordCount(count)
    }

    func toggleLeftSidebar() {
        let isCollapsed = splitView.isSubviewCollapsed(fileTreeVC.view)
        splitView.setPosition(isCollapsed ? 220 : 0, ofDividerAt: 0)
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.fileTreeVC.rootURL = url
            self?.window?.title = "Marker — \(url.lastPathComponent)"
        }
    }

    func toggleRightSidebar() {
        let isCollapsed = splitView.isSubviewCollapsed(outlineVC.view)
        let pos = isCollapsed ? splitView.bounds.width - 220 : splitView.bounds.width
        splitView.setPosition(pos, ofDividerAt: 1)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return subview === fileTreeVC.view || subview === outlineVC.view
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
        editorVC?.bridge.openTab(id: tabId, content: "") { [weak self] success in
            guard success else { return }
            self?.tabManager.addTab(id: tabId, title: "Untitled")
        }
    }
}

// MARK: - TabManagerDelegate

extension MainWindowController: TabManagerDelegate {
    func tabManager(_ manager: TabManager, didSwitchTo tab: Tab) {
        tabBarView.setActiveTab(id: tab.id)
        editorVC?.bridge.switchTab(id: tab.id)
        outlineVC.activeTabId = tab.id
        outlineVC.refreshHeadings(webView: editorVC?.webView)
        let filePath = tab.filePath
        statusBarView.updateFilePath(filePath)
    }

    func tabManager(_ manager: TabManager, didClose tab: Tab) {
        tabBarView.removeTab(id: tab.id)
        editorVC?.bridge.closeTab(id: tab.id)
    }

    func tabManager(_ manager: TabManager, didAdd tab: Tab) {
        tabBarView.addTab(id: tab.id, title: tab.title, isDirty: tab.isDirty)
    }

    func tabManager(_ manager: TabManager, didUpdateDirty tab: Tab) {
        tabBarView.updateDirty(id: tab.id, isDirty: tab.isDirty)
        // Refresh outline when content changes
        outlineVC.refreshHeadings(webView: editorVC?.webView)
    }
}

// MARK: - FileTreeDelegate

extension MainWindowController: FileTreeDelegate {
    func fileTree(didSelectFile url: URL) {
        // Check if file is already open
        if let existing = tabManager.tabByFilePath(url.path) {
            tabManager.switchTo(id: existing.id)
            return
        }
        // Open file via AppDelegate (which handles content reading + bridge call)
        (NSApp.delegate as? AppDelegate)?.openFile(path: url.path)
    }
}
