import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var pendingFiles: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create window
        let windowRect = NSRect(x: 0, y: 0, width: 1200, height: 800)
        window = NSWindow(contentRect: windowRect,
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered,
                         defer: false)
        window.center()
        window.title = "Marker"
        window.minSize = NSSize(width: 600, height: 400)

        // Create WKWebView
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(MessageHandler(), name: "marker")
        config.userContentController = contentController

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)

        // Load editor from bundle resources
        let editorURL = Bundle.main.url(forResource: "editor", withExtension: "html")
        if let url = editorURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("ERROR: editor.html not found in bundle!")
            print("Bundle path: \(Bundle.main.bundlePath)")
            print("Resource path: \(Bundle.main.resourcePath ?? "nil")")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Initialize editor after page loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.webView.evaluateJavaScript("marker.init()") { _, error in
                if let error = error {
                    print("Failed to init editor: \(error)")
                } else {
                    // Open any pending files
                    for file in self.pendingFiles {
                        self.openFile(path: file)
                    }
                    self.pendingFiles.removeAll()
                }
            }
        }
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            if webView != nil {
                openFile(path: filename)
            } else {
                pendingFiles.append(filename)
            }
        }
        application.reply(toOpenOrPrint: .success)
    }

    func openFile(path: String) {
        // Read file and open in editor
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }
        let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                            .replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
        let tabId = "tab-\(Int(Date().timeIntervalSince1970 * 1000))"
        webView.evaluateJavaScript("marker.openTab('\(tabId)', '\(escaped)')") { _, error in
            if let error = error {
                print("Failed to open tab: \(error)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

class MessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "dirty":
            let tabId = body["tabId"] as? String ?? ""
            let isDirty = body["isDirty"] as? Bool ?? false
            print("Tab \(tabId) dirty: \(isDirty)")
        case "cursorChanged":
            let line = body["line"] as? Int ?? 1
            let col = body["col"] as? Int ?? 1
            print("Cursor: Ln \(line), Col \(col)")
        case "markdown":
            let tabId = body["tabId"] as? String ?? ""
            let content = body["content"] as? String ?? ""
            print("Markdown for \(tabId): \(content.prefix(50))...")
        case "imagePaste":
            let tabId = body["tabId"] as? String ?? ""
            print("Image paste in tab \(tabId)")
        case "evicted":
            let tabId = body["tabId"] as? String ?? ""
            print("Tab evicted: \(tabId)")
        default:
            print("Unknown message type: \(type)")
        }
    }
}
