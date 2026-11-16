import Foundation
import Darwin

/// All socket traffic is serialized on this actor, never on the UI thread.
public actor VICP {
    private var descriptor: Int32 = -1
    private var sequence: UInt8 = 0
    private let limit = 16 * 1024 * 1024
    public init() {}
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    public func close() { if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 } }

    public func connect(host: String, port: UInt16 = 1861) throws {
        close()
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw ScopeError.message("Zadej platnou IPv4 adresu osciloskopu.")
        }
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure("Nelze vytvořit spojení") }
        do {
            var yes: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
            var timeout = timeval(tv_sec: 4, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            let flags = fcntl(descriptor, F_GETFL)
            guard fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw failure("Nastavení spojení") }
            let addressLength = socklen_t(address.sin_len)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, addressLength) }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw failure("Připojení selhalo") }
                var item = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                guard poll(&item, 1, 4000) > 0 else { throw ScopeError.message("Osciloskop neodpovídá. Zkontroluj kabel, IP adresu a VPN.") }
                var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                    throw ScopeError.message("Připojení selhalo: \(String(cString: strerror(error)))")
                }
            }
            guard fcntl(descriptor, F_SETFL, flags) == 0 else { throw failure("Nastavení spojení") }
        } catch { close(); throw error }
    }

    private func failure(_ message: String) -> ScopeError {
        .message("\(message): \(String(cString: strerror(errno)))")
    }
    private func read(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count), done = 0
        while done < count {
            let amount = bytes.withUnsafeMutableBytes { buffer in
                recv(descriptor, buffer.baseAddress!.advanced(by: done), count - done, 0)
            }
            if amount < 0 && errno == EINTR { continue }
            guard amount > 0 else { throw failure("Přenos přerušen nebo vypršel časový limit") }
            done += amount
        }
        return bytes
    }
    private func write(_ bytes: [UInt8]) throws {
        guard descriptor >= 0 else { throw ScopeError.message("Osciloskop není připojen.") }
        var done = 0
        while done < bytes.count {
            let amount = bytes.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress!.advanced(by: done), bytes.count - done, 0) }
            if amount < 0 && errno == EINTR { continue }
            guard amount > 0 else { throw failure("Odesílání selhalo") }
            done += amount
        }
    }
    public func send(_ command: String) throws {
        guard !command.contains("\n"), !command.contains("\r"), command.utf8.count < 4096 else {
            throw ScopeError.message("Neplatný příkaz.")
        }
        sequence = sequence == 255 ? 1 : sequence + 1
        let payload = Array((command + "\n").utf8)
        let length = UInt32(payload.count)
        let header: [UInt8] = [0x81, 1, sequence, 0, UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)]
        do { try write(header + payload) } catch { close(); throw error }
    }
    public func query(_ command: String) throws -> Data {
        do {
            try send(command)
            var result = Data()
            for _ in 0..<1024 {
                let header = try read(8)
                let length = header[4..<8].reduce(0) { ($0 << 8) | Int($1) }
                guard header[1] == 1, length <= limit, result.count + length <= limit else {
                    throw ScopeError.message("Neplatná hlavička VICP.")
                }
                if length > 0 { result.append(contentsOf: try read(length)) }
                if header[0] & 1 != 0 { return result }
            }
            throw ScopeError.message("Příliš mnoho bloků odpovědi.")
        } catch { close(); throw error }
    }
    public func text(_ command: String) throws -> String {
        let result = try query(command)
        guard let text = String(data: result, encoding: .ascii) else { throw ScopeError.message("Neplatná textová odpověď.") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
