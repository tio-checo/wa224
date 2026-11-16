import ScopeCore
import SwiftUI

struct WavePlot: View {
    let waves: [Waveform]
    let channels: [ChannelSettings]
    let start: Double
    let span: Double
    let cursors: Bool
    let cursorA: Double
    let cursorB: Double

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 12, y: 25, width: max(1, size.width - 24), height: max(1, size.height - 62))
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10), with: .color(Color(red: 0.025, green: 0.035, blue: 0.045)))
            var grid = Path()
            for column in 0...12 {
                let x = rect.minX + rect.width * Double(column) / 12
                grid.move(to: CGPoint(x: x, y: rect.minY)); grid.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for row in 0...8 {
                let y = rect.minY + rect.height * Double(row) / 8
                grid.move(to: CGPoint(x: rect.minX, y: y)); grid.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
            var center = Path()
            center.move(to: CGPoint(x: rect.minX, y: rect.midY)); center.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            let zeroX = rect.minX - start / span * rect.width
            if rect.contains(CGPoint(x: zeroX, y: rect.midY)) {
                center.move(to: CGPoint(x: zeroX, y: rect.minY)); center.addLine(to: CGPoint(x: zeroX, y: rect.maxY))
            }
            context.stroke(center, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            var clipped = context
            clipped.clip(to: Path(rect))
            for wave in waves {
                guard let setting = channels.first(where: { $0.id == wave.channel }), wave.samples.count > 1 else { continue }
                let first = max(0, min(wave.samples.count - 1, Int(floor((start - wave.start) / wave.interval))))
                let last = max(0, min(wave.samples.count - 1, Int(ceil((start + span - wave.start) / wave.interval))))
                guard first < last else { continue }
                func point(_ index: Int) -> CGPoint {
                    CGPoint(x: rect.minX + (wave.start + Double(index) * wave.interval - start) / span * rect.width,
                            y: rect.midY - (wave.samples[index] + setting.offset) / (setting.voltsPerDivision * 8) * rect.height)
                }
                // Min/max buckets retain narrow spikes even for long records.
                let stride = max(1, (last - first) / max(1, Int(rect.width * 2)))
                var path = Path(); path.move(to: point(first))
                var index = first
                while index <= last {
                    let end = min(last + 1, index + stride)
                    var low = index, high = index
                    for sample in index..<end {
                        if wave.samples[sample] < wave.samples[low] { low = sample }
                        if wave.samples[sample] > wave.samples[high] { high = sample }
                    }
                    if low < high { path.addLine(to: point(low)); path.addLine(to: point(high)) }
                    else { path.addLine(to: point(high)); path.addLine(to: point(low)) }
                    index = end
                }
                clipped.stroke(path, with: .color(channelColor(wave.channel)), lineWidth: 1.25)
            }
            if cursors {
                for (fraction, color, label) in [(cursorA, Color.orange, "A"), (cursorB, Color.cyan, "B")] {
                    let x = rect.minX + fraction * rect.width
                    var line = Path(); line.move(to: CGPoint(x: x, y: rect.minY)); line.addLine(to: CGPoint(x: x, y: rect.maxY))
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    context.draw(Text(label).font(.caption.bold()).foregroundColor(color), at: CGPoint(x: x, y: 12))
                }
            }
            for column in [0, 3, 6, 9, 12] {
                let text = engineering(start + Double(column) / 12 * span, unit: "s")
                context.draw(Text(text).font(.system(size: 10, design: .monospaced)).foregroundColor(.gray),
                             at: CGPoint(x: rect.minX + rect.width * Double(column) / 12, y: rect.maxY + 18),
                             anchor: column == 0 ? .leading : column == 12 ? .trailing : .center)
            }
        }
        .accessibilityLabel("Naměřené průběhy. Časový rozsah \(engineering(span, unit: "s")).")
    }
}
