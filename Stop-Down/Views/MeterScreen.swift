import SwiftUI
import UIKit

/// The main meter screen (spec §4.2, §4.7): the live camera preview as the
/// background with a high-contrast, accessible control layer — a circular
/// central EV dial, lens selection, Average/Spot modes, the equivalent-exposure
/// wheels in the lower third, and Hold/Save.
///
/// It is driven entirely by `MeteringController`, so the feed (the real camera
/// by default; the DEBUG test feed via the DEBUG feed switch) is invisible to
/// this layout.
struct MeterScreen: View {
    @State private var controller: MeteringController
    @State private var saveMessage = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showAbout = false

    @MainActor
    init(controller: MeteringController) {
        _controller = State(initialValue: controller)
    }

    var body: some View {
        GeometryReader { proxy in
            // Responsive dial (spec §4.7: 190–240 pt, smaller on small
            // screens) so the whole control stack fits the safe area.
            let dialSize = min(192, max(160, proxy.size.height * 0.26))
            ZStack {
                background
                controls(dialSize: dialSize)
                spotReticle(viewSize: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, viewSize: proxy.size)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.15), value: saveMessage)
        .sheet(isPresented: $showAbout) {
            AboutSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        if let session = controller.previewSession {
            CameraPreviewView(session: session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            MeterTheme.background.ignoresSafeArea()
        }
        // Subtle scrims keep the top/bottom control layers legible outdoors
        // (spec §4.7) without hiding the framed scene.
        VStack {
            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Control layer

    /// The control stack. The top (lens/mode) and bottom (Hold/Save) bars are
    /// pinned with safe-area insets so they stay fully on-screen and tappable
    /// even when the middle content is tall; the middle content is sized to
    /// fit between them.
    private func controls(dialSize: CGFloat) -> some View {
        VStack(spacing: 10) {
            AvailabilityBanner(controller: controller)
            #if DEBUG
            DebugTestBar(controller: controller)
            #endif
            Spacer(minLength: 4)
            CenterDial(
                reading: controller.displayedReading,
                isHeld: controller.isHeld,
                size: dialSize
            )
            ConfidenceBanner(reading: controller.displayedReading)
            Spacer(minLength: 4)
            ExposureWheels(controller: controller)
            CombinationList(controller: controller)
            IncrementAndCompensation(controller: controller)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .safeAreaInset(edge: .top, spacing: 0) {
            TopBar(controller: controller)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(MeterTheme.secondary)
                        .transition(.opacity)
                }
                BottomBar(controller: controller, onAbout: {
                    showAbout = true
                }) {
                    save()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: Spot reticle + tap-to-meter

    /// The movable reticle in Spot mode (spec §4.3). The stored point is in
    /// capture space; the inverse conversion positions it on screen.
    @ViewBuilder
    private func spotReticle(viewSize: CGSize) -> some View {
        if controller.mode == .spot, let spot = controller.spotPoint {
            let point = SpotPointConverter.viewPoint(
                bufferPoint: spot,
                viewSize: viewSize,
                bufferSize: controller.previewBufferSize,
                rotation: .right
            )
            SpotReticleView()
                .position(
                    x: point.x * viewSize.width,
                    y: point.y * viewSize.height
                )
                .accessibilityLabel("Spot metering point")
                .accessibilityIdentifier("spot-reticle")
        }
    }

    /// Tapping the framed scene in Spot mode moves the reticle (spec §4.3):
    /// the screen point is converted to capture space before it is stored.
    private func handleTap(at location: CGPoint, viewSize: CGSize) {
        guard controller.mode == .spot else { return }
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let viewPoint = CGPoint(
            x: location.x / viewSize.width,
            y: location.y / viewSize.height
        )
        let bufferPoint = SpotPointConverter.bufferPoint(
            viewPoint: viewPoint,
            viewSize: viewSize,
            bufferSize: controller.previewBufferSize,
            rotation: .right
        )
        controller.spotPoint = bufferPoint
    }

    // MARK: Save (history milestone placeholder)

    private func save() {
        saveMessage = "History saving arrives with the persistence milestone."
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { saveMessage = "" }
        }
    }
}

// MARK: - Theme (spec §4.7 design tokens)

private enum MeterTheme {
    static let background = Color(hex: 0x0B0B0D)
    static let panel = Color.black.opacity(0.68)
    static let primary = Color(hex: 0xF5F2EA)
    static let secondary = Color(hex: 0xA6A8AD)
    static let accent = Color(hex: 0xFFB000)
    static let warning = Color(hex: 0xFF7A45)
    static let success = Color(hex: 0x58B77B)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Top bar (lens + mode)

private struct TopBar: View {
    @Bindable var controller: MeteringController

    var body: some View {
        HStack(spacing: 12) {
            lensControl
            Spacer()
            Picker("Metering mode", selection: $controller.mode) {
                ForEach(MeteringMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .accessibilityIdentifier("mode-control")
        }
    }

    @ViewBuilder
    private var lensControl: some View {
        if controller.availableLensNames.count > 1 {
            Picker("Lens", selection: $controller.lens) {
                ForEach(controller.availableLensNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
            .accessibilityLabel("Selected lens")
            .accessibilityIdentifier("lens-picker")
        } else {
            Text(controller.lens)
                .font(.headline)
                .foregroundStyle(MeterTheme.primary)
                .accessibilityLabel("Selected lens")
                .accessibilityIdentifier("lens-label")
        }
    }
}

// MARK: - Central EV dial (spec §4.7)

private struct CenterDial: View {
    let reading: MeterReading?
    let isHeld: Bool
    var size: CGFloat = 192

    var body: some View {
        let ev = reading?.ev100
        let ring = ringState
        ZStack {
            // Thin partial state ring (6 pt) around the dial (spec §4.7).
            Circle()
                .trim(from: 0, to: ring.fraction)
                .stroke(ring.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .inset(by: 10)
                .fill(MeterTheme.panel)
            VStack(spacing: 6) {
                Text(modeLabel)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(MeterTheme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("EV")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MeterTheme.secondary)
                        .accessibilityHidden(true)
                    if let ev {
                        Text(evText(ev))
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MeterTheme.primary)
                            .contentTransition(.numericText())
                            .accessibilityLabel("Exposure value (EV100)")
                            .accessibilityValue(evText(ev))
                            .accessibilityIdentifier("ev-readout")
                    } else {
                        Text("—")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(MeterTheme.secondary)
                            .accessibilityLabel("No reading")
                            .accessibilityIdentifier("ev-readout")
                    }
                }
                StatePill(isHeld: isHeld, confidence: reading?.confidence)
            }
            .padding(18)
        }
        .frame(width: size, height: size)
    }

    private var modeLabel: String {
        (reading?.mode.displayName ?? "Average").uppercased()
    }

    /// The ring's arc fraction and color for the current state (spec §4.7:
    /// the thin partial ring is the state indicator).
    private var ringState: (fraction: CGFloat, color: Color) {
        guard reading?.ev100 != nil else {
            return (0.35, MeterTheme.secondary)
        }
        let confidence = reading?.confidence ?? .stabilizing
        if confidence == .stable {
            return (1.0, MeterTheme.success)
        }
        if confidence == .stabilizing {
            return (0.35, MeterTheme.accent)
        }
        return (1.0, MeterTheme.warning)
    }

    private func evText(_ ev: Double) -> String {
        String(format: "%.1f", ev)
    }
}

private struct StatePill: View {
    let isHeld: Bool
    let confidence: ConfidenceLevel?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isHeld ? MeterTheme.accent : MeterTheme.success)
                .frame(width: 8, height: 8)
            Text(isHeld ? "HOLD" : "LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(MeterTheme.primary)
            if !isHeld, let confidence, confidence == .stabilizing {
                Text("Stabilizing…")
                    .font(.caption)
                    .foregroundStyle(MeterTheme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isHeld ? "Holding reading" : "Live reading")
        .accessibilityIdentifier("live-hold-state")
    }
}

// MARK: - Confidence banner

private struct ConfidenceBanner: View {
    let reading: MeterReading?

    var body: some View {
        Group {
            if let reading, reading.confidence.isLowConfidence {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.ev100 == nil ? "No reading yet" : "Low confidence")
                        .font(.footnote.weight(.semibold))
                    if let guidance = reading.confidence.guidance {
                        Text(guidance)
                            .font(.caption)
                    }
                }
                .foregroundStyle(reading.ev100 == nil ? MeterTheme.secondary : MeterTheme.warning)
                .frame(maxWidth: 340, alignment: .leading)
                .padding(8)
                .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Low confidence: \((reading.confidence.guidance) ?? "No reading yet")")
                .accessibilityIdentifier("confidence-banner")
            }
        }
        // Reserved slot: the banner appears only when needed (spec §4.2) but
        // its presence must not shift the rest of the layout.
        .frame(minHeight: 48, alignment: .center)
    }
}

// MARK: - Camera availability

private struct AvailabilityBanner: View {
    let controller: MeteringController
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let note = controller.unavailableNote {
            VStack(alignment: .leading, spacing: 4) {
                Label("Camera unavailable", systemImage: "video.slash")
                    .font(.footnote.weight(.semibold))
                Text(note)
                    .font(.caption)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.caption.weight(.semibold))
                .tint(MeterTheme.accent)
            }
            .foregroundStyle(MeterTheme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("camera-unavailable-banner")
        }
    }
}

// MARK: - Spot reticle

private struct SpotReticleView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(MeterTheme.accent, lineWidth: 2)
            Circle()
                .fill(MeterTheme.accent.opacity(0.15))
            Circle()
                .fill(MeterTheme.accent)
                .frame(width: 4, height: 4)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

// MARK: - DEBUG test bar

#if DEBUG
private struct DebugTestBar: View {
    @Bindable var controller: MeteringController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Feed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MeterTheme.secondary)
                Picker("Feed", selection: feedBinding) {
                    ForEach(MeteringController.Feed.allCases) { feed in
                        Text(feed.label).tag(feed)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityIdentifier("debug-feed-picker")
                Spacer()
                if controller.isTestFeed {
                    Button("Step") {
                        controller.stepTestSource()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(MeterTheme.accent)
                }
            }
            if controller.isTestFeed {
                Text("DEBUG TEST DATA — not a real reading")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MeterTheme.secondary)
                Picker("Scenario", selection: scenarioBinding) {
                    ForEach(TestMeterSource.Scenario.allCases) { scenario in
                        Text(scenario.label).tag(scenario)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(8)
        .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("debug-test-bar")
    }

    private var feedBinding: Binding<MeteringController.Feed> {
        Binding(
            get: { controller.feed },
            set: { controller.setFeed($0) }
        )
    }

    private var scenarioBinding: Binding<TestMeterSource.Scenario> {
        Binding(
            get: { controller.testSource?.scenario ?? .stable },
            set: { controller.setTestScenario($0) }
        )
    }
}
#endif

// MARK: - Exposure wheels (lower third, spec §4.7)

private struct ExposureWheels: View {
    @Bindable var controller: MeteringController

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ExposureAxis.allCases, id: \.self) { axis in
                dialRow(axis)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exposure dials")
    }

    @ViewBuilder
    private func dialRow(_ axis: ExposureAxis) -> some View {
        let exposure = controller.exposure
        let isLocked = exposure.lockedAxis == axis
        let isSolved = exposure.solvedAxis == axis
        let value = exposure.display(for: axis)

        HStack(spacing: 10) {
            Button {
                controller.setLockedAxis(axis)
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(isLocked ? MeterTheme.accent : MeterTheme.secondary)
                    .frame(width: 22)
            }
            .accessibilityLabel("\(axis.displayName) \(isLocked ? "locked" : "not locked")")
            .accessibilityHint("Tap to lock \(axis.displayName)")
            .accessibilityIdentifier("lock-\(axis.rawValue)")

            Text(axis.displayName)
                .font(.subheadline)
                .foregroundStyle(isLocked ? MeterTheme.accent : MeterTheme.primary)
                .frame(width: 72, alignment: .leading)

            if isSolved {
                Text("auto")
                    .font(.caption2)
                    .foregroundStyle(MeterTheme.secondary)
            }

            Spacer(minLength: 8)

            Button {
                controller.setDial(axis, to: neighborValue(axis, by: -1))
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            .tint(MeterTheme.primary)
            .accessibilityLabel("Decrease \(axis.displayName)")
            .accessibilityIdentifier("dial-decrease-\(axis.rawValue)")

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MeterTheme.primary)
                .frame(minWidth: 84, alignment: .trailing)
                .accessibilityLabel("\(axis.displayName)")
                .accessibilityValue(value)
                .accessibilityIdentifier("dial-\(axis.rawValue)")

            Button {
                controller.setDial(axis, to: neighborValue(axis, by: 1))
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .tint(MeterTheme.primary)
            .accessibilityLabel("Increase \(axis.displayName)")
            .accessibilityIdentifier("dial-increase-\(axis.rawValue)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isLocked ? MeterTheme.accent.opacity(0.14) : MeterTheme.panel,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    /// The dial value one increment in `offset` (−1/0/+1) along the table.
    private func neighborValue(_ axis: ExposureAxis, by offset: Int) -> Double {
        let series = ExposureValueTables.series(axis: axis, increment: controller.exposure.increment)
        let current = controller.exposure.value(of: axis)
        guard let index = series.firstIndex(where: { abs($0.value - current) < 1e-6 }) else {
            return current
        }
        let target = index + offset
        guard series.indices.contains(target) else { return current }
        return series[target].value
    }
}

// MARK: - Nearby equivalent combinations (spec §4.3)

/// The compact list below the wheels: nearby equivalent combinations for the
/// current target EV. Tapping a row applies it (the anchor dial takes the
/// row's value; the engine re-solves the third axis).
private struct CombinationList: View {
    let controller: MeteringController

    var body: some View {
        let combinations = controller.nearbyCombinations
        if !combinations.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(combinations) { combination in
                    Button {
                        controller.applyCombination(combination)
                    } label: {
                        HStack(spacing: 8) {
                            Text(
                                ExposureValueTables.displayLabel(
                                    for: .iso,
                                    value: combination.settings.iso.value
                                )
                            )
                            .frame(width: 52, alignment: .trailing)
                            Text(
                                ExposureValueTables.displayLabel(
                                    for: .aperture,
                                    value: combination.settings.aperture.value
                                )
                            )
                            .frame(width: 64, alignment: .trailing)
                            Text(
                                ExposureValueTables.displayLabel(
                                    for: .shutter,
                                    value: combination.settings.shutter.value
                                )
                            )
                            .frame(width: 72, alignment: .trailing)
                            Spacer(minLength: 0)
                        }
                        .font(.caption.monospacedDigit())
                        .contentTransition(.numericText())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MeterTheme.primary)
                    .accessibilityLabel(appliedLabel(combination))
                    .accessibilityHint("Applies this equivalent exposure")
                }
            }
            .padding(6)
            .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Equivalent exposures")
            .accessibilityIdentifier("equivalent-list")
        }
    }

    private func appliedLabel(_ combination: EquivalentCombination) -> String {
        "Apply ISO \(ExposureValueTables.displayLabel(for: .iso, value: combination.settings.iso.value)), "
            + "\(ExposureValueTables.displayLabel(for: .aperture, value: combination.settings.aperture.value)), "
            + "\(ExposureValueTables.displayLabel(for: .shutter, value: combination.settings.shutter.value))"
    }
}

// MARK: - Increment + compensation

private struct IncrementAndCompensation: View {
    @Bindable var controller: MeteringController

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Stop increment")
                    .font(.subheadline)
                    .foregroundStyle(MeterTheme.secondary)
                Spacer()
                Picker("Stop increment", selection: $controller.increment) {
                    Text("Full").tag(StopIncrement.full)
                    Text("Half").tag(StopIncrement.half)
                    Text("Third").tag(StopIncrement.third)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityIdentifier("increment-picker")
            }

            HStack {
                Label(compText, systemImage: "circle.lefthalf.filled")
                    .font(.subheadline)
                    .foregroundStyle(MeterTheme.secondary)
                Spacer()
                Button {
                    bump(-1)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                .tint(MeterTheme.primary)
                .accessibilityLabel("Decrease filter compensation")
                .accessibilityIdentifier("comp-decrease")
                Text(compValueText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MeterTheme.primary)
                    .frame(minWidth: 44, alignment: .trailing)
                Button {
                    bump(1)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(MeterTheme.primary)
                .accessibilityLabel("Increase filter compensation")
                .accessibilityIdentifier("comp-increase")
            }
        }
        .padding(10)
        .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var compText: String {
        "Filter compensation"
    }

    private var compValueText: String {
        let c = controller.filterCompensationEV
        if abs(c - c.rounded()) < 1e-6 {
            return "+\(Int(c.rounded()))"
        }
        return String(format: "+%.1f", c)
    }

    private func bump(_ dir: Int) {
        let step: Double
        switch controller.increment {
        case .full: step = 1
        case .half: step = 0.5
        case .third: step = 1.0 / 3.0
        }
        let raw = controller.filterCompensationEV + Double(dir) * step
        let snapped = (raw / step).rounded() * step
        controller.filterCompensationEV = min(10, max(0, snapped))
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    @Bindable var controller: MeteringController
    var onAbout: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onAbout()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(MeterTheme.secondary)
            .accessibilityLabel("About Stop-Down")
            .accessibilityHint("Shows version and support")
            .accessibilityIdentifier("about-button")

            Button {
                controller.toggleHold()
            } label: {
                Label(controller.isHeld ? "Live" : "Hold",
                      systemImage: controller.isHeld ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MeterTheme.accent)
            .accessibilityIdentifier("hold-live")

            Button {
                onSave()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .tint(MeterTheme.primary)
            .accessibilityIdentifier("save")
        }
        .controlSize(.large)
    }
}

// MARK: - About sheet (release readiness: version, privacy, support)

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let supportURL = URL(string: "https://www.hoaglun.com/stop-down")!
    private static let supportDisplay = "www.hoaglun.com/stop-down"

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(MeterTheme.secondary)
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("about-close")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Text("Stop-Down")
                .font(.title2.weight(.bold))
                .foregroundStyle(MeterTheme.primary)
            Text("Reflected-light exposure meter")
                .font(.subheadline)
                .foregroundStyle(MeterTheme.secondary)

            Text(versionText)
                .font(.footnote)
                .foregroundStyle(MeterTheme.secondary)
                .accessibilityIdentifier("about-version")

            Text("All metering and history stay on this device. No accounts, analytics, or network requests.")
                .font(.footnote)
                .foregroundStyle(MeterTheme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            Link(destination: Self.supportURL) {
                Text(Self.supportDisplay)
                    .font(.footnote.weight(.semibold))
                    .underline()
            }
            .tint(MeterTheme.accent)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(Self.supportDisplay)")
            .accessibilityIdentifier("support-link")
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("about-sheet")
    }

    /// Read from the bundle so the displayed version can never drift from
    /// the Xcode build settings that generate the Info.plist values.
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "1"
        return "Version \(version) (\(build))"
    }
}

#Preview {
    MeterScreen(controller: MeteringController())
}
