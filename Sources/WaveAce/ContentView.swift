import AppKit
import ScopeCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: ScopeModel
    @State private var zoom = 1.0
    @State private var pan = 0.5
    @State private var cursors = false
    @State private var cursorA = 0.3
    @State private var cursorB = 0.7
    private let panel = Color.white.opacity(0.045)

    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 14) {
                    HStack {
                        Label("PRŮBĚHY", systemImage: "waveform.path").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !model.live || !model.connected { Label("Poslední záznam", systemImage: "pause.circle").foregroundStyle(.orange).font(.caption) }
                        Text(String(format: "%.1f sn./s", model.framesPerSecond)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        Button { model.live.toggle() } label: { Image(systemName: model.live ? "pause.fill" : "play.fill") }
                            .help("Pozastavit pouze přenos do Macu; měření přístroje pokračuje")
                        Button("CSV") { model.exportCSV() }.disabled(model.shownWaves.isEmpty)
                        Button("PNG") { exportPNG() }.disabled(model.shownWaves.isEmpty)
                    }
                    plot.frame(minHeight: 310)
                    HStack {
                        Toggle("Kurzory", isOn: $cursors).toggleStyle(.switch).controlSize(.small)
                        Spacer()
                        Text("Zoom").foregroundStyle(.secondary)
                        Picker("Zoom", selection: $zoom) {
                            Text("1×").tag(1.0); Text("2×").tag(2.0); Text("5×").tag(5.0); Text("10×").tag(10.0)
                        }.labelsHidden().frame(width: 90)
                        Slider(value: $pan, in: 0...1).frame(width: 140).disabled(zoom == 1)
                        Button("Celý záznam") { zoom = 1; pan = 0.5 }
                    }.font(.caption)
                    if cursors {
                        HStack {
                            Text("A").foregroundStyle(.orange); Slider(value: $cursorA, in: 0...1)
                            Text("B").foregroundStyle(.cyan); Slider(value: $cursorB, in: 0...1)
                            let delta = abs(cursorA - cursorB) * visibleRange.span
                            Text("Δt \(engineering(delta, unit: "s")) · 1/Δt \(delta > 0 ? engineering(1 / delta, unit: "Hz") : "—")")
                                .monospacedDigit().frame(minWidth: 235, alignment: .trailing)
                        }.font(.caption)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(1...4, id: \.self) { number in channelCard(number) }
                    }
                }
                .padding(16).background(panel, in: RoundedRectangle(cornerRadius: 16))
                ScrollView { controls }.frame(width: 235)
            }.padding(20)
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 10) {
                Circle().fill(model.connected ? Color.green : Color.gray).frame(width: 7, height: 7)
                Text(model.status).lineLimit(1)
                Spacer()
                if let date = model.lastFrame {
                    Text("Přenos \(date.formatted(date: .omitted, time: .standard))").monospacedDigit()
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Color(red: 0.035, green: 0.05, blue: 0.07))
        .alert("Spojení s osciloskopem", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Zavřít", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 30)).foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text("WaveAce").font(.title2.weight(.semibold))
                Text(model.identity).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            TextField("IPv4 adresa", text: $model.host).textFieldStyle(.roundedBorder).frame(width: 155)
                .disabled(model.connected || model.connecting).onSubmit { model.connect() }
            if model.connecting { ProgressView().controlSize(.small) }
            Button(model.connected || model.connecting ? "Odpojit" : "Připojit") {
                if model.connected || model.connecting { model.disconnect() } else { model.connect() }
            }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
        }
    }
    private var visibleRange: (start: Double, span: Double) {
        let waves = model.shownWaves
        let first = waves.map(\.start).min() ?? -0.00006
        let last = waves.map(\.end).max() ?? 0.00006
        let full = max(last - first, 1e-12), span = full / zoom
        return (first + (full - span) * pan, span)
    }
    private var plot: some View {
        WavePlot(waves: model.shownWaves, channels: model.settings?.channels ?? [],
                 start: visibleRange.start, span: visibleRange.span,
                 cursors: cursors, cursorA: cursorA, cursorB: cursorB)
            .overlay {
                if model.shownWaves.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path").font(.system(size: 40)).foregroundStyle(.mint.opacity(0.6))
                        Text(model.connected ? "Zapni kanál a přenos průběhů" : "Připraveno k měření").font(.title3)
                        Text(model.connected ? "Ovládání kanálů najdeš pod grafem." : "Připoj WaveAce 224 přes Ethernet.").foregroundStyle(.secondary)
                    }.padding(25).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
    }
    private func channelCard(_ number: Int) -> some View {
        let settings = model.settings?.channels.first { $0.id == number }
        let wave = model.waves[number]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CH\(number)").font(.headline).foregroundStyle(channelColor(number))
                Spacer()
                Button { if model.hidden.contains(number) { model.hidden.remove(number) } else { model.hidden.insert(number) } } label: {
                    Image(systemName: model.hidden.contains(number) ? "eye.slash" : "eye")
                }.buttonStyle(.plain).help("Zobrazit / skrýt v aplikaci")
            }
            Toggle("Vstup", isOn: Binding(get: { settings?.enabled ?? false }, set: { model.command("C\(number):TRA \($0 ? "ON" : "OFF")") }))
                .toggleStyle(.switch).controlSize(.mini).disabled(!model.connected || model.operating)
            Text(settings.map { engineering($0.voltsPerDivision, unit: "V/div") } ?? "—").font(.system(.body, design: .monospaced))
            HStack {
                Button("−") { stepVolts(number, direction: -1) }
                Button("+") { stepVolts(number, direction: 1) }
                Spacer()
                Text(settings?.coupling ?? "—").font(.caption).foregroundStyle(.secondary)
            }.disabled(!model.connected || model.operating)
            Divider()
            metric("Vpp", wave.map { engineering($0.maximum - $0.minimum, unit: "V") } ?? "—")
            metric("RMS", wave.map { engineering($0.rms, unit: "V") } ?? "—")
            Text(wave.map { "\($0.samples.count) vzorků" } ?? "Bez průběhu").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity).background(channelColor(number).opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(channelColor(number).opacity(0.16)))
    }
    private func metric(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.caption)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AKVIZICE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.settings?.triggerMode ?? "—").font(.title2.monospaced()).foregroundStyle(model.settings?.triggerMode == "STOP" ? .orange : .mint)
            HStack {
                Button("Run") { model.command("TRMD AUTO") }.tint(.green)
                Button("Stop") { model.command("TRMD STOP") }.tint(.orange)
                Button("Single") { model.command("TRMD SINGLE") }
            }.disabled(!model.connected || model.operating)
            Divider()
            Text("ČASOVÁ ZÁKLADNA").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.settings.map { engineering($0.timePerDivision, unit: "s/div") } ?? "—").font(.title3.monospaced())
            HStack {
                Button("Rychleji") { stepTime(-1) }
                Button("Pomaleji") { stepTime(1) }
            }.disabled(!model.connected || model.operating)
            Text("Graf zobrazuje přenesený záznam. Jeho rozsah je uveden na časové ose.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("TRIGGER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let settings = model.settings {
                Picker("Zdroj", selection: Binding(get: { settings.triggerSource }, set: { number in
                    var tokens = settings.triggerSelection.split(separator: ",").map(String.init)
                    if let index = tokens.firstIndex(of: "SR"), index + 1 < tokens.count {
                        tokens[index + 1] = "C\(number)"; model.command("TRSE " + tokens.joined(separator: ","))
                    }
                })) {
                    if settings.triggerSource == 0 { Text("Externí / jiný").tag(0) }
                    ForEach(1...4, id: \.self) { Text("CH\($0)").tag($0) }
                }
                if settings.triggerSource > 0 {
                    Picker("Hrana", selection: Binding(get: { settings.triggerSlope }, set: { model.command("C\(settings.triggerSource):TRSL \($0)") })) {
                        Text("Vzestupná").tag("POS"); Text("Sestupná").tag("NEG")
                    }
                    NumericSetting(title: "Úroveň (V)", value: settings.triggerLevel) {
                        model.command("C\(settings.triggerSource):TRLV \($0)")
                    }
                }
            }
            Divider()
            Text("PŘENOS DO MACU").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Vzorky", selection: $model.transferStride) {
                Text("Plný záznam").tag(1)
                Text("Každý 4. vzorek").tag(4)
                Text("Každý 10. vzorek").tag(10)
                Text("Každý 20. vzorek").tag(20)
            }
            if model.transferStride > 1 {
                Text("Řidší náhled může vynechat krátké špičky. Vpp, RMS i CSV používají přenesené vzorky.").font(.caption).foregroundStyle(.orange)
            }
            Picker("Prodleva", selection: $model.refreshInterval) {
                Text("Nejrychlejší").tag(0.02)
                Text("0,2 s").tag(0.2)
                Text("0,5 s").tag(0.5)
                Text("1 s").tag(1.0)
            }
            Text("Vpp a RMS se počítají z celého přeneseného záznamu.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(panel, in: RoundedRectangle(cornerRadius: 16))
            .disabled(model.operating)
    }
    private func stepVolts(_ channel: Int, direction: Int) {
        guard let value = model.settings?.channels.first(where: { $0.id == channel })?.voltsPerDivision else { return }
        let values = (-3...2).flatMap { exponent in [1.0, 2, 5].map { $0 * pow(10, Double(exponent)) } }
        model.command("C\(channel):VDIV \(step(value, values: values, direction: direction))")
    }
    private func stepTime(_ direction: Int) {
        guard let value = model.settings?.timePerDivision else { return }
        let values = (-9...1).flatMap { exponent in [1.0, 2.5, 5].map { $0 * pow(10, Double(exponent)) } }.filter { $0 >= 2.5e-9 && $0 <= 50 }
        model.command("TDIV \(step(value, values: values, direction: direction))")
    }
    private func step(_ value: Double, values: [Double], direction: Int) -> Double {
        direction > 0 ? values.first(where: { $0 > value * 1.01 }) ?? value : values.last(where: { $0 < value * 0.99 }) ?? value
    }
    private func exportPNG() {
        let renderer = ImageRenderer(content: plot.frame(width: 1400, height: 700).padding(20).background(Color.black))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "WaveAce-\(ScopeModel.fileDate()).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url); model.status = "PNG uloženo: \(url.lastPathComponent)" }
        catch { model.error = error.localizedDescription }
    }
}

struct NumericSetting: View {
    let title: String
    let value: Double
    let submit: (Double) -> Void
    @State private var text = ""
    var body: some View {
        HStack {
            Text(title).font(.caption)
            TextField(title, text: $text).textFieldStyle(.roundedBorder).onSubmit(apply)
            Button { apply() } label: { Image(systemName: "checkmark") }
        }.onAppear { text = String(format: "%.6g", value) }
            .onChange(of: value) { _, number in text = String(format: "%.6g", number) }
    }
    private func apply() {
        if let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite { submit(number) }
    }
}
