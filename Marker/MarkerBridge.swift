import WebKit

/// Typed Swift API over the JS marker.* bridge.
/// All marker.* functions are async in JS — uses callAsyncJavaScript to await them.
class MarkerBridge {
    private weak var webView: WKWebView?

    /// Pending requestMarkdown callbacks keyed by tabId
    private var markdownCallbacks: [String: (String?) -> Void] = [:]

    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Tab Operations

    func openTab(id: String, content: String, completion: ((Bool) -> Void)? = nil) {
        callAsync("await marker.openTab(tabId, content)",
                  arguments: ["tabId": id, "content": content]) { success in
            completion?(success)
        }
    }

    func switchTab(id: String) {
        callAsync("await marker.switchTab(tabId, content)",
                  arguments: ["tabId": id, "content": ""])
    }

    func closeTab(id: String) {
        callAsync("await marker.closeTab(tabId)",
                  arguments: ["tabId": id])
    }

    // MARK: - Content

    func requestMarkdown(id: String, completion: @escaping (String?) -> Void) {
        markdownCallbacks[id] = completion
        callAsync("await marker.requestMarkdown(tabId)",
                  arguments: ["tabId": id])
    }

    /// Called by MessageHandler when JS posts {type: "markdown", tabId, content}
    func handleMarkdownResponse(tabId: String, content: String?) {
        let callback = markdownCallbacks.removeValue(forKey: tabId)
        callback?(content)
    }

    // MARK: - Navigation

    func scrollToHeading(tabId: String, index: Int) {
        callAsync("marker.scrollToHeading(tabId, index)",
                  arguments: ["tabId": tabId, "index": index])
    }

    // MARK: - Appearance

    func setTheme(_ theme: String) {
        callAsync("marker.setTheme(theme)", arguments: ["theme": theme])
    }

    func setFontSize(_ px: Int) {
        callAsync("marker.setFontSize(px)", arguments: ["px": px])
    }

    func setFontFamily(_ family: String) {
        callAsync("marker.setFontFamily(family)", arguments: ["family": family])
    }

    // MARK: - Search

    func find(tabId: String, query: String, caseSensitive: Bool, wholeWord: Bool, useRegex: Bool, completion: @escaping (Int, Int) -> Void) {
        webView?.callAsyncJavaScript(
            "return marker.find(tabId, query, caseSensitive, wholeWord, useRegex)",
            arguments: ["tabId": tabId, "query": query, "caseSensitive": caseSensitive, "wholeWord": wholeWord, "useRegex": useRegex],
            in: nil, in: .page
        ) { result in
            if case .success(let value) = result,
               let dict = value as? [String: Any],
               let count = dict["count"] as? Int,
               let index = dict["currentIndex"] as? Int {
                completion(count, index)
            } else {
                completion(0, -1)
            }
        }
    }

    func findNext(tabId: String, completion: @escaping (Int, Int) -> Void) {
        webView?.callAsyncJavaScript(
            "return marker.findNext(tabId)",
            arguments: ["tabId": tabId],
            in: nil, in: .page
        ) { result in
            if case .success(let value) = result,
               let dict = value as? [String: Any],
               let count = dict["count"] as? Int,
               let index = dict["currentIndex"] as? Int {
                completion(count, index)
            } else {
                completion(0, -1)
            }
        }
    }

    func findPrev(tabId: String, completion: @escaping (Int, Int) -> Void) {
        webView?.callAsyncJavaScript(
            "return marker.findPrev(tabId)",
            arguments: ["tabId": tabId],
            in: nil, in: .page
        ) { result in
            if case .success(let value) = result,
               let dict = value as? [String: Any],
               let count = dict["count"] as? Int,
               let index = dict["currentIndex"] as? Int {
                completion(count, index)
            } else {
                completion(0, -1)
            }
        }
    }

    func replaceOne(tabId: String, replacement: String, query: String, caseSensitive: Bool, wholeWord: Bool, useRegex: Bool, completion: @escaping (Int, Int) -> Void) {
        webView?.callAsyncJavaScript(
            "return marker.replaceOne(tabId, replacement, query, caseSensitive, wholeWord, useRegex)",
            arguments: ["tabId": tabId, "replacement": replacement, "query": query, "caseSensitive": caseSensitive, "wholeWord": wholeWord, "useRegex": useRegex],
            in: nil, in: .page
        ) { result in
            if case .success(let value) = result,
               let dict = value as? [String: Any],
               let count = dict["count"] as? Int,
               let index = dict["currentIndex"] as? Int {
                completion(count, index)
            } else {
                completion(0, -1)
            }
        }
    }

    func replaceAllMatches(tabId: String, query: String, replacement: String, caseSensitive: Bool, wholeWord: Bool, useRegex: Bool, completion: @escaping (Int) -> Void) {
        webView?.callAsyncJavaScript(
            "return marker.replaceAllMatches(tabId, query, replacement, caseSensitive, wholeWord, useRegex)",
            arguments: ["tabId": tabId, "query": query, "replacement": replacement, "caseSensitive": caseSensitive, "wholeWord": wholeWord, "useRegex": useRegex],
            in: nil, in: .page
        ) { result in
            if case .success(let value) = result, let count = value as? Int {
                completion(count)
            } else {
                completion(0)
            }
        }
    }

    func clearSearch(tabId: String) {
        callAsync("marker.clearSearch(tabId)", arguments: ["tabId": tabId])
    }

    // MARK: - Text Insertion

    func insertText(tabId: String, text: String) {
        callAsync("marker.insertText(tabId, text)",
                  arguments: ["tabId": tabId, "text": text])
    }

    // MARK: - Word Count

    func getWordCount(tabId: String, completion: @escaping (Int) -> Void) {
        let js = """
        (function() {
            var active = document.querySelector('.editor-tab-container[style*="display: block"] .ProseMirror');
            if (!active) return 0;
            var text = active.innerText || '';
            return text.trim().split(/\\s+/).filter(function(w) { return w.length > 0; }).length;
        })()
        """
        webView?.evaluateJavaScript(js) { result, _ in
            completion((result as? Int) ?? 0)
        }
    }

    // MARK: - Private

    private func callAsync(_ script: String, arguments: [String: Any] = [String: Any](),
                           completion: ((Bool) -> Void)? = nil) {
        webView?.callAsyncJavaScript(
            script, arguments: arguments,
            in: nil, in: .page
        ) { result in
            switch result {
            case .failure(let error):
                NSLog("Marker bridge: \(script) failed: \(error)")
                completion?(false)
            case .success:
                completion?(true)
            }
        }
    }
}
