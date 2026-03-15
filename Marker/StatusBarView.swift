import Cocoa

class StatusBarView: NSView {
    private let filePathLabel = NSTextField(labelWithString: "")
    private let cursorLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let encodingLabel = NSTextField(labelWithString: "UTF-8")
    private let lineEndingLabel = NSTextField(labelWithString: "LF")
    private let wordCountLabel = NSTextField(labelWithString: "0 words")

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 24)
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
        layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0).cgColor

        let labels = [filePathLabel, cursorLabel, encodingLabel, lineEndingLabel, wordCountLabel]
        for label in labels {
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        // File path on the left, everything else on the right
        filePathLabel.lineBreakMode = .byTruncatingMiddle
        filePathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Separators between right-side items
        let sep1 = makeSeparator()
        let sep2 = makeSeparator()
        let sep3 = makeSeparator()

        NSLayoutConstraint.activate([
            filePathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            filePathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            filePathLabel.trailingAnchor.constraint(lessThanOrEqualTo: wordCountLabel.leadingAnchor, constant: -12),

            wordCountLabel.trailingAnchor.constraint(equalTo: sep3.leadingAnchor, constant: -6),
            wordCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            sep3.trailingAnchor.constraint(equalTo: lineEndingLabel.leadingAnchor, constant: -6),
            sep3.centerYAnchor.constraint(equalTo: centerYAnchor),

            lineEndingLabel.trailingAnchor.constraint(equalTo: sep2.leadingAnchor, constant: -6),
            lineEndingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            sep2.trailingAnchor.constraint(equalTo: encodingLabel.leadingAnchor, constant: -6),
            sep2.centerYAnchor.constraint(equalTo: centerYAnchor),

            encodingLabel.trailingAnchor.constraint(equalTo: sep1.leadingAnchor, constant: -6),
            encodingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            sep1.trailingAnchor.constraint(equalTo: cursorLabel.leadingAnchor, constant: -6),
            sep1.centerYAnchor.constraint(equalTo: centerYAnchor),

            cursorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cursorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeSeparator() -> NSTextField {
        let sep = NSTextField(labelWithString: "|")
        sep.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sep.textColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.5)
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)
        return sep
    }

    // MARK: - Public API

    func updateCursor(line: Int, col: Int) {
        cursorLabel.stringValue = "Ln \(line), Col \(col)"
    }

    func updateFilePath(_ path: String?) {
        filePathLabel.stringValue = path ?? ""
    }

    func updateEncoding(_ encoding: String) {
        encodingLabel.stringValue = encoding
    }

    func updateLineEnding(_ ending: String) {
        lineEndingLabel.stringValue = ending
    }

    func updateWordCount(_ count: Int) {
        wordCountLabel.stringValue = "\(count) words"
    }
}
