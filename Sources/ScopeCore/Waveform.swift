import Foundation

public enum ScopeError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

public struct Waveform: Sendable {
    public let channel: Int
    public let samples: [Double]
    public let interval: Double
    public let start: Double
    public let capturedAt: Date
    public var end: Double { start + Double(max(0, samples.count - 1)) * interval }
    public var minimum: Double { samples.min() ?? 0 }
    public var maximum: Double { samples.max() ?? 0 }
    public var rms: Double { sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(max(1, samples.count))) }

    public static func decode(_ response: Data, channel: Int) throws -> Waveform {
        func fail(_ text: String) -> ScopeError { .message("CH\(channel): \(text)") }
        let bytes = [UInt8](response)
        // A definite-length IEEE 488.2 block can have a textual command header.
        guard let hash = bytes.prefix(256).firstIndex(of: 35), hash + 2 <= bytes.count,
              bytes[hash + 1] >= 49, bytes[hash + 1] <= 57 else {
            throw fail("Chybí binární blok průběhu.")
        }
        let digits = Int(bytes[hash + 1] - 48)
        let beginning = hash + 2 + digits
        guard beginning <= bytes.count,
              bytes[(hash + 2)..<beginning].allSatisfy({ (48...57).contains($0) }),
              let size = Int(String(decoding: bytes[(hash + 2)..<beginning], as: UTF8.self)),
              size >= 346, size <= bytes.count - beginning else {
            throw fail("Neúplný binární blok.")
        }
        let b = Array(bytes[beginning..<(beginning + size)])
        guard String(decoding: b.prefix(8), as: UTF8.self) == "WAVEDESC" else {
            throw fail("Neznámý formát deskriptoru.")
        }
        let little: Bool
        switch (b[34], b[35]) {
        case (1, 0): little = true
        case (0, 0): little = false
        default: throw fail("Neplatné pořadí bajtů.")
        }
        func u(_ offset: Int, _ count: Int) -> UInt64 {
            let range = Array(b[offset..<(offset + count)])
            let ordered = little ? Array(range.reversed()) : range
            return ordered.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        func i(_ offset: Int) -> Int { Int(Int32(bitPattern: UInt32(u(offset, 4)))) }
        func f(_ offset: Int) -> Double { Double(Float(bitPattern: UInt32(u(offset, 4)))) }
        let type = u(32, 2)
        guard type <= 1 else { throw fail("Nepodporované rozlišení vzorků.") }
        let width = type == 0 ? 1 : 2
        let descriptor = i(36)
        let lengths = [i(40), i(44), i(48), i(52), i(56)]
        let dataBytes = i(60), count = i(116), first = i(124), last = i(128)
        guard descriptor >= 346, lengths.allSatisfy({ $0 >= 0 && $0 <= size }),
              descriptor <= size, dataBytes > 0,
              count > 0, count <= dataBytes / width,
              first >= 0, last >= first, last < count else {
            throw fail("Neplatné délky nebo rozsah vzorků.")
        }
        guard i(144) <= 1, i(52) == 0, i(64) == 0 else {
            throw fail("Sekvenční, RIS a dvojité datové průběhy zatím nejsou podporovány.")
        }
        let dataStart = descriptor + lengths.reduce(0, +)
        let stride = max(1, i(136))
        var effectiveCount = count, effectiveFirst = first, effectiveLast = last
        if stride > 1 {
            // WA224 firmware 5.05.02.14 describes the original record even
            // though it sends floor(count / stride) samples. Its dt is also
            // the original interval. Do not apply this quirk to other formats.
            let template = String(decoding: b[16..<32].prefix(while: { $0 != 0 }), as: UTF8.self)
            let instrument = String(decoding: b[76..<92].prefix(while: { $0 != 0 }), as: UTF8.self)
            guard template == "WAVEACE", instrument == "WA224", i(132) == 0,
                  first == 0, last == count - 1, dataBytes == count * width else {
                throw fail("Nepodporovaný formát zředěného záznamu.")
            }
            effectiveCount = count / stride
            effectiveFirst = 0; effectiveLast = effectiveCount - 1
        }
        let transmittedBytes = stride > 1 ? effectiveCount * width : dataBytes
        guard effectiveCount > 0, dataStart <= size, transmittedBytes <= size - dataStart,
              stride == 1 || transmittedBytes == size - dataStart else { throw fail("Chybí vzorky průběhu.") }
        let gain = f(156), offset = f(160), interval = f(176) * Double(stride)
        let start = Double(bitPattern: u(180, 8))
        guard gain.isFinite, gain > 0, offset.isFinite, interval.isFinite, interval > 0, start.isFinite else {
            throw fail("Neplatná kalibrace průběhu.")
        }
        var samples = [Double]()
        samples.reserveCapacity(effectiveLast - effectiveFirst + 1)
        for index in effectiveFirst...effectiveLast {
            let p = dataStart + index * width
            let raw = width == 1 ? Int(Int8(bitPattern: b[p])) : Int(Int16(bitPattern: UInt16(u(p, 2))))
            samples.append(Double(raw) * gain - offset)
        }
        guard samples.allSatisfy(\.isFinite) else { throw fail("Neplatné hodnoty napětí.") }
        return Waveform(channel: channel, samples: samples, interval: interval,
                        start: start + Double(effectiveFirst) * interval, capturedAt: Date())
    }

    public func csv() -> String {
        var result = "time_s,CH\(channel)_V\n"
        for (i, voltage) in samples.enumerated() { result += "\(start + Double(i) * interval),\(voltage)\n" }
        return result
    }
}

public func engineering(_ value: Double, unit: String = "") -> String {
    guard value.isFinite else { return "—" }
    if value == 0 { return "0 \(unit)" }
    let prefixes: [(Double, String)] = [(1e9,"G"),(1e6,"M"),(1e3,"k"),(1,""),(1e-3,"m"),(1e-6,"µ"),(1e-9,"n"),(1e-12,"p")]
    let scale = prefixes.first { abs(value) >= $0.0 } ?? (1e-12,"p")
    return String(format: "%.4g %@%@", locale: Locale(identifier: "en_US_POSIX"), value / scale.0, scale.1, unit)
}
