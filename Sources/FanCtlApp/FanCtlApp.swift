import SwiftUI
import Charts
import FanCtlProtocol
import ServiceManagement
import os.log

private let log = Logger(subsystem: "com.juanipis.FanCtl", category: "App")

@main
struct FanCtlApp: App {
    @StateObject private var client = HelperClient()
    @StateObject private var installer = HelperInstaller()
    @StateObject private var updater = Updater()
    @State private var showAllTemps = false

    var body: some Scene {
        MenuBarExtra {
            MenuContent(showAllTemps: $showAllTemps)
                .environmentObject(client)
                .environmentObject(installer)
                .environmentObject(updater)
                .frame(width: 360)
                .onAppear {
                    client.startPolling()
                    Notifications.shared.requestAuthorizationIfNeeded()
                }
                .onDisappear { client.stopPolling() }
        } label: {
            MenuLabel(client: client)
        }
        .menuBarExtraStyle(.window)

        // Free-floating Preferences window. Open with `cmd+,` from any focused
        // FanCtl window or programmatically via openWindow(id: "preferences").
        Window("FanCtl Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(client)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Menu bar label

struct MenuLabel: View {
    @ObservedObject var client: HelperClient

    var body: some View {
        let mode = client.snapshot?.activeMode ?? .auto
        let isAnimated = mode != .auto
        Image(systemName: mode == .manual ? "slider.horizontal.3"
                          : mode == .cool ? "snowflake"
                          : mode == .silent ? "moon.zzz"
                          : mode == .performance ? "bolt.fill"
                          : "fanblades")
            .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isAnimated && mode == .performance)
    }
}

// MARK: - Popover

struct MenuContent: View {
    @EnvironmentObject var client: HelperClient
    @EnvironmentObject var installer: HelperInstaller
    @Binding var showAllTemps: Bool

    var body: some View {
        VStack(spacing: 0) {
            Header()
            Divider().opacity(0.4)

            if !client.isConnected {
                NotInstalledView().padding(16)
            } else if let snap = client.snapshot {
                VStack(spacing: 12) {
                    Hero(snapshot: snap, history: client.history)
                    ModePicker(active: snap.activeMode)
                    if snap.activeMode == .manual, let fan = snap.fans.first {
                        ManualSlider(fan: fan)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    TempsRow(temps: snap.temps, showAll: $showAllTemps)
                }
                .padding(14)
                .animation(.easeInOut(duration: 0.18), value: snap.activeMode)
            } else {
                ProgressView().padding(40)
            }

            if let err = client.lastError, client.isConnected {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }

            Divider().opacity(0.4)
            Footer()
        }
        .background(.regularMaterial)
    }
}

// MARK: - Header / Footer

struct Header: View {
    @EnvironmentObject var client: HelperClient
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            Text("FanCtl")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            if let mode = client.snapshot?.activeMode {
                Label(mode.displayName, systemImage: mode.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(modeTint(mode).opacity(0.18))
                    .foregroundStyle(modeTint(mode))
                    .clipShape(.capsule)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct Footer: View {
    @EnvironmentObject var client: HelperClient
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                client.setMode(.auto)
            } label: {
                Label("Auto", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!client.isConnected)
            Spacer()
            Button {
                showAbout.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .popover(isPresented: $showAbout, arrowEdge: .bottom) {
                AboutCard().padding(16).frame(width: 260)
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct AboutCard: View {
    @EnvironmentObject var updater: Updater
    @Environment(\.openWindow) private var openWindow
    private static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let build: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    private static let repoURL = URL(string: "https://github.com/Juanipis/fanctl")!
    private static let authorURL = URL(string: "https://github.com/Juanipis")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FanCtl")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("v\(Self.version) (\(Self.build))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("Native macOS fan controller for Apple Silicon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Created by").font(.caption2).foregroundStyle(.secondary)
                Link(destination: Self.authorURL) {
                    HStack(spacing: 4) {
                        Text("Juan Pablo Díaz Correa")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9))
                    }
                }
            }

            Link(destination: Self.repoURL) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("Source on GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 9))
                }
                .font(.caption)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "preferences")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                    Text("Preferences…")
                    Spacer()
                }
                .font(.caption)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                updater.checkNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                    Text(updater.canCheck ? "Check for Updates…" : "Checking…")
                    Spacer()
                }
                .font(.caption)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!updater.canCheck)

            Text("MIT-licensed. Auto-updates via Sparkle.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Hero (big number + sparkline)

struct Hero: View {
    let snapshot: SystemSnapshot
    let history: [HistorySample]

    var body: some View {
        let fan = snapshot.fans.first
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fan.map { "\(Int($0.current))" } ?? "—")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("rpm")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.1f °C", snapshot.hottestC))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(tempTint(snapshot.hottestC))
                        .monospacedDigit()
                    Text("hottest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HistoryChart(history: history)
                .frame(height: 56)

            if let fan {
                HStack(spacing: 8) {
                    InlineStat(label: "target", value: "\(Int(fan.target))")
                    InlineStat(label: "min",    value: "\(Int(fan.min))")
                    InlineStat(label: "max",    value: "\(Int(fan.max))")
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

struct InlineStat: View {
    let label: String, value: String
    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}

struct HistoryChart: View {
    let history: [HistorySample]
    var body: some View {
        Chart {
            ForEach(history) { s in
                LineMark(
                    x: .value("t", s.timestamp),
                    y: .value("rpm", s.rpm),
                    series: .value("series", "rpm")
                )
                .foregroundStyle(.tint)
                .lineStyle(.init(lineWidth: 1.4, lineCap: .round))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("t", s.timestamp),
                    y: .value("rpm", s.rpm)
                )
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)
            }
            ForEach(history) { s in
                LineMark(
                    x: .value("t", s.timestamp),
                    y: .value("°C", s.hottestC * 60),  // scale up so it's visible alongside RPM
                    series: .value("series", "temp")
                )
                .foregroundStyle(.orange.opacity(0.65))
                .lineStyle(.init(lineWidth: 1, lineCap: .round, dash: [2, 2]))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.background(Color.clear) }
    }
}

// MARK: - Mode picker (segmented pills)

struct ModePicker: View {
    let active: ControlMode
    @EnvironmentObject var client: HelperClient

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ControlMode.allCases, id: \.self) { mode in
                ModePill(mode: mode, isActive: active == mode) {
                    client.setMode(mode)
                }
            }
        }
        .padding(4)
        .background(.thinMaterial, in: .rect(cornerRadius: 11, style: .continuous))
    }
}

struct ModePill: View {
    let mode: ControlMode
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(mode.displayName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                isActive ? AnyShapeStyle(modeTint(mode).opacity(0.22))
                         : AnyShapeStyle(Color.clear),
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .foregroundStyle(isActive ? modeTint(mode) : Color.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .help(tooltipText)
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityHint(tooltipText)
    }

    private var tooltipText: String {
        if let curve = mode.curveSummary {
            return "\(mode.summary)\n\n\(curve)"
        }
        return mode.summary
    }
}

// MARK: - Manual slider card

struct ManualSlider: View {
    let fan: FanState
    @EnvironmentObject var client: HelperClient
    @State private var draftRpm: Double = 0
    @State private var dragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Manual target")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(dragging ? draftRpm : fan.target)) rpm")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
            Slider(
                value: Binding(
                    get: { dragging ? draftRpm : fan.target },
                    set: { draftRpm = $0; dragging = true }
                ),
                in: fan.min...max(fan.max, fan.min + 1),
                step: 50,
                onEditingChanged: { editing in
                    if !editing {
                        client.setManual(fan: fan.index, rpm: draftRpm)
                        dragging = false
                    }
                }
            )
            .tint(.orange)
            HStack(spacing: 6) {
                PresetButton("Min") { client.setManual(fan: fan.index, rpm: fan.min) }
                PresetButton("Mid") { client.setManual(fan: fan.index, rpm: (fan.min + fan.max) / 2) }
                PresetButton("Max") { client.setManual(fan: fan.index, rpm: fan.max) }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

struct PresetButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Temps row

struct TempsRow: View {
    let temps: [TempState]
    @Binding var showAll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Temperatures")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showAll.toggle() }
                } label: {
                    Image(systemName: showAll ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Always-visible top 3.
            HStack(spacing: 6) {
                ForEach(temps.prefix(3), id: \.key) { t in
                    TempChip(temp: t)
                }
            }

            if showAll {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(temps.dropFirst(3), id: \.key) { t in
                        HStack {
                            Text(t.key)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f °C", t.celsius))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(tempTint(t.celsius))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

struct TempChip: View {
    let temp: TempState
    var body: some View {
        VStack(spacing: 1) {
            Text(temp.key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f°", temp.celsius))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tempTint(temp.celsius))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tempTint(temp.celsius).opacity(0.10),
                    in: .rect(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Not-installed view

struct NotInstalledView: View {
    @EnvironmentObject var installer: HelperInstaller
    @EnvironmentObject var client: HelperClient
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Helper daemon is not running.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text("FanCtl needs a privileged background helper to talk to the SMC. Click below — macOS will ask you to approve it in System Settings → Login Items & Extensions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    installer.register()
                    client.reconnect()
                } label: {
                    Label("Install Helper", systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    client.reconnect()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            if let s = installer.lastStatus {
                Text(s).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SMAppService wrapper

@MainActor
final class HelperInstaller: ObservableObject {
    @Published var lastStatus: String?
    private let service = SMAppService.daemon(plistName: kHelperPlistName)

    func register() {
        // Drop any stale BTM record first. macOS keeps a record by bundle
        // UUID and won't refresh it on re-register if the bundle was
        // moved or rebuilt — `unregister` clears that. Failure here is
        // expected on the very first install.
        try? service.unregister()
        do {
            try service.register()
            lastStatus = "Registered. Approve in System Settings if prompted."
            log.info("SMAppService.register OK (after defensive unregister)")
        } catch {
            lastStatus = "register failed: \(error.localizedDescription)"
            log.error("SMAppService.register failed: \(String(describing: error), privacy: .public)")
        }
    }

    func unregister() {
        do {
            try service.unregister()
            lastStatus = "Unregistered."
        } catch {
            lastStatus = "unregister failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Theming helpers

func modeTint(_ mode: ControlMode) -> Color {
    switch mode {
    case .auto:        return .green
    case .silent:      return .indigo
    case .cool:        return .cyan
    case .performance: return .red
    case .custom:      return .pink
    case .manual:      return .orange
    }
}

func tempTint(_ c: Double) -> Color {
    switch c {
    case ..<55:  return .green
    case ..<75:  return .yellow
    default:     return .red
    }
}
