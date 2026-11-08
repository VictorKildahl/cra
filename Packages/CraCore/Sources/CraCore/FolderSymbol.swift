import Foundation

public enum FolderSymbol: String, Codable, CaseIterable {
    case star, bookmark, heart, bolt, triangle, asterisk, bell, lightbulb
    case chat, people, tools, egg, circle, moon, planet, leaf
    case cloud, paw, cutlery, airplane, music, video, code, skull

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        let name = try value.decode(String.self)
        guard let symbol = Self(rawValue: name == "pizza" ? "leaf" : name) else {
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown folder symbol: \(name)")
        }
        self = symbol
    }
}
