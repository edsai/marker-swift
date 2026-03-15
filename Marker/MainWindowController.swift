import Cocoa

class MainWindowController: NSWindowController, NSSplitViewDelegate {
    let tabManager = TabManager()
    let tabBarView = TabBarView()
    let findBarView = FindBarView()
    private var findBarHeightConstraint: NSLayoutConstraint!
    let fileWatcher = FileWatcher()
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
        window.backgroundColor = .windowBackgroundColor
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

        findBarView.translatesAutoresizingMaskIntoConstraints = false
        findBarView.isHidden = true
        contentView.addSubview(findBarView)

        // Zero-height constraint when hidden (isHidden alone doesn't collapse in manual AL)
        findBarHeightConstraint = findBarView.heightAnchor.constraint(equalToConstant: 0)
        findBarHeightConstraint.isActive = true

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

            findBarView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            findBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            findBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: findBarView.bottomAnchor),
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
        fileWatcher.delegate = self
        findBarView.delegate = self
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
            self?.fileWatcher.watch(directory: url)
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
        confirmCloseTab(id: id)
    }

    func confirmCloseTab(id: String) {
        guard let tab = tabManager.tab(for: id) else { return }

        if tab.isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to \"\(tab.title)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Save then close
                (NSApp.delegate as? AppDelegate)?.saveAndCloseTab(id: id)
                return
            case .alertSecondButtonReturn:
                // Don't save — close directly
                break
            case .alertThirdButtonReturn:
                // Cancel — do nothing
                return
            default:
                return
            }
        }

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
        statusBarView.updateFilePath(tab.filePath)

        // Update encoding/line ending display for the switched tab
        statusBarView.updateEncoding(tab.encoding)
        statusBarView.updateLineEnding(tab.lineEnding)

        // Update word count
        editorVC?.bridge.getWordCount(tabId: tab.id) { [weak self] count in
            self?.statusBarView.updateWordCount(count)
        }

        // Update file tree to show the switched-to file's parent directory
        if let path = tab.filePath {
            let dirURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
            let currentRoot = fileTreeVC.rootURL
            if currentRoot == nil || !path.hasPrefix(currentRoot!.path) {
                fileTreeVC.rootURL = dirURL
                fileWatcher.watch(directory: dirURL)
                window?.title = "Marker — \(dirURL.lastPathComponent)"
            }
            // Highlight the current file in the file tree
            fileTreeVC.selectFile(at: URL(fileURLWithPath: path))
        }

        // Re-run search on the new tab if find bar is open
        if !findBarView.isHidden {
            let query = findBarView.searchField.stringValue
            if query.isEmpty {
                findBarView.updateResults(count: 0, index: -1)
            } else {
                findBar(findBarView, didSearchFor: query, options: findBarView.options)
            }
        }
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
        // Update word count
        editorVC?.bridge.getWordCount(tabId: tab.id) { [weak self] count in
            self?.statusBarView.updateWordCount(count)
        }
    }
}

// MARK: - FileWatcherDelegate

extension MainWindowController: FileWatcherDelegate {
    func fileWatcher(_ watcher: FileWatcher, didDetectChangesAt paths: [String]) {
        // Refresh file tree
        if fileTreeVC.rootURL != nil {
            fileTreeVC.rootURL = fileTreeVC.rootURL  // triggers reload
        }

        for path in paths {
            guard let tab = tabManager.tabByFilePath(path) else { continue }

            if !FileManager.default.fileExists(atPath: path) {
                // File was deleted — mark tab as orphaned
                tabBarView.updateTitle(id: tab.id, title: "⚠ \(tab.title)")
                continue
            }

            if tab.isDirty {
                // Dirty tab + external change — ask user
                let alert = NSAlert()
                alert.messageText = "File Changed on Disk"
                alert.informativeText = "\(tab.title) has been modified externally. Reload from disk or keep your changes?"
                alert.addButton(withTitle: "Reload")
                alert.addButton(withTitle: "Keep Mine")
                alert.alertStyle = .warning

                if alert.runModal() == .alertFirstButtonReturn {
                    (NSApp.delegate as? AppDelegate)?.reloadTab(id: tab.id, path: path)
                }
            } else {
                // Clean tab — silently reload
                (NSApp.delegate as? AppDelegate)?.reloadTab(id: tab.id, path: path)
            }
        }
    }
}

// MARK: - Find & Replace

extension MainWindowController {
    func showFind() {
        findBarHeightConstraint.isActive = false
        findBarView.show(withReplace: false)
    }

    func showFindReplace() {
        findBarHeightConstraint.isActive = false
        findBarView.show(withReplace: true)
    }
}

extension MainWindowController: FindBarDelegate {
    func findBar(_ bar: FindBarView, didSearchFor query: String, options: FindBarView.Options) {
        guard let tabId = tabManager.activeTabId else { return }
        editorVC?.bridge.find(tabId: tabId, query: query, caseSensitive: options.caseSensitive, wholeWord: options.wholeWord, useRegex: options.useRegex) { count, index in
            bar.updateResults(count: count, index: index)
        }
    }

    func findBarDidRequestNext(_ bar: FindBarView) {
        guard let tabId = tabManager.activeTabId else { return }
        editorVC?.bridge.findNext(tabId: tabId) { count, index in
            bar.updateResults(count: count, index: index)
        }
    }

    func findBarDidRequestPrev(_ bar: FindBarView) {
        guard let tabId = tabManager.activeTabId else { return }
        editorVC?.bridge.findPrev(tabId: tabId) { count, index in
            bar.updateResults(count: count, index: index)
        }
    }

    func findBar(_ bar: FindBarView, didReplace replacement: String) {
        guard let tabId = tabManager.activeTabId else { return }
        let opts = bar.options
        editorVC?.bridge.replaceOne(tabId: tabId, replacement: replacement, query: bar.searchField.stringValue, caseSensitive: opts.caseSensitive, wholeWord: opts.wholeWord, useRegex: opts.useRegex) { count, index in
            bar.updateResults(count: count, index: index)
        }
    }

    func findBar(_ bar: FindBarView, didReplaceAll replacement: String) {
        guard let tabId = tabManager.activeTabId else { return }
        let opts = bar.options
        editorVC?.bridge.replaceAllMatches(tabId: tabId, query: bar.searchField.stringValue, replacement: replacement, caseSensitive: opts.caseSensitive, wholeWord: opts.wholeWord, useRegex: opts.useRegex) { replacedCount in
            bar.showReplacedCount(replacedCount)
        }
    }

    func findBarDidClose(_ bar: FindBarView) {
        // Collapse the find bar height when closed
        if bar.isHidden {
            findBarHeightConstraint.isActive = true
        }
        guard let tabId = tabManager.activeTabId else { return }
        editorVC?.bridge.clearSearch(tabId: tabId)
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
