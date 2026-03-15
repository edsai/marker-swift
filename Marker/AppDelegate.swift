import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var windowController: MainWindowController!
    var webView: WKWebView!
    var pendingFiles: [String] = []
    private var messageHandler: MessageHandler?
    private var bridgeReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Marker: applicationDidFinishLaunching")

        // Create main window controller (creates window + layout)
        windowController = MainWindowController()

        // Create WKWebView
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let contentController = WKUserContentController()
        let handler = MessageHandler(appDelegate: self)
        messageHandler = handler
        contentController.add(handler, name: "marker")
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.black.cgColor

        // Pass webview to window controller (places it in center pane)
        windowController.webView = webView

        // Load editor from bundle resources
        let editorURL = Bundle.main.url(forResource: "editor", withExtension: "html")
        NSLog("Marker: editor URL = \(String(describing: editorURL))")

        if let url = editorURL {
            let resourceDir = url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
        } else {
            NSLog("Marker: ERROR - editor.html not found!")
        }

        windowController.showWindow(nil)
        windowController.setInitialDividerPositions()
        windowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove script message handler to prevent WKUserContentController leak
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "marker")
    }

    // WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("Marker: page finished loading")
    }

    /// Called by MessageHandler when JS bridge posts "ready"
    func bridgeDidBecomeReady() {
        guard !bridgeReady else { return }  // Guard against duplicate "ready" messages
        bridgeReady = true
        NSLog("Marker: bridge ready, opening \(pendingFiles.count) pending files")
        for file in pendingFiles {
            openFile(path: file)
        }
        pendingFiles.removeAll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("Marker: navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("Marker: provisional navigation failed: \(error)")
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
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        let title = (path as NSString).lastPathComponent

        // Use callAsyncJavaScript with parameters to safely pass content (handles all Unicode)
        webView.callAsyncJavaScript(
            "await marker.openTab(tabId, content)",
            arguments: ["tabId": tabId, "content": content],
            in: nil,
            in: .page
        ) { [weak self] result in
            switch result {
            case .failure(let error):
                NSLog("Marker: Failed to open tab: \(error)")
            case .success:
                self?.windowController.tabManager.addTab(id: tabId, title: title, filePath: path)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - MessageHandler

class MessageHandler: NSObject, WKScriptMessageHandler {
    weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        NSLog("Marker: bridge message: \(type)")

        switch type {
        case "dirty":
            if let tabId = body["tabId"] as? String,
               let isDirty = body["isDirty"] as? Bool {
                appDelegate?.windowController.tabManager.setDirty(id: tabId, isDirty: isDirty)
            }
        case "cursorChanged":
            // B6 will handle status bar update
            break
        case "ready":
            NSLog("Marker: editor ready")
            // Register the welcome tab that marker.init() auto-creates (JS uses id "welcome")
            appDelegate?.windowController.tabManager.addTab(id: "welcome", title: "Welcome")
            appDelegate?.bridgeDidBecomeReady()
        case "markdown", "evicted", "imagePaste":
            // Handled in later issues
            break
        default:
            break
        }
    }
}
