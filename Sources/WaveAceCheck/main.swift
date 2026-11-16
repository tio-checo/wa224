import Foundation
import ScopeCore

@main struct Check {
    static func main() async {
        do {
            if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--decode" {
                let wave = try Waveform.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])), channel: 1)
                print("Decoded \(wave.samples.count) samples, dt=\(wave.interval), t0=\(wave.start), min=\(wave.minimum), max=\(wave.maximum)")
                return
            }
            let host = CommandLine.arguments.dropFirst().first ?? "192.168.0.100"
            let arguments = CommandLine.arguments
            let stride: Int
            if let index = arguments.firstIndex(of: "--stride"), index + 1 < arguments.count,
               let parsed = Int(arguments[index + 1]), [1, 4, 10, 20].contains(parsed) { stride = parsed }
            else if arguments.contains("--stride") { throw ScopeError.message("Použij --stride 1, 4, 10 nebo 20.") }
            else { stride = 1 }
            let scope = ScopeClient()
            print("Identity:", try await scope.connect(host))
            let settings = try await scope.settings()
            print("Time/div:", settings.timePerDivision, "Trigger:", settings.triggerMode, settings.triggerSelection)
            for channel in settings.channels where channel.enabled {
                let started = Date()
                let wave = try await scope.waveform(channel.id, stride: stride)
                print("CH\(channel.id): \(wave.samples.count) samples, dt=\(wave.interval), min=\(wave.minimum), max=\(wave.maximum), transfer=\(Date().timeIntervalSince(started))s")
            }
            await scope.disconnect()
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
