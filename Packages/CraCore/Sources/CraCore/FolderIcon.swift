public struct FolderIcon: Codable, Equatable {
    public var color: FolderIconStyle?
    public var symbol: FolderSymbol?

    public var isEmpty: Bool { color == nil && symbol == nil }

    public init(color: FolderIconStyle? = nil, symbol: FolderSymbol? = nil) {
        self.color = color
        self.symbol = symbol
    }

    private enum CodingKeys: String, CodingKey { case color, symbol }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let color = try? value.decode(FolderIconStyle.self) {
            self.init(color: color)
        } else {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            self.init(color: try fields.decodeIfPresent(FolderIconStyle.self, forKey: .color),
                      symbol: try fields.decodeIfPresent(FolderSymbol.self, forKey: .symbol))
        }
    }

    public func encode(to encoder: Encoder) throws {
        if symbol == nil, let color {
            var value = encoder.singleValueContainer()
            try value.encode(color)
        } else {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encodeIfPresent(color, forKey: .color)
            try fields.encodeIfPresent(symbol, forKey: .symbol)
        }
    }
}
