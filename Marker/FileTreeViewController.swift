import Cocoa

protocol FileTreeDelegate: AnyObject {
    func fileTree(didSelectFile url: URL)
}

class FileTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var delegate: FileTreeDelegate?

    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var rootNode: FileNode?

    var rootURL: URL? {
        didSet {
            if let url = rootURL {
                rootNode = FileNode(url: url)
                rootNode?.loadChildren()
            } else {
                rootNode = nil
            }
            outlineView?.reloadData()
        }
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0).cgColor

        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 16
        outlineView.rowHeight = 22
        outlineView.backgroundColor = .clear
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.target = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Context menu
        let menu = NSMenu()
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Path", action: #selector(copyPath), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Rename…", action: #selector(renameItem), keyEquivalent: "")
        menu.addItem(withTitle: "Delete", action: #selector(deleteItem), keyEquivalent: "")
        outlineView.menu = menu

        self.view = container
    }

    // MARK: - Actions

    @objc private func doubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else if node.isMarkdown {
            delegate?.fileTree(didSelectFile: node.url)
        }
    }

    @objc private func revealInFinder() {
        guard let node = selectedNode() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func copyPath() {
        guard let node = selectedNode() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    @objc private func renameItem() {
        guard let node = selectedNode() else { return }
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter new name:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = node.name
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != node.name else { return }

        let newURL = node.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: node.url, to: newURL)
            // Reload parent
            if let parent = parentNode(of: node) {
                parent.children = nil
                parent.loadChildren()
                outlineView.reloadItem(parent, reloadChildren: true)
            } else {
                rootNode?.children = nil
                rootNode?.loadChildren()
                outlineView.reloadData()
            }
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.runModal()
        }
    }

    @objc private func deleteItem() {
        guard let node = selectedNode() else { return }
        let alert = NSAlert()
        alert.messageText = "Move to Trash?"
        alert.informativeText = node.name
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            if let parent = parentNode(of: node) {
                parent.children = nil
                parent.loadChildren()
                outlineView.reloadItem(parent, reloadChildren: true)
            } else {
                rootNode?.children = nil
                rootNode?.loadChildren()
                outlineView.reloadData()
            }
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.runModal()
        }
    }

    private func selectedNode() -> FileNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileNode
    }

    private func parentNode(of child: FileNode) -> FileNode? {
        return outlineView.parent(forItem: child) as? FileNode
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootNode?.children?.count ?? 0
        }
        guard let node = item as? FileNode else { return 0 }
        node.loadChildren()
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootNode!.children![index]
        }
        let node = item as! FileNode
        return node.children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.isDirectory
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let cellID = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        cell.textField?.stringValue = node.name

        if node.isDirectory {
            cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
            cell.imageView?.contentTintColor = .systemBlue
            cell.textField?.textColor = .labelColor
        } else if node.isMarkdown {
            cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Markdown")
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.textField?.textColor = .labelColor
        } else {
            cell.imageView?.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "File")
            cell.imageView?.contentTintColor = .tertiaryLabelColor
            cell.textField?.textColor = .tertiaryLabelColor
        }

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        if node.isMarkdown {
            delegate?.fileTree(didSelectFile: node.url)
        }
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        node.loadChildren()
    }
}
