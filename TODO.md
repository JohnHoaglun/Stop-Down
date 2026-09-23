# To Do

## Now

- [x] Establish the Xcode project, targets, and canonical `scripts/verify.sh` command.
- [x] Implement a pure exposure-math engine with deterministic tests.
- [x] Reconcile the iOS deployment target (set to 26.0 to match the spec's iOS 26+).
- [x] Implement the pure, deterministic meter core (`MeterEngine`) with fixture tests.
- [x] Define the DEBUG-only Test Meter seam for simulated readings.
- [x] Meter UI: EV readout, Hold/Live, equivalent-exposure dials, filter compensation.

## Later

- [ ] Camera, native-metering, luminance-confidence, and Spot mode (real `MeteringSource` behind the seam).
- [ ] Local history, snapshots, beta, and release readiness.

Use GitHub Issues for independently trackable work; link them here rather than duplicating their content.
