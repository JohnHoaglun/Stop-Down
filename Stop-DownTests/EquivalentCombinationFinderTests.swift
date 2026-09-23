import Foundation
import Testing
@testable import Stop_Down

@Suite("EquivalentCombinationFinder")
struct EquivalentCombinationFinderTests {

    /// Default dial state: ISO 100 locked, aperture 5.6 anchored, shutter
    /// solved, third-stop increment.
    private let state = ExposureState()
    private let targetEV100 = 12.0

    @Test("Third-stop rows walk ±1 full stop and keep the locked axis")
    func thirdStopRows() {
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: state,
            targetEV100: targetEV100
        )
        // ±1 full stop at third-stop increments is 6 candidates; the list is
        // capped at 5, so the last candidate is dropped.
        #expect(rows.count == 5)

        let apertures = rows.map { $0.settings.aperture.value }
        #expect(Set(apertures) == Set([5.0, 6.3, 4.5, 7.1, 4.0]))

        // The locked axis (ISO) never changes.
        for row in rows {
            #expect(row.settings.iso.value == 100)
        }

        // The current combination is excluded.
        #expect(!rows.contains { $0.settings.aperture.value == 5.6 })

        // Sorted nearest-first.
        let distances = rows.map { abs($0.anchorStepOffset) }
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 })

        // Each row reproduces the target EV (within half an increment).
        for row in rows {
            #expect(abs(row.settings.ev100 - targetEV100) < 0.15)
        }

        // Unique rows.
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("Every candidate within ±1 stop is listed when the limit allows")
    func allCandidatesWithinOneStop() {
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: state,
            targetEV100: targetEV100,
            limit: 6
        )
        let pairs = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.settings.aperture.value, $0.settings.shutter.value)
        })
        #expect(pairs[5.0] == 1.0 / 160.0)
        #expect(pairs[6.3] == 1.0 / 100.0)
        #expect(pairs[4.5] == 1.0 / 200.0)
        #expect(pairs[7.1] == 1.0 / 80.0)
        #expect(pairs[4.0] == 1.0 / 250.0)
        #expect(pairs[8.0] == 1.0 / 60.0)
    }

    @Test("Full-stop increments yield one stop either side")
    func fullStopIncrement() {
        var fullStop = ExposureState(increment: .full)
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: fullStop,
            targetEV100: targetEV100
        )
        let pairs = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.settings.aperture.value, $0.settings.shutter.value)
        })
        #expect(rows.count == 2)
        #expect(pairs[4.0] == 1.0 / 250.0)
        #expect(pairs[8.0] == 1.0 / 60.0)
    }

    @Test("The locked axis value is constant when it is not the anchor")
    func lockedApertureConstant() {
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: ExposureState(lockedAxis: .aperture, anchorAxis: .iso),
            targetEV100: targetEV100,
            limit: 6
        )
        #expect(rows.count == 6)
        for row in rows {
            #expect(row.settings.aperture.value == 5.6)
        }
        let pairs = Dictionary(uniqueKeysWithValues: rows.map {
            ($0.settings.iso.value, $0.settings.shutter.value)
        })
        // Doubling ISO halves the shutter.
        #expect(pairs[80] == 1.0 / 100.0)
        #expect(pairs[125] == 1.0 / 160.0)
        #expect(pairs[64] == 1.0 / 80.0)
        #expect(pairs[160] == 1.0 / 200.0)
        #expect(pairs[50] == 1.0 / 60.0)
        #expect(pairs[200] == 1.0 / 250.0)
    }

    @Test("Filter compensation slows the solved axis by one stop")
    func compensationSlowsSolvedAxis() {
        let plain = EquivalentCombinationFinder.nearbyCombinations(
            state: state,
            targetEV100: targetEV100
        )
        let compensated = EquivalentCombinationFinder.nearbyCombinations(
            state: state,
            targetEV100: targetEV100,
            compensationStops: 1
        )
        #expect(plain.count == compensated.count)
        for (a, b) in zip(plain, compensated) {
            #expect(a.settings.aperture.value == b.settings.aperture.value)
            #expect(abs(b.settings.shutter.value / a.settings.shutter.value - 2.0) < 0.2)
        }
    }

    @Test("Rows whose solved value leaves the supported range are dropped")
    func outOfRangeSolvedAxisDropsRows() {
        // f/2.2 anchored, EV −5: every nearby solved shutter exceeds the
        // 30 s bound, so all rows are dropped.
        var dark = ExposureState()
        dark.aperture = 2.2
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: dark,
            targetEV100: -5
        )
        #expect(rows.isEmpty)
    }

    @Test("An anchor at the table edge only lists available offsets")
    func tableEdgeAnchor() {
        // f/56 is the last full-stop aperture; only −1 (f/40) is available.
        var edge = ExposureState(increment: .full)
        edge.aperture = 56
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: edge,
            targetEV100: targetEV100
        )
        #expect(rows.count == 1)
        #expect(rows.first?.settings.aperture.value == 40.0)
        #expect(rows.first?.anchorStepOffset == -1)
    }

    @Test("An anchor value outside the table yields no rows")
    func anchorNotInTable() {
        var offTable = ExposureState()
        offTable.aperture = 9.9
        let rows = EquivalentCombinationFinder.nearbyCombinations(
            state: offTable,
            targetEV100: targetEV100
        )
        #expect(rows.isEmpty)
    }
}
