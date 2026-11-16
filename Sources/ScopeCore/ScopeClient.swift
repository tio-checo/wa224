import Foundation

public struct ChannelSettings: Sendable, Identifiable {
    public let id: Int
    public var enabled: Bool
    public var voltsPerDivision: Double
    public var offset: Double
    public var coupling: String
}
public struct ScopeSettings: Sendable {
    public var channels: [ChannelSettings]
    public var timePerDivision: Double
    public var triggerMode: String
    public var triggerSource: Int
    public var triggerLevel: Double
    public var triggerSlope: String
    public var triggerSelection: String
}

public actor ScopeClient {
    private let wire = VICP()
    private var originalTransfer: String?
    private var configuredStride: Int?
    public init() {}
    public func disconnect() async {
        if let original = originalTransfer { try? await wire.send(original) }
        originalTransfer = nil; configuredStride = nil
        await wire.close()
    }
    public func connect(_ host: String) async throws -> String {
        try await wire.connect(host: host)
        let identity = try await wire.text("*IDN?")
        guard identity.uppercased().contains("WA224") else {
            await wire.close()
            throw ScopeError.message("Neočekávaný přístroj: \(identity). Tato verze je určena pro WA224.")
        }
        let transfer = try await value("WFSU?")
        guard transfer.hasPrefix("SP,"), !transfer.contains(";"), !transfer.contains("\n") else {
            await wire.close()
            throw ScopeError.message("Neplatné nastavení přenosu WFSU.")
        }
        originalTransfer = "WFSU " + transfer
        configuredStride = nil
        return identity.replacingOccurrences(of: "*IDN ", with: "")
    }
    private func value(_ command: String) async throws -> String {
        let text = try await wire.text(command)
        guard let space = text.firstIndex(of: " ") else { return text }
        return String(text[text.index(after: space)...])
    }
    private func number(_ command: String) async throws -> Double {
        let text = try await value(command)
        let expression = try NSRegularExpression(pattern: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[Ee][+-]?[0-9]+)?")
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text), let result = Double(text[range]), result.isFinite else {
            throw ScopeError.message("Neplatná odpověď na \(command): \(text)")
        }
        return result
    }
    public func settings() async throws -> ScopeSettings {
        var channels = [ChannelSettings]()
        for channel in 1...4 {
            let prefix = "C\(channel):"
            let enabled = try await value(prefix + "TRA?") == "ON"
            let volts = try await number(prefix + "VDIV?")
            let offset = try await number(prefix + "OFST?")
            let coupling = try await value(prefix + "CPL?")
            guard volts > 0 else { throw ScopeError.message("Neplatná citlivost kanálu.") }
            channels.append(ChannelSettings(id: channel, enabled: enabled, voltsPerDivision: volts, offset: offset, coupling: coupling))
        }
        let time = try await number("TDIV?")
        let mode = try await value("TRMD?")
        let selection = try await value("TRSE?")
        let tokens = selection.split(separator: ",").map(String.init)
        let source = tokens.firstIndex(of: "SR").flatMap { $0 + 1 < tokens.count ? Int(tokens[$0 + 1].dropFirst()) : nil } ?? 0
        // External triggers are displayed but not silently replaced by channel 1.
        let level = source > 0 ? try await number("C\(source):TRLV?") : 0
        let slope = source > 0 ? try await value("C\(source):TRSL?") : "POS"
        guard time > 0 else { throw ScopeError.message("Neplatná časová základna.") }
        return ScopeSettings(channels: channels, timePerDivision: time, triggerMode: mode, triggerSource: source,
                             triggerLevel: level, triggerSlope: slope, triggerSelection: selection)
    }
    public func waveform(_ channel: Int, stride: Int = 1) async throws -> Waveform {
        guard (1...4).contains(channel) else { throw ScopeError.message("Neplatný kanál.") }
        guard [1, 4, 10, 20].contains(stride) else { throw ScopeError.message("Neplatné rozlišení přenosu.") }
        if configuredStride != stride {
            try await wire.send("WFSU SP,\(stride),NP,0,FP,0,SN,0")
            let actual = try await value("WFSU?")
            guard actual == "SP,\(stride),NP,0,FP,0,SN,0" else {
                throw ScopeError.message("Osciloskop nepotvrdil zvolené rozlišení přenosu: \(actual)")
            }
            configuredStride = stride
        }
        let response = try await wire.query("C\(channel):WF? ALL")
        return try Waveform.decode(response, channel: channel)
    }
    public func command(_ command: String) async throws { try await wire.send(command) }
}
