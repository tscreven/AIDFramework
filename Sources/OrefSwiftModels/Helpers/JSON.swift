import Foundation

// MARK: - JSON Protocol

@dynamicMemberLookup public protocol JSON: Codable {
    var rawJSON: String { get }
    init?(from: String)
}

public extension JSON {
    var rawJSON: RawJSON {
        String(data: try! JSONCoding.encoder.encode(self), encoding: .utf8)!
    }

    init?(from: String) {
        guard let data = from.data(using: .utf8) else {
            return nil
        }

        do {
            let object = try JSONCoding.decoder.decode(Self.self, from: data)
            self = object
        } catch {
            return nil
        }
    }

    var dictionaryRepresentation: [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    subscript(dynamicMember string: String) -> Any? {
        dictionaryRepresentation?[string]
    }
}

extension String: JSON {
    public var rawJSON: String { self }
    public init?(from: String) { self = from }
}

extension Double: JSON {}
extension Int: JSON {}
extension Bool: JSON {}
extension Decimal: JSON {}

extension Date: JSON {
    public init?(from: String) {
        let dateFormatter = Formatter.iso8601withFractionalSeconds
        let string = from.replacingOccurrences(of: "\"", with: "")
        if let date = dateFormatter.date(from: string) {
            self = date
        } else {
            return nil
        }
    }
}

public typealias RawJSON = String

public extension RawJSON {
    static let null = "null"
    static let empty = ""
}

extension Array: JSON where Element: JSON {}
extension Dictionary: JSON where Key: JSON, Value: JSON {}

public extension Dictionary where Key == String {
    var rawJSON: RawJSON? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: .prettyPrinted) else { return nil }
        return RawJSON(data: data, encoding: .utf8)
    }
}
