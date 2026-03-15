import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, EditorDelegate {
    var windowController: MainWindowController!
    var pendingFiles: [String] = []
    private var bridgeReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    // MARK: - EditorDelegate

    func editorDidBecomeReady() {
        guard !bridgeReady else { return }
        bridgeReady = true
        windowController.tabManager.addTab(id: "welcome", title: "Welcome")
        NSLog("Marker: bridge ready, opening \(pendingFiles.count) pending files")
        for file in pendingFiles {
            openFile(path: file)
        }
        pendingFiles.removeAll()
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
}
