import Foundation

class FileNode {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?  // nil = not yet loaded, [] = empty dir

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown"].contains(ext)
    }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    /// Lazily load children for directories
    func loadChildren() {
        guard isDirectory, children == nil else { return }

        let hiddenPrefixes: Set<String> = [".git", ".DS_Store", "node_modules", ".build", ".swiftpm"]

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            children = contents
                .filter { !hiddenPrefixes.contains($0.lastPathComponent) }
                .map { FileNode(url: $0) }
                .sorted { lhs, rhs in
                    // Directories first, then alphabetical
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        } catch {
            children = []
            NSLog("Marker: failed to load directory \(url.path): \(error)")
        }
    }
}
