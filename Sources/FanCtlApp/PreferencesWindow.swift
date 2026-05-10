import SwiftUI
import Charts
import FanCtlProtocol

/// Preferences view: drag points on the curve, pick the driving sensor.
/// Opens as a free-floating window separate from the menu-bar popover.
struct PreferencesView: View {
    @EnvironmentObject var client: HelperClient
    @State private var draftPoints: [FanCurve.Point] = []
    @State private var selectedSensor: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom curve")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Drag a point to reshape the curve. Each point maps a temperature to a fan target as a fraction of the fan's range.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CurveEditor(points: $draftPoints)
                .frame(height: 220)
                .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                Button("Reset to default") {
                    draftPoints = FanCurve.defaultCustom.points
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    client.setCustomCurve(FanCurve(points: draftPoints))
                    client.setMode(.custom)
                } label: {
                    Label("Save & activate", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftPoints.count < 2)
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Driving sensor")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Pick which temperature drives the curve. \"Hottest\" tracks whichever sensor is currently the highest — usually the safe default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("", selection: $selectedSensor) {
                    Text("Hottest (auto)").tag("")
                    ForEach(client.snapshot?.temps ?? [], id: \.key) { t in
                        Text("\(t.key)  ·  \(String(format: "%.1f °C", t.celsius))")
                            .tag(t.key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: selectedSensor) { _, new in
                    client.setSensorKey(new.isEmpty ? nil : new)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { syncFromSnapshot() }
        .onChange(of: client.snapshot?.timestamp) { _, _ in syncFromSnapshot() }
    }

    /// Pull the current curve + sensor out of the live snapshot the first
    /// time the window opens and on reconnects, so what the user sees
    /// matches what the helper is actually running.
    private func syncFromSnapshot() {
        guard draftPoints.isEmpty else { return }   // don't clobber edits
        if let curve = client.snapshot?.customCurve, !curve.points.isEmpty {
            draftPoints = curve.points
        } else {
            draftPoints = FanCurve.defaultCustom.points
        }
        selectedSensor = client.snapshot?.sensorKey ?? ""
    }
}

// MARK: - Curve editor chart

/// A draggable line chart bound to an array of `FanCurve.Point`. The
/// outermost x-points stay fixed in temperature; intermediate points can
/// move along both axes within a clamped range. Ordering is enforced.
private struct CurveEditor: View {
    @Binding var points: [FanCurve.Point]
    @State private var draggingIndex: Int?

    private let tempRange: ClosedRange<Double> = 20...100
    private let rpmRange:  ClosedRange<Double> = 0...1

    var body: some View {
        GeometryReader { geo in
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    LineMark(
                        x: .value("°C", p.tempC),
                        y: .value("RPM %", p.rpmFraction * 100)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(.cyan)
                    .lineStyle(.init(lineWidth: 2, lineCap: .round))

                    PointMark(
                        x: .value("°C", p.tempC),
                        y: .value("RPM %", p.rpmFraction * 100)
                    )
                    .foregroundStyle(.cyan)
                    .symbolSize(draggingIndex == i ? 250 : 110)
                }
                AreaMark(
                    x: .value("°C", points.first?.tempC ?? 0),
                    yStart: .value("min", 0),
                    yEnd:   .value("max", 0)
                )
                .opacity(0)  // forces the axes to start at 0
            }
            .chartXScale(domain: tempRange)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(position: .bottom, values: stride(from: 30.0, through: 100.0, by: 10.0).map { $0 }) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))°") } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))%") } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { plotGeo in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in handleDrag(at: v.location, proxy: proxy, geo: plotGeo) }
                                .onEnded   { _ in draggingIndex = nil }
                        )
                }
            }
        }
    }

    private func handleDrag(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geo[plotFrame]
        let local = CGPoint(x: location.x - plotRect.minX, y: location.y - plotRect.minY)
        guard plotRect.contains(location),
              let temp: Double = proxy.value(atX: local.x),
              let rpmPct: Double = proxy.value(atY: local.y) else { return }

        // Pick the closest point on first contact, then keep updating it.
        if draggingIndex == nil {
            var best: (Int, Double) = (0, .infinity)
            for (i, p) in points.enumerated() {
                let dx = p.tempC - temp
                let dy = (p.rpmFraction * 100) - rpmPct
                let d = dx * dx + dy * dy
                if d < best.1 { best = (i, d) }
            }
            draggingIndex = best.0
        }
        guard let i = draggingIndex else { return }

        // Clamp to neighbours so the points stay sorted by temperature.
        let lo = i == 0 ? tempRange.lowerBound : points[i - 1].tempC + 1
        let hi = i == points.count - 1 ? tempRange.upperBound : points[i + 1].tempC - 1
        let clampedTemp = min(max(temp, lo), hi)
        let clampedFrac = min(max(rpmPct / 100, rpmRange.lowerBound), rpmRange.upperBound)
        points[i] = .init(tempC: clampedTemp, rpmFraction: clampedFrac)
    }
}
