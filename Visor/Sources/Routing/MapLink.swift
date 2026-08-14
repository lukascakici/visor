import Core
import Foundation

/// A destination somebody shared from another map app.
public struct MapLink: Hashable, Sendable {
    public let coordinate: Coordinate
    /// Whatever the link called the place, when it said. Worth keeping: it is
    /// the only thing that lets a rider tell they pasted the right one.
    public let name: String?

    public init(coordinate: Coordinate, name: String?) {
        self.coordinate = coordinate
        self.name = name
    }
}

/// Reads a shared link and finds the place in it.
///
/// This exists because searching inside this app will always be worse than
/// searching inside Google or Yandex, and there is no reason to compete: let a
/// rider find the place wherever they already find places, share it here, and
/// we do the part those apps cannot, which is talk to the display.
///
/// The parsing is deliberately forgiving. These URLs are not a documented
/// interface, they are whatever those apps happen to emit this year, so this
/// tries several shapes in order of how sure each one is and stops at the first
/// that yields a real position.
public enum MapLinkReader {
    /// Hosts that hand back a short code and nothing else. A link from one of
    /// these has to be followed before there is anything to read.
    static let shorteners = [
        "maps.app.goo.gl",
        "goo.gl",
        "g.co",
        "ya.cc",
        "yandex.com.tr/maps/-/",
        "yandex.com/maps/-/",
        "yandex.ru/maps/-/",
    ]

    /// Whether this is worth handing to `resolve` at all.
    ///
    /// What it saves is asking the map service to search for a URL, which is a
    /// request that can only come back empty and confusing.
    public static func looksLikeALink(_ text: String) -> Bool {
        firstLink(in: text) != nil || parse(text) != nil
    }

    /// Whether this text needs a round trip to the network before it says
    /// anything.
    public static func isShortened(_ text: String) -> Bool {
        guard let link = firstLink(in: text)?.lowercased() else { return false }
        return shorteners.contains { link.contains($0) }
    }

    /// Reads a link that already carries a position.
    ///
    /// Returns `nil` for a shortened link, which carries none until it is
    /// followed, and for anything that is not a map link at all.
    public static func parse(_ text: String) -> MapLink? {
        guard let link = firstLink(in: text) else {
            // Not a link. Someone may simply have pasted two numbers, which is
            // how coordinates get passed around between people.
            return pair(in: text[...]).map { MapLink(coordinate: coordinate($0.0, $0.1), name: nil) }
        }

        let lower = link.lowercased()
        let name = placeName(in: link)

        // A place URL from Google carries the pin twice: once as the map centre
        // after the @, and once as !3d and !4d, which is the place itself. They
        // are usually the same and occasionally are not, and when they differ
        // the second one is the one somebody meant to share.
        if let latitude = number(after: "!3d", in: link), let longitude = number(after: "!4d", in: link) {
            return checked(latitude, longitude, name)
        }

        // Yandex writes longitude first. Everyone else writes latitude first.
        // Getting this backwards puts Istanbul in Somalia, which is the sort of
        // mistake that looks like a routing bug for an hour.
        let yandex = lower.contains("yandex.")
        for marker in ["ll=", "pt=", "whatshere%5Bpoint%5D=", "whatshere[point]="] {
            if let found = pair(after: marker, in: link) {
                let position = yandex ? (found.1, found.0) : found
                if let link = checked(position.0, position.1, name) {
                    return link
                }
            }
        }

        if let found = pair(after: "@", in: link), let link = checked(found.0, found.1, name) {
            return link
        }

        // The last resort, and the one `geo:` links rely on: a query that turns
        // out to be a position rather than a search term.
        for marker in ["q=", "query=", "daddr=", "destination=", "sll=", "center="] {
            if let found = pair(after: marker, in: link), let link = checked(found.0, found.1, name) {
                return link
            }
        }

        // geo:41.0082,28.9784 — but geo:0,0?q=... is the common form and its
        // zeroes mean nothing, which the check above has already thrown out.
        if lower.hasPrefix("geo:"), let found = pair(in: link.dropFirst(4)) {
            return checked(found.0, found.1, name)
        }

        return nil
    }

    /// Follows a shortened link and reads whatever it expands to.
    ///
    /// The expansion is read off the URL the server redirects to rather than
    /// out of the page, so nothing here parses HTML and no key is needed. A
    /// HEAD would be tidier, but these hosts answer it inconsistently.
    public static func resolve(_ text: String, using session: URLSession = .shared) async throws -> MapLink? {
        if let direct = parse(text) {
            return direct
        }

        guard let link = firstLink(in: text), let url = URL(string: link) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        // Asking as a browser, because these hosts answer a bare client with a
        // consent page that redirects nowhere useful.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (_, response) = try await session.data(for: request)
        guard let final = response.url?.absoluteString else { return nil }

        return parse(final)
    }

    // MARK: - Picking the link out

    /// The first thing in `text` that looks like a link.
    ///
    /// Shared text is rarely just a URL: it usually arrives with the name of
    /// the place on a line above it, or a sentence around it.
    static func firstLink(in text: String) -> String? {
        let schemes = ["http://", "https://", "geo:", "comgooglemaps://", "yandexmaps://", "maps://"]

        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let lower = token.lowercased()
            if schemes.contains(where: { lower.hasPrefix($0) }) {
                return String(token)
            }
        }
        return nil
    }

    /// The name a link gives the place, if it gives one.
    private static func placeName(in link: String) -> String? {
        // Google puts it in the path: /maps/place/Bostanci+Sahili/@...
        if let range = link.range(of: "/place/") {
            let rest = link[range.upperBound...]
            let name = rest.prefix { $0 != "/" && $0 != "?" }
            if let decoded = decode(String(name)), !decoded.isEmpty {
                return decoded
            }
        }

        // Apple and geo links put it in a query, sometimes in brackets after
        // the coordinates: geo:0,0?q=41.0,28.9(Bostanci)
        if let range = link.range(of: "("), let close = link.range(of: ")", range: range.upperBound..<link.endIndex) {
            let name = String(link[range.upperBound..<close.lowerBound])
            if let decoded = decode(name), !decoded.isEmpty {
                return decoded
            }
        }

        for marker in ["&q=", "?q=", "&name=", "?name=", "&text=", "?text="] {
            guard let range = link.range(of: marker) else { continue }
            let value = link[range.upperBound...].prefix { $0 != "&" }
            // A query that is really a position is not a name.
            if pair(in: value) != nil {
                continue
            }
            if let decoded = decode(String(value)), !decoded.isEmpty {
                return decoded
            }
        }

        return nil
    }

    private static func decode(_ text: String) -> String? {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reading numbers

    /// A position is only a position if it could be somewhere.
    ///
    /// Null Island is thrown out along with everything out of range: several of
    /// these links carry a literal `0,0` as a placeholder, and taking it at
    /// face value would route a rider into the Atlantic.
    private static func checked(_ latitude: Double, _ longitude: Double, _ name: String?) -> MapLink? {
        guard latitude >= -90, latitude <= 90, longitude >= -180, longitude <= 180 else { return nil }
        guard abs(latitude) > 1e-8 || abs(longitude) > 1e-8 else { return nil }
        return MapLink(coordinate: coordinate(latitude, longitude), name: name)
    }

    private static func coordinate(_ latitude: Double, _ longitude: Double) -> Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func number(after marker: String, in text: String) -> Double? {
        guard let range = text.range(of: marker) else { return nil }
        return scan(text[range.upperBound...])?.value
    }

    private static func pair(after marker: String, in text: String) -> (Double, Double)? {
        guard let range = text.range(of: marker) else { return nil }
        return pair(in: text[range.upperBound...])
    }

    /// Two numbers with a comma between them, at the very start of `text`.
    private static func pair(in text: Substring) -> (Double, Double)? {
        let trimmed = text.drop { $0 == " " }
        guard let first = scan(trimmed) else { return nil }

        // The comma survives percent encoding about half the time, depending on
        // which app did the sharing and whether the link came through a
        // messaging app on the way.
        var rest = first.rest.drop { $0 == " " }
        if rest.first == "," {
            rest = rest.dropFirst()
        } else if rest.prefix(3).lowercased() == "%2c" {
            rest = rest.dropFirst(3)
        } else {
            return nil
        }

        guard let second = scan(rest.drop { $0 == " " }) else { return nil }
        return (first.value, second.value)
    }

    /// A decimal number at the start of `text`, and whatever follows it.
    private static func scan(_ text: Substring) -> (value: Double, rest: Substring)? {
        var end = text.startIndex
        var seenDigit = false
        var seenDot = false

        while end < text.endIndex {
            let character = text[end]
            if character.isNumber {
                seenDigit = true
            } else if character == "." && !seenDot && seenDigit {
                seenDot = true
            } else if (character == "-" || character == "+") && end == text.startIndex {
                // A sign, and only where a sign can be.
            } else {
                break
            }
            end = text.index(after: end)
        }

        guard seenDigit, let value = Double(text[text.startIndex..<end]) else { return nil }
        return (value, text[end...])
    }
}
