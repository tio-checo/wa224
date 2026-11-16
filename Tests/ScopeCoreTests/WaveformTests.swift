import Foundation
import XCTest
@testable import ScopeCore

final class WaveformTests: XCTestCase {
    func fixture(little: Bool = true, word: Bool = false, first: Int = 0, last: Int = 2) -> Data {
        var b = [UInt8](repeating: 0, count: 346)
        b.replaceSubrange(0..<8, with: Array("WAVEDESC".utf8))
        func put(_ offset: Int, _ number: UInt64, _ count: Int = 4) {
            let bytes = (0..<count).map { UInt8((number >> ($0 * 8)) & 255) }
            b.replaceSubrange(offset..<(offset + count), with: little ? bytes : Array(bytes.reversed()))
        }
        put(32, word ? 1 : 0, 2); put(34, little ? 1 : 0, 2)
        put(36, 346); put(60, word ? 6 : 3); put(116, 3)
        put(124, UInt64(first)); put(128, UInt64(last)); put(136, 1); put(144, 1)
        put(156, UInt64(Float(0.5).bitPattern)); put(160, UInt64(Float(1).bitPattern))
        put(176, UInt64(Float(0.25).bitPattern)); put(180, Double(-2).bitPattern, 8)
        if word {
            for raw: Int16 in [-300, 0, 300] {
                let v = UInt16(bitPattern: raw), bytes = [UInt8(v & 255), UInt8(v >> 8)]
                b += little ? bytes : Array(bytes.reversed())
            }
        } else { b += [UInt8(bitPattern: -2), 0, 2] }
        return Data(Array("C1:WF ALL,#9\(String(format: "%09d", b.count))".utf8) + b + [10])
    }

    func sparseFixture() -> Data {
        var data = fixture()
        let block = data.range(of: Data("WAVEDESC".utf8))!.lowerBound
        func put(_ offset: Int, _ number: UInt32) {
            data.replaceSubrange((block + offset)..<(block + offset + 4),
                                 with: (0..<4).map { UInt8((number >> ($0 * 8)) & 255) })
        }
        data.replaceSubrange((block + 16)..<(block + 23), with: "WAVEACE".utf8)
        data.replaceSubrange((block + 76)..<(block + 81), with: "WA224".utf8)
        // Thirteen original samples, three transferred samples (indices 0,4,8).
        put(60, 13); put(116, 13); put(128, 12); put(136, 4)
        return data
    }
    func testWA224SparseTimingAndCSV() throws {
        let wave = try Waveform.decode(sparseFixture(), channel: 1)
        XCTAssertEqual(wave.samples, [-2, -1, 0])
        XCTAssertEqual(wave.interval, 1)
        XCTAssertEqual(wave.start, -2); XCTAssertEqual(wave.end, 0)
        XCTAssertTrue(wave.csv().contains("-1.0,-1.0"))
    }
    func testRejectsSparseTruncationAndUnknownDescriptor() {
        var data = sparseFixture()
        let block = data.range(of: Data("WAVEDESC".utf8))!.lowerBound
        data[block + 136] = 3 // Would require four samples rather than three.
        XCTAssertThrowsError(try Waveform.decode(data, channel: 1))
        data = sparseFixture()
        data[block + 76] = 88
        XCTAssertThrowsError(try Waveform.decode(data, channel: 1))
    }

    func testByteCalibrationAndSignedValues() throws {
        let wave = try Waveform.decode(fixture(), channel: 1)
        XCTAssertEqual(wave.samples, [-2, -1, 0])
        XCTAssertEqual(wave.start, -2); XCTAssertEqual(wave.end, -1.5)
        XCTAssertTrue(wave.csv().contains("-1.75,-1.0"))
    }
    func testBigEndianWordsAndValidRange() throws {
        let wave = try Waveform.decode(fixture(little: false, word: true, first: 1), channel: 2)
        XCTAssertEqual(wave.samples, [-1, 149])
        XCTAssertEqual(wave.start, -1.75)
    }
    func testLittleEndianWords() throws {
        XCTAssertEqual(try Waveform.decode(fixture(word: true), channel: 1).samples, [-151, -1, 149])
    }
    func testRejectsTruncatedAndInvalidRecords() {
        let data = fixture()
        for length in [0, 1, 21, 100, data.count - 2] {
            XCTAssertThrowsError(try Waveform.decode(data.prefix(length), channel: 1))
        }
        XCTAssertThrowsError(try Waveform.decode(fixture(first: 2, last: 1), channel: 1))
        XCTAssertThrowsError(try Waveform.decode(fixture(last: 3), channel: 1))
    }
    func testRejectsNonfiniteCalibration() {
        var data = fixture()
        let block = data.range(of: Data("WAVEDESC".utf8))!.lowerBound
        data.replaceSubrange((block + 176)..<(block + 180), with: [0, 0, 128, 127])
        XCTAssertThrowsError(try Waveform.decode(data, channel: 1))
    }
}
