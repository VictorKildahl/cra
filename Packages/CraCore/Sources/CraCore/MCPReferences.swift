import Foundation

/// A reference never changes identity. Navigation discards refs rather than reusing them.
public struct MCPReferences {
    private var document = ""
    private var sequence = 0
    private let prefix = UUID().uuidString.lowercased()
    private var nodes: [String: Int] = [:]
    private var refs: [Int: String] = [:]
    public init() {}

    public mutating func reference(node: Int, document: String) -> String? {
        if self.document != document {
            self.document = document
            nodes.removeAll(); refs.removeAll()
        }
        if let ref = refs[node] { return ref }
        guard nodes.count < 2000 else { return nil }
        sequence += 1
        let ref = "e-\(prefix)-\(sequence)"
        nodes[ref] = node; refs[node] = ref
        return ref
    }

    public mutating func retain(nodes current: Set<Int>, document: String) {
        guard self.document == document else { return }
        nodes = nodes.filter { current.contains($0.value) }
        refs = refs.filter { current.contains($0.key) }
    }

    public func resolve(_ ref: String, document: String) -> Int? {
        guard self.document == document else { return nil }
        return nodes[ref]
    }
}
