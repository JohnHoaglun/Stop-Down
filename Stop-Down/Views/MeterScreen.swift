import SwiftUI

/// The main meter screen (spec §4.2): live readout, confidence banner, exposure
/// dials with a lock axis, filter compensation, and Hold/Live.
///
/// It is driven entirely by `MeteringController`, so the feed (DEBUG test data
/// now, the real camera later) is invisible to this layout.
struct MeterScreen: View {
    @State private var controller: MeteringController
    @State private var saveMessage = ""
    @State private var saveTask: Task<Void, Never>?

    @MainActor
    init(controller: MeteringController) {
        _controller = State(initialValue: controller)
    }

    var body: some View {
        VStack(spacing: 12) {
            TopBar(controller: controller)
            ReadoutCard(reading: controller.displayedReading)
            ConfidenceBanner(reading: controller.displayedReading)
            #if DEBUG
            if controller.isTestFeed {
                DebugTestBar(controller: controller)
            }
            #endif
            DialControls(controller: controller)
            IncrementAndCompensation(controller: controller)
            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            BottomBar(controller: controller) {
                save()
            }
        }
        .padding()
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .animation(.easeInOut(duration: 0.15), value: saveMessage)
    }

    private func save() {
        saveMessage = "History saving arrives with the persistence milestone."
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { saveMessage = "" }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Bindable var controller: MeteringController

    var body: some View {
        HStack(spacing: 12) {
            Text(controller.lens)
                .font(.headline)
                .accessibilityLabel("Selected lens")
                .accessibilityIdentifier("lens-label")
            Spacer()
            Picker("Metering mode", selection: $controller.mode) {
                ForEach(MeteringMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .accessibilityIdentifier("mode-control")
        }
    }
}

// MARK: - Readout

private struct ReadoutCard: View {
    let reading: MeterReading?

    var body: some View {
        VStack(spacing: 6) {
            if let ev = reading?.ev100 {
                Text(evText(ev))
                    .font(.system(size: 68, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Exposure value")
                    .accessibilityValue(evText(ev))
                    .accessibilityIdentifier("ev-readout")
            } else {
                Text("—")
                    .font(.system(size: 68, weight: .semibold, design: .rounded))
                    .accessibilityLabel("No reading")
                    .accessibilityIdentifier("ev-readout")
            }
            if let reading {
                HStack(spacing: 12) {
                    Text(reading.mode.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    StatePill(isHeld: false, confidence: reading.confidence)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func evText(_ ev: Double) -> String {
        String(format: "%.1f", ev)
    }
}

private struct StatePill: View {
    let isHeld: Bool
    let confidence: ConfidenceLevel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isHeld ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(isHeld ? "HOLD" : "LIVE")
                .font(.caption.weight(.bold))
            if !isHeld && confidence == .stabilizing {
                Text("Stabilizing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        if let reading, reading.confidence.isLowConfidence {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.ev100 == nil ? "No reading yet" : "Low confidence")
                    .font(.footnote.weight(.semibold))
                if let guidance = reading.confidence.guidance {
                    Text(guidance)
                        .font(.caption)
                }
            }
            .foregroundStyle(reading.ev100 == nil ? Color.secondary : Color.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Low confidence: \((reading.confidence.guidance) ?? "No reading yet")")
            .accessibilityIdentifier("confidence-banner")
        }
    }
}

// MARK: - DEBUG test bar

#if DEBUG
private struct DebugTestBar: View {
    @Bindable var controller: MeteringController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG TEST DATA — not a real reading")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("Scenario", selection: scenarioBinding) {
                    ForEach(TestMeterSource.Scenario.allCases) { scenario in
                        Text(scenario.label).tag(scenario)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
                Button("Step") {
                    controller.stepTestSource()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("debug-test-bar")
    }

    private var scenarioBinding: Binding<TestMeterSource.Scenario> {
        Binding(
            get: { controller.testSource?.scenario ?? .stable },
            set: { controller.setTestScenario($0) }
        )
    }
}
#endif

// MARK: - Exposure dials

private struct DialControls: View {
    @Bindable var controller: MeteringController

    var body: some View {
        VStack(spacing: 8) {
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
                    .foregroundStyle(isLocked ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
            }
            .accessibilityLabel("\(axis.displayName) \(isLocked ? "locked" : "not locked")")
            .accessibilityHint("Tap to lock \(axis.displayName)")
            .accessibilityIdentifier("lock-\(axis.rawValue)")

            Text(axis.displayName)
                .font(.subheadline)
                .foregroundStyle(isLocked ? Color.accentColor : Color.primary)
                .frame(width: 72, alignment: .leading)

            if isSolved {
                Text("auto")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                controller.setDial(axis, to: neighborValue(axis, by: -1))
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            .accessibilityLabel("Decrease \(axis.displayName)")
            .accessibilityIdentifier("dial-decrease-\(axis.rawValue)")

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 84, alignment: .trailing)
                .accessibilityLabel("\(axis.displayName)")
                .accessibilityValue(value)
                .accessibilityIdentifier("dial-\(axis.rawValue)")

            Button {
                controller.setDial(axis, to: neighborValue(axis, by: 1))
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .accessibilityLabel("Increase \(axis.displayName)")
            .accessibilityIdentifier("dial-increase-\(axis.rawValue)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isLocked ? Color.accentColor.opacity(0.12) : Color.clear,
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

// MARK: - Increment + compensation

private struct IncrementAndCompensation: View {
    @Bindable var controller: MeteringController

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Stop increment")
                    .font(.subheadline)
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
                Spacer()
                Button {
                    bump(-1)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Decrease filter compensation")
                .accessibilityIdentifier("comp-decrease")
                Button {
                    bump(1)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Increase filter compensation")
                .accessibilityIdentifier("comp-increase")
            }
        }
    }

    private var compText: String {
        let c = controller.filterCompensationEV
        let formatted: String
        if abs(c - c.rounded()) < 1e-6 {
            formatted = "+\(Int(c.rounded()))"
        } else {
            formatted = String(format: "+%.1f", c)
        }
        return "Filter compensation \(formatted) stops"
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
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                controller.toggleHold()
            } label: {
                Label(controller.isHeld ? "Live" : "Hold",
                      systemImage: controller.isHeld ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("hold-live")

            Button {
                onSave()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("save")
        }
        .controlSize(.large)
    }
}

#Preview {
    MeterScreen(controller: MeteringController())
}
