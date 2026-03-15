import Cocoa

protocol FindBarDelegate: AnyObject {
    func findBar(_ bar: FindBarView, didSearchFor query: String, options: FindBarView.Options)
    func findBarDidRequestNext(_ bar: FindBarView)
    func findBarDidRequestPrev(_ bar: FindBarView)
    func findBar(_ bar: FindBarView, didReplace replacement: String)
    func findBar(_ bar: FindBarView, didReplaceAll replacement: String)
    func findBarDidClose(_ bar: FindBarView)
}

class FindBarView: NSView, NSSearchFieldDelegate {
    struct Options {
        var caseSensitive: Bool = false
        var wholeWord: Bool = false
        var useRegex: Bool = false
    }

    weak var delegate: FindBarDelegate?

    let searchField = NSSearchField()
    let replaceField = NSTextField()
    let resultLabel = NSTextField(labelWithString: "")
    private let nextButton = NSButton(title: "▼", target: nil, action: nil)
    private let prevButton = NSButton(title: "▲", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "All", target: nil, action: nil)
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private let caseSensitiveButton = NSButton(title: "Aa", target: nil, action: nil)
    private let wholeWordButton = NSButton(title: "W", target: nil, action: nil)
    private let regexButton = NSButton(title: ".*", target: nil, action: nil)

    private var showReplace = false
    private var replaceRow: NSStackView!
    private var lastQuery = ""  // Track if query changed vs same (for Enter = next)

    var options = Options()

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: showReplace ? 64 : 32)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Search row
        searchField.placeholderString = "Find"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.delegate = self  // For controlTextDidChange (live search)
        searchField.target = self
        searchField.action = #selector(enterPressed)  // Enter = next match
        searchField.translatesAutoresizingMaskIntoConstraints = false

        for btn in [nextButton, prevButton, closeButton, caseSensitiveButton, wholeWordButton, regexButton] {
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.contentTintColor = .secondaryLabelColor
            btn.setContentHuggingPriority(.required, for: .horizontal)
        }

        caseSensitiveButton.toolTip = "Case Sensitive"
        wholeWordButton.toolTip = "Whole Word"
        regexButton.toolTip = "Regular Expression"

        nextButton.target = self; nextButton.action = #selector(nextClicked)
        prevButton.target = self; prevButton.action = #selector(prevClicked)
        closeButton.target = self; closeButton.action = #selector(closeClicked)
        caseSensitiveButton.target = self; caseSensitiveButton.action = #selector(toggleCaseSensitive)
        wholeWordButton.target = self; wholeWordButton.action = #selector(toggleWholeWord)
        regexButton.target = self; regexButton.action = #selector(toggleRegex)

        resultLabel.font = NSFont.systemFont(ofSize: 11)
        resultLabel.textColor = .tertiaryLabelColor
        resultLabel.setContentHuggingPriority(.required, for: .horizontal)

        let searchRow = NSStackView(views: [searchField, resultLabel, caseSensitiveButton, wholeWordButton, regexButton, prevButton, nextButton, closeButton])
        searchRow.orientation = .horizontal
        searchRow.spacing = 4
        searchRow.alignment = .centerY
        searchRow.translatesAutoresizingMaskIntoConstraints = false

        // Replace row
        replaceField.placeholderString = "Replace"
        replaceField.font = NSFont.systemFont(ofSize: 12)
        replaceField.translatesAutoresizingMaskIntoConstraints = false

        for btn in [replaceButton, replaceAllButton] {
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.contentTintColor = .secondaryLabelColor
            btn.setContentHuggingPriority(.required, for: .horizontal)
        }
        replaceButton.target = self; replaceButton.action = #selector(replaceClicked)
        replaceAllButton.target = self; replaceAllButton.action = #selector(replaceAllClicked)

        replaceRow = NSStackView(views: [replaceField, replaceButton, replaceAllButton])
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 4
        replaceRow.alignment = .centerY
        replaceRow.translatesAutoresizingMaskIntoConstraints = false
        replaceRow.isHidden = true

        let stack = NSStackView(views: [searchRow, replaceRow])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Bottom separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            replaceField.widthAnchor.constraint(equalTo: searchField.widthAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    // MARK: - Keyboard

    /// Escape closes the find bar
    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    /// Cmd+G / Cmd+Shift+G from within the search field
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHidden else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "g" {
            if event.modifierFlags.contains(.shift) {
                delegate?.findBarDidRequestPrev(self)
            } else {
                delegate?.findBarDidRequestNext(self)
            }
            return true
        }
        // Escape
        if event.keyCode == 53 {
            hide()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - NSSearchFieldDelegate — live search on every keystroke

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue
        if query.isEmpty {
            resultLabel.stringValue = ""
            lastQuery = ""
            delegate?.findBarDidClose(self)  // Clear highlights
            return
        }
        lastQuery = query
        delegate?.findBar(self, didSearchFor: query, options: options)
    }

    // MARK: - Public

    func show(withReplace: Bool = false) {
        isHidden = false
        showReplace = withReplace
        replaceRow.isHidden = !withReplace
        invalidateIntrinsicContentSize()
        window?.makeFirstResponder(searchField)
    }

    func hide() {
        isHidden = true
        invalidateIntrinsicContentSize()
        delegate?.findBarDidClose(self)
    }

    func updateResults(count: Int, index: Int) {
        if count == 0 {
            resultLabel.stringValue = searchField.stringValue.isEmpty ? "" : "No results"
        } else {
            resultLabel.stringValue = "\(index + 1) of \(count)"
        }
    }

    // MARK: - Actions

    /// Enter in the search field = find next (not re-search)
    @objc private func enterPressed() {
        let query = searchField.stringValue
        guard !query.isEmpty else { return }
        delegate?.findBarDidRequestNext(self)
    }

    @objc private func nextClicked() { delegate?.findBarDidRequestNext(self) }
    @objc private func prevClicked() { delegate?.findBarDidRequestPrev(self) }
    @objc private func closeClicked() { hide() }

    @objc private func replaceClicked() {
        delegate?.findBar(self, didReplace: replaceField.stringValue)
    }

    @objc private func replaceAllClicked() {
        delegate?.findBar(self, didReplaceAll: replaceField.stringValue)
    }

    @objc private func toggleCaseSensitive() {
        options.caseSensitive.toggle()
        caseSensitiveButton.contentTintColor = options.caseSensitive ? .controlAccentColor : .secondaryLabelColor
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }

    @objc private func toggleWholeWord() {
        options.wholeWord.toggle()
        wholeWordButton.contentTintColor = options.wholeWord ? .controlAccentColor : .secondaryLabelColor
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }

    @objc private func toggleRegex() {
        options.useRegex.toggle()
        regexButton.contentTintColor = options.useRegex ? .controlAccentColor : .secondaryLabelColor
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }
}
