import Cocoa

protocol TabBarViewDelegate: AnyObject {
    func tabBarDidSelectTab(id: String)
    func tabBarDidCloseTab(id: String)
    func tabBarDidRequestNewTab()
}

class TabBarView: NSView {
    weak var delegate: TabBarViewDelegate?

    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let addButton = NSButton()
    private var tabButtons: [String: TabButton] = [:]
    private var activeTabId: String?

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 36)
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
        layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0).cgColor

        // Stack view for tab buttons
        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Scroll view wrapping the stack (for many tabs)
        scrollView.documentView = stackView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Pin stack view height to scroll clip view (prevents zero-height collapse)
        NSLayoutConstraint.activate([
            stackView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
        ])

        // + button
        addButton.bezelStyle = .inline
        addButton.title = "+"
        addButton.font = NSFont.systemFont(ofSize: 16, weight: .light)
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.target = self
        addButton.action = #selector(addTabClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
        ])
    }

    // MARK: - Public API

    func addTab(id: String, title: String, isDirty: Bool = false) {
        let button = TabButton(id: id, title: title, isDirty: isDirty)
        button.onSelect = { [weak self] in self?.delegate?.tabBarDidSelectTab(id: id) }
        button.onClose = { [weak self] in self?.delegate?.tabBarDidCloseTab(id: id) }
        tabButtons[id] = button
        stackView.addArrangedSubview(button)
    }

    func removeTab(id: String) {
        guard let button = tabButtons.removeValue(forKey: id) else { return }
        stackView.removeArrangedSubview(button)
        button.removeFromSuperview()
    }

    func setActiveTab(id: String) {
        activeTabId = id
        for (tabId, button) in tabButtons {
            button.setActive(tabId == id)
        }
    }

    func updateDirty(id: String, isDirty: Bool) {
        tabButtons[id]?.setDirty(isDirty)
    }

    func updateTitle(id: String, title: String) {
        tabButtons[id]?.setTitle(title)
    }

    @objc private func addTabClicked() {
        delegate?.tabBarDidRequestNewTab()
    }
}

// MARK: - TabButton

private class TabButton: NSView {
    let id: String
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyIndicator = NSTextField(labelWithString: "●")
    private let closeButton = NSButton()
    private var isActive = false

    init(id: String, title: String, isDirty: Bool) {
        self.id = id
        super.init(frame: .zero)
        setupViews(title: title, isDirty: isDirty)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupViews(title: String, isDirty: Bool) {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        dirtyIndicator.font = NSFont.systemFont(ofSize: 8)
        dirtyIndicator.textColor = .systemOrange
        dirtyIndicator.isHidden = !isDirty
        dirtyIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dirtyIndicator)

        closeButton.bezelStyle = .inline
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 10)
        closeButton.isBordered = false
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        titleLabel.stringValue = title

        NSLayoutConstraint.activate([
            dirtyIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dirtyIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: dirtyIndicator.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 140),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            heightAnchor.constraint(equalToConstant: 28),
        ])

        updateAppearance()
    }

    // Use mouseDown instead of NSClickGestureRecognizer to avoid competing with close button
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // If click is on the close button, let it handle it
        if closeButton.frame.contains(location) {
            return
        }
        onSelect?()
    }

    func setActive(_ active: Bool) {
        isActive = active
        updateAppearance()
    }

    func setDirty(_ isDirty: Bool) {
        dirtyIndicator.isHidden = !isDirty
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    private func updateAppearance() {
        layer?.backgroundColor = isActive
            ? NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0).cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isActive ? .labelColor : .secondaryLabelColor
        layer?.cornerRadius = 4
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
