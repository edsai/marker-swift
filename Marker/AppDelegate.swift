import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, EditorDelegate {
    var windowController: MainWindowController!
    var pendingFiles: [String] = []
    private var bridgeReady = false
    private var preferencesController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MenuBuilder.buildMainMenu()
        NSLog("Marker: applicationDidFinishLaunching")

        windowController = MainWindowController()

        // Create and embed editor view controller
        let editorVC = EditorWebViewController()
        editorVC.delegate = self
        windowController.editorVC = editorVC
        editorVC.loadEditor()

        windowController.showWindow(nil)
        windowController.setInitialDividerPositions()
        windowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save session before terminating
        SessionManager.save(tabManager: windowController.tabManager, workspaceURL: windowController.fileTreeVC.rootURL)
        // Break WKUserContentController → MessageHandler retain before exit
        windowController.editorVC?.cleanup()
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            if bridgeReady {
                openFile(path: filename)
            } else {
                pendingFiles.append(filename)
            }
        }
        application.reply(toOpenOrPrint: .success)
    }

    func openFile(path: String) {
        let fileContent: FileContent
        do {
            fileContent = try FileIO.readFile(at: path)
        } catch {
            NSLog("Marker: Failed to read file: \(error)")
            return
        }

        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        let title = (path as NSString).lastPathComponent
        let dirPath = (path as NSString).deletingLastPathComponent
        let resolved = Self.resolveImagePaths(in: fileContent.content, baseDir: dirPath)

        windowController.editorVC?.bridge.openTab(id: tabId, content: resolved) { [weak self] success in
            guard success else { return }
            self?.windowController.tabManager.addTab(id: tabId, title: title, filePath: path)
            // Update status bar with file metadata
            self?.windowController.statusBarView.updateEncoding(fileContent.encoding.displayName)
            self?.windowController.statusBarView.updateLineEnding(fileContent.lineEnding.rawValue)
        }
    }

    func reloadTab(id: String, path: String) {
        let fileContent: FileContent
        do {
            fileContent = try FileIO.readFile(at: path)
        } catch {
            NSLog("Marker: Failed to reload file: \(error)")
            return
        }

        let dirPath = (path as NSString).deletingLastPathComponent
        let resolved = Self.resolveImagePaths(in: fileContent.content, baseDir: dirPath)

        // Re-open the tab with fresh content (openTab on an existing tab replaces content)
        windowController.editorVC?.bridge.openTab(id: id, content: resolved)
        windowController.tabManager.setDirty(id: id, isDirty: false)
    }

    /// Resolve relative image paths in markdown to marker-file:// absolute URLs.
    /// Handles: ![alt](./path), ![alt](../path), ![alt](relative/path)
    /// Skips: ![alt](https://...), ![alt](data:...), ![alt](marker-file://...), ![alt](/absolute/path)
    static func resolveImagePaths(in markdown: String, baseDir: String) -> String {
        // Match markdown image syntax: ![...](path)
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown }

        var result = markdown
        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

        // Process in reverse so ranges stay valid
        for match in matches.reversed() {
            guard let pathRange = Range(match.range(at: 2), in: markdown) else { continue }
            let imagePath = String(markdown[pathRange])

            // Skip absolute URLs, data URIs, and already-resolved paths
            if imagePath.hasPrefix("http://") || imagePath.hasPrefix("https://") ||
               imagePath.hasPrefix("data:") || imagePath.hasPrefix("marker-file://") ||
               imagePath.hasPrefix("blob:") {
                continue
            }

            // Resolve relative path against document directory
            let absolutePath: String
            if imagePath.hasPrefix("/") {
                absolutePath = imagePath
            } else {
                absolutePath = (baseDir as NSString).appendingPathComponent(imagePath)
            }

            // Standardize the path (resolve ../ etc.)
            let standardized = (absolutePath as NSString).standardizingPath
            let markerURL = "marker-file://\(standardized)"

            // Replace in result
            let fullMatchRange = Range(match.range, in: result)!
            let alt = match.range(at: 1)
            let altText = String(result[Range(alt, in: result)!])
            result.replaceSubrange(fullMatchRange, with: "![\(altText)](\(markerURL))")
        }
        return result
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController.showWindow(nil)
        }
        return true
    }

    // MARK: - EditorDelegate

    func editorDidBecomeReady() {
        if bridgeReady {
            // This is a crash recovery — re-open all existing tabs
            NSLog("Marker: bridge re-ready (crash recovery), restoring \(windowController.tabManager.tabs.count) tabs")
            for tab in windowController.tabManager.tabs {
                if let path = tab.filePath {
                    windowController.editorVC?.bridge.openTab(id: tab.id, content: (try? FileIO.readFile(at: path).content) ?? "")
                }
            }
            if let activeId = windowController.tabManager.activeTabId {
                windowController.editorVC?.bridge.switchTab(id: activeId)
            }
            return
        }

        bridgeReady = true
        windowController.tabManager.addTab(id: "welcome", title: "Welcome")
        NSLog("Marker: bridge ready, opening \(pendingFiles.count) pending files")
        for file in pendingFiles {
            openFile(path: file)
        }
        pendingFiles.removeAll()

        // Restore session
        restoreSession()

        // Apply saved preferences
        let defaults = UserDefaults.standard
        let fontSize = defaults.integer(forKey: "editorFontSize")
        if fontSize > 0 {
            windowController.editorVC?.bridge.setFontSize(fontSize)
        }
        let fontFamily = defaults.string(forKey: "editorFontFamily") ?? ""
        if !fontFamily.isEmpty && fontFamily != "System Default" {
            windowController.editorVC?.bridge.setFontFamily(fontFamily)
        }
    }

    private func restoreSession() {
        guard let state = SessionManager.restore() else { return }

        // Restore workspace
        if let workspacePath = state.workspaceURL {
            let url = URL(fileURLWithPath: workspacePath)
            if FileManager.default.fileExists(atPath: workspacePath) {
                windowController.fileTreeVC.rootURL = url
                windowController.fileWatcher.watch(directory: url)
                windowController.window?.title = "Marker — \(url.lastPathComponent)"
            }
        }

        // Restore tabs (only those with file paths that still exist)
        for tab in state.tabs {
            guard let path = tab.filePath,
                  FileManager.default.fileExists(atPath: path),
                  tab.id != "welcome" else { continue }
            openFile(path: path)
        }
    }

    func editor(didChangeDirty tabId: String, isDirty: Bool) {
        windowController.tabManager.setDirty(id: tabId, isDirty: isDirty)
    }

    func editor(didChangeCursor tabId: String, line: Int, col: Int) {
        windowController.updateCursorPosition(line: line, col: col)
    }

    func editor(didReceiveMarkdown tabId: String, content: String?) {
        // Used by B7 (file save) — log for now
        NSLog("Marker: received markdown for \(tabId), length=\(content?.count ?? 0)")
    }

    func editor(didEvictTab tabId: String, markdown: String) {
        // Used by B9 (session persistence) — log for now
        NSLog("Marker: tab \(tabId) evicted from pool")
    }

    func editor(didPasteImage tabId: String, base64: String, fileExtension: String) {
        // Used by B7 (image save) — log for now
        NSLog("Marker: image pasted in \(tabId)")
    }

    // MARK: - Menu Actions

    @objc func newTab() {
        windowController.tabBarDidRequestNewTab()
    }

    @objc func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!, .plainText]

        panel.beginSheetModal(for: windowController.window!) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openFile(path: url.path)
            }
        }
    }

    @objc func openFolderDialog() {
        windowController.openFolder()
    }

    @objc func saveCurrentTab() {
        guard let tab = windowController.tabManager.activeTab,
              let path = tab.filePath else {
            saveCurrentTabAs()  // No file path → Save As
            return
        }

        windowController.editorVC?.bridge.requestMarkdown(id: tab.id) { [weak self] content in
            guard let content = content else { return }
            // TODO: Store encoding/lineEnding per tab (B9). For now use defaults.
            do {
                try FileIO.writeFile(at: path, content: content, encoding: .utf8, lineEnding: .lf)
                self?.windowController.tabManager.setDirty(id: tab.id, isDirty: false)
                NSLog("Marker: saved \(path)")
            } catch {
                NSLog("Marker: save failed: \(error)")
            }
        }
    }

    @objc func saveCurrentTabAs() {
        guard let tab = windowController.tabManager.activeTab else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = tab.title

        panel.beginSheetModal(for: windowController.window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            self?.windowController.editorVC?.bridge.requestMarkdown(id: tab.id) { content in
                guard let content = content else { return }
                do {
                    try FileIO.writeFile(at: url.path, content: content, encoding: .utf8, lineEnding: .lf)
                    // Update tab with new file path
                    // For now just clear dirty since TabManager doesn't support updating filePath
                    self?.windowController.tabManager.setDirty(id: tab.id, isDirty: false)
                    NSLog("Marker: saved as \(url.path)")
                } catch {
                    NSLog("Marker: save as failed: \(error)")
                }
            }
        }
    }

    @objc func closeCurrentTab() {
        guard let tab = windowController.tabManager.activeTab else { return }
        windowController.tabManager.closeTab(id: tab.id)
    }

    @objc func toggleSidebar() {
        windowController.toggleLeftSidebar()
    }

    @objc func toggleOutline() {
        windowController.toggleRightSidebar()
    }

    @objc func showPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        preferencesController?.showWindow(nil)
        preferencesController?.window?.makeKeyAndOrderFront(nil)
    }
}
