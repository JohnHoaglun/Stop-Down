import Foundation
import Testing
@testable import Stop_Down

// MARK: - ExposureMath

@Suite("ExposureMath")
struct ExposureMathTests {

    @Test("EV100 value form and stop form agree")
    func evFormsAgree() {
        let valueEV = ExposureMath.ev100(iso: 200, aperture: 2.0, shutterSeconds: 1.0 / 125.0)
        let stopEV = ExposureMath.ev100(
            isoStops: ExposureMath.isoStops(200),
            apertureStops: ExposureMath.apertureStops(2.0),
            shutterStops: ExposureMath.shutterStops(1.0 / 125.0)
        )
        #expect(abs(valueEV - stopEV) < 1e-9)
    }

    @Test("Sunny-16 reference exposure is ~EV15")
    func sunnySixteen() {
        let ev = ExposureMath.ev100(iso: 100, aperture: 16, shutterSeconds: 1.0 / 125.0)
        #expect(abs(ev - 14.97) < 0.05)
    }

    @Test("Aperture stop convention anchors (photographic log2(N^2))")
    func apertureAnchors() {
        #expect(abs(ExposureMath.apertureStops(1.0)) < 1e-9)
        #expect(abs(ExposureMath.apertureStops(1.4) - 1) < 0.05)
        #expect(abs(ExposureMath.apertureStops(2.0) - 2) < 1e-9)
        #expect(abs(ExposureMath.apertureStops(2.8) - 3) < 0.05)
        #expect(abs(ExposureMath.apertureStops(4.0) - 4) < 1e-9)
    }

    @Test("ISO and shutter stop anchors")
    func isoShutterAnchors() {
        #expect(abs(ExposureMath.isoStops(100)) < 1e-9)
        #expect(abs(ExposureMath.isoStops(200) - 1) < 1e-9)
        #expect(abs(ExposureMath.isoStops(50) + 1) < 1e-9)
        #expect(abs(ExposureMath.shutterStops(1.0)) < 1e-9)
        #expect(abs(ExposureMath.shutterStops(0.5) - 1) < 1e-9)
        #expect(abs(ExposureMath.shutterStops(2.0) + 1) < 1e-9)
    }

    @Test("One full stop per axis shifts EV by exactly one stop")
    func fullStopShifts() {
        #expect(abs((ExposureMath.isoStops(200) - ExposureMath.isoStops(100)) - 1) < 1e-9)
        #expect(abs((ExposureMath.apertureStops(2.0 * sqrt(2)) - ExposureMath.apertureStops(2.0)) - 1) < 1e-9)
        #expect(abs((ExposureMath.shutterStops(1.0) - ExposureMath.shutterStops(0.5)) + 1) < 1e-9)
    }

    @Test("Stop/value round-trips across every axis")
    func roundTrip() {
        for axis in ExposureAxis.allCases {
            for stops in stride(from: -6, through: 14, by: 0.5) {
                let value = ExposureMath.value(of: axis, stops: stops)
                #expect(abs(ExposureMath.stops(of: axis, value: value) - stops) < 1e-9)
            }
        }
    }
}

// MARK: - StopQuantizer

@Suite("StopQuantizer")
struct StopQuantizerTests {

    @Test("Full-stop ties round half-down (toward −∞)")
    func fullTies() {
        #expect(StopQuantizer.quantize(1.5, to: .full).quantized == 1)
        #expect(StopQuantizer.quantize(2.5, to: .full).quantized == 2)
        #expect(StopQuantizer.quantize(-1.5, to: .full).quantized == -2)
    }

    @Test("Full-stop non-tie nearest")
    func fullNearest() {
        #expect(StopQuantizer.quantize(1.4, to: .full).quantized == 1)
        #expect(StopQuantizer.quantize(1.6, to: .full).quantized == 2)
        #expect(StopQuantizer.quantize(0.4, to: .full).quantized == 0)
        #expect(StopQuantizer.quantize(0.6, to: .full).quantized == 1)
        #expect(StopQuantizer.quantize(0.5, to: .full).quantized == 0)
    }

    @Test("On-grid inputs are unchanged")
    func onGrid() {
        #expect(StopQuantizer.quantize(3.0, to: .full).quantized == 3)
        #expect(StopQuantizer.quantize(0.5, to: .half).quantized == 0.5)
        #expect(abs(StopQuantizer.quantize(1.0 / 3.0, to: .third).quantized - 1.0 / 3.0) < 1e-9)
        #expect(!StopQuantizer.quantize(2.0, to: .full).wasRounded)
    }

    @Test("Half- and third-stop ties")
    func finerTies() {
        #expect(StopQuantizer.quantize(0.75, to: .half).quantized == 0.5)
        #expect(abs(StopQuantizer.quantize(0.5, to: .third).quantized - 1.0 / 3.0) < 1e-9)
    }

    @Test("Rounding delta is reported")
    func delta() {
        let q = StopQuantizer.quantize(1.4, to: .full)
        #expect(abs(q.delta - 0.4) < 1e-9)
        #expect(q.wasRounded)
    }
}

// MARK: - ExposureValueTables

@Suite("ExposureValueTables")
struct ExposureValueTablesTests {

    @Test("Third-stop table sizes match the spec (34 / 40 / 55)")
    func thirdStopCounts() {
        #expect(ExposureValueTables.series(axis: .iso, increment: .third).count == 34)
        #expect(ExposureValueTables.series(axis: .aperture, increment: .third).count == 40)
        #expect(ExposureValueTables.series(axis: .shutter, increment: .third).count == 55)
    }

    @Test("Third-stop ISO display fixtures match the spec")
    func isoThirdDisplay() {
        let expected = ["6", "8", "10", "12", "16", "20", "25", "32", "40", "50", "64", "80", "100", "125",
                        "160", "200", "250", "320", "400", "500", "640", "800", "1000", "1250", "1600",
                        "2000", "2500", "3200", "4000", "5000", "6400", "8000", "10000", "12800"]
        #expect(ExposureValueTables.displayLabels(axis: .iso, increment: .third) == expected)
    }

    @Test("Third-stop aperture display fixtures match the spec")
    func apertureThirdDisplay() {
        let expected = ["f/0.7", "f/0.8", "f/0.9", "f/1", "f/1.1", "f/1.2", "f/1.4", "f/1.6", "f/1.8",
                        "f/2", "f/2.2", "f/2.5", "f/2.8", "f/3.2", "f/3.5", "f/4", "f/4.5", "f/5",
                        "f/5.6", "f/6.3", "f/7.1", "f/8", "f/9", "f/10", "f/11", "f/13", "f/14",
                        "f/16", "f/18", "f/20", "f/22", "f/25", "f/29", "f/32", "f/36", "f/40",
                        "f/45", "f/51", "f/57", "f/64"]
        #expect(ExposureValueTables.displayLabels(axis: .aperture, increment: .third) == expected)
    }

    @Test("Third-stop shutter display fixtures match the spec")
    func shutterThirdDisplay() {
        let expected = ["1/8000", "1/6400", "1/5000", "1/4000", "1/3200", "1/2500", "1/2000", "1/1600",
                        "1/1250", "1/1000", "1/800", "1/640", "1/500", "1/400", "1/320", "1/250",
                        "1/200", "1/160", "1/125", "1/100", "1/80", "1/60", "1/50", "1/40", "1/30",
                        "1/25", "1/20", "1/15", "1/13", "1/10", "1/8", "1/6", "1/5", "1/4", "1/3",
                        "0.4", "0.5", "0.6", "0.8", "1", "1.3", "1.6", "2", "2.5", "3.2", "4", "5",
                        "6", "8", "10", "13", "15", "20", "25", "30"]
        #expect(ExposureValueTables.displayLabels(axis: .shutter, increment: .third) == expected)
    }

    @Test("Every series is strictly monotonic in stop space")
    func monotonic() {
        for axis in ExposureAxis.allCases {
            for increment in StopIncrement.allCases {
                let stops = ExposureValueTables.series(axis: axis, increment: increment).map { $0.stops }
                let diffs = zip(stops.dropFirst(), stops).map { $0 - $1 }
                #expect(diffs.allSatisfy { $0 > 0 } || diffs.allSatisfy { $0 < 0 })
            }
        }
    }

    @Test("Full stops are a subset of the finer increments on the same axis")
    func fullStopsSubset() {
        for axis in ExposureAxis.allCases {
            let full = Set(ExposureValueTables.series(axis: axis, increment: .full).map { $0.value })
            let half = Set(ExposureValueTables.series(axis: axis, increment: .half).map { $0.value })
            #expect(full.isSubset(of: half))
        }
    }

    @Test("Display formatter follows per-axis conventions")
    func displayFormatter() {
        #expect(ExposureValueTables.displayLabel(for: .iso, value: 125) == "125")
        #expect(ExposureValueTables.displayLabel(for: .aperture, value: 2.8) == "f/2.8")
        #expect(ExposureValueTables.displayLabel(for: .aperture, value: 2.0) == "f/2")
        #expect(ExposureValueTables.displayLabel(for: .shutter, value: 1.0 / 125.0) == "1/125")
        #expect(ExposureValueTables.displayLabel(for: .shutter, value: 1.0 / 3.0) == "1/3")
        #expect(ExposureValueTables.displayLabel(for: .shutter, value: 0.4) == "0.4")
        #expect(ExposureValueTables.displayLabel(for: .shutter, value: 30.0) == "30")
    }
}

// MARK: - ExposureSolver

@Suite("ExposureSolver")
struct ExposureSolverTests {

    @Test("Solving the shutter reproduces the dial value")
    func solveShutter() throws {
        let iso = 200.0, f = 2.8, t = 1.0 / 60.0
        let target = ExposureMath.ev100(iso: iso, aperture: f, shutterSeconds: t)
        let result = try ExposureSolver.solve(targetEV100: target, iso: iso, aperture: f, shutter: nil)
        #expect(result.solvedAxis == .shutter)
        #expect(result.settings.shutter.value == 1.0 / 60.0)
        #expect(abs(result.achievedEV100 - target) < 0.02)
    }

    @Test("Solving ISO and aperture reproduce the dial values")
    func solveISOAndAperture() throws {
        let t = 1.0 / 125.0
        let target = ExposureMath.ev100(iso: 100, aperture: 8, shutterSeconds: t)
        let isoResult = try ExposureSolver.solve(targetEV100: target, iso: nil, aperture: 8, shutter: t)
        #expect(isoResult.solvedAxis == .iso)
        #expect(isoResult.settings.iso.value == 100)

        let apResult = try ExposureSolver.solve(targetEV100: target, iso: 100, aperture: nil, shutter: t)
        #expect(apResult.solvedAxis == .aperture)
        #expect(abs(apResult.settings.aperture.value - 8.0) < 1e-9)
    }

    @Test("ND-filter compensation slows the shutter (more exposure)")
    func compensation() throws {
        let t = 1.0 / 125.0
        let target = ExposureMath.ev100(iso: 100, aperture: 8, shutterSeconds: t)
        let result = try ExposureSolver.solve(
            targetEV100: target, iso: 100, aperture: 8, shutter: nil,
            compensationStops: 2, increment: .full
        )
        #expect(result.solvedAxis == .shutter)
        // Two full stops slower than 1/125 → 1/30.
        #expect(result.settings.shutter.value == 1.0 / 30.0)
        #expect(result.achievedEV100 < target)
    }

    @Test("Out-of-range solves clamp to the supported extreme")
    func outOfRange() throws {
        let target = 30.0
        let result = try ExposureSolver.solve(targetEV100: target, iso: nil, aperture: 8, shutter: 1.0)
        #expect(result.solvedAxis == .iso)
        #expect(result.inRange == false)
        #expect(result.settings.iso.value == 6)
    }

    @Test("Exactly one axis must be solved")
    func arity() {
        #expect(throws: ExposureSolverError.self) {
            try ExposureSolver.solve(targetEV100: 10, iso: 100, aperture: 8, shutter: 0.008)
        }
        #expect(throws: ExposureSolverError.self) {
            try ExposureSolver.solve(targetEV100: 10, iso: nil, aperture: nil, shutter: nil)
        }
    }

    @Test("Achieved EV stays within half a stop of the target for in-range solves")
    func accuracyBound() throws {
        let iso = 400.0, f = 5.6, t = 1.0 / 60.0
        let target = ExposureMath.ev100(iso: iso, aperture: f, shutterSeconds: t)
        let result = try ExposureSolver.solve(targetEV100: target, iso: nil, aperture: f, shutter: t)
        #expect(abs(result.achievedEV100 - target) < 0.5)
    }
}
