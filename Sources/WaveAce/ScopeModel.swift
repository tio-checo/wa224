import AppKit
import Combine
import Foundation
import ScopeCore
import SwiftUI

@MainActor final class ScopeModel: ObservableObject {
    @Published var host = "192.168.0.100"
    @Published var connected = false
    @Published var connecting = false
    @Published var operating = false
    @Published var live = true
    @Published var identity = "LeCroy WaveAce 224"
    @Published var status = "Připoj osciloskop v místní síti."
    @Published var error: String?
    @Published var settings: ScopeSettings?
    @Published var waves: [Int: Waveform] = [:]
    @Published var hidden: Set<Int> = []
    @Published var framesPerSecond = 0.0
    @Published var lastFrame: Date?
    @Published var refreshInterval = 0.2
    @Published var transferStride = 1
    private var client = ScopeClient()
    private var loop: Task<Void, Never>?
    private var generation = UUID()
    var shownWaves: [Waveform] { waves.values.filter { !hidden.contains($0.channel) }.sorted { $0.channel < $1.channel } }

    func connect() {
        guard !connected, !connecting else { return }
        let token = UUID()
        generation = token
        connecting = true; error = nil; status = "Připojuji…"
        let scope = ScopeClient()
        client = scope
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        loop = Task {
            do {
                let name = try await scope.connect(address)
                let initial = try await scope.settings()
                guard generation == token, !Task.isCancelled else { await scope.disconnect(); return }
                identity = name; settings = initial; waves = [:]; lastFrame = nil
                connected = true; connecting = false; status = "Připojeno · Ethernet / VICP"
                var lastSettings = Date()
                while !Task.isCancelled, generation == token {
                    if !operating, live {
                        let started = Date()
                        if Date().timeIntervalSince(lastSettings) > 3 {
                            let updated = try await scope.settings()
                            guard generation == token, !Task.isCancelled else { break }
                            settings = updated; lastSettings = Date()
                        }
                        let stride = transferStride
                        var next: [Int: Waveform] = [:]
                        for channel in settings?.channels ?? [] where channel.enabled && !hidden.contains(channel.id) {
                            try Task.checkCancellation()
                            next[channel.id] = try await scope.waveform(channel.id, stride: stride)
                        }
                        guard generation == token, !Task.isCancelled else { break }
                        waves = next
                        framesPerSecond = next.isEmpty ? 0 : 1 / max(0.001, Date().timeIntervalSince(started) + refreshInterval)
                        lastFrame = next.isEmpty ? nil : Date()
                    }
                    try await Task.sleep(for: .seconds(refreshInterval))
                }
            } catch {
                if generation == token, !Task.isCancelled {
                    self.error = error.localizedDescription
                    connected = false; connecting = false; status = "Spojení přerušeno · zobrazen poslední záznam"
                }
            }
            await scope.disconnect()
        }
    }
    func disconnect() {
        generation = UUID(); loop?.cancel(); loop = nil
        connected = false; connecting = false; operating = false; framesPerSecond = 0
        status = "Odpojeno · zobrazen poslední záznam"
        let previous = client
        Task { await previous.disconnect() }
    }
    func command(_ command: String) {
        guard connected, !operating else { return }
        operating = true; error = nil
        let token = generation, scope = client
        Task {
            do {
                try await scope.command(command)
                let updated = try await scope.settings()
                guard generation == token else { return }
                settings = updated; operating = false
                status = "Připojeno · nastavení načteno z přístroje"
            } catch {
                guard generation == token else { return }
                self.error = error.localizedDescription
                operating = false; disconnect()
            }
        }
    }
    func exportCSV() {
        let records = shownWaves
        guard !records.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "WaveAce-\(Self.fileDate()).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var text = records.flatMap { ["time_CH\($0.channel)_s", "CH\($0.channel)_V"] }.joined(separator: ",") + "\n"
        for index in 0..<(records.map { $0.samples.count }.max() ?? 0) {
            text += records.flatMap { wave -> [String] in
                guard index < wave.samples.count else { return ["", ""] }
                return [String(wave.start + Double(index) * wave.interval), String(wave.samples[index])]
            }.joined(separator: ",") + "\n"
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8); status = "CSV uloženo: \(url.lastPathComponent)" }
        catch { self.error = error.localizedDescription }
    }
    static func fileDate() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

let channelColors: [Color] = [.yellow, .cyan, .green, .red]
func channelColor(_ number: Int) -> Color { channelColors[max(0, min(3, number - 1))] }
