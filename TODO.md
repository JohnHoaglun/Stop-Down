# To Do

## Now

- [x] Establish the Xcode project, targets, and canonical `scripts/verify.sh` command.
- [x] Implement a pure exposure-math engine with deterministic tests.
- [x] Reconcile the iOS deployment target (set to 26.0 to match the spec's iOS 26+).
- [x] Implement the pure, deterministic meter core (`MeterEngine`) with fixture tests.
- [x] Define the DEBUG-only Test Meter seam for simulated readings.
- [x] Meter UI: EV readout, Hold/Live, equivalent-exposure dials, filter compensation.
- [x] Camera, native-metering, luminance-confidence, and Spot mode (real `MeteringSource` behind the seam).
- [ ] Physical-device validation: camera session, permission request/denial/recovery, Spot point-of-interest, and `lensAperture` on iOS 26 fixed-aperture hardware.

## Later

- [ ] Local history, snapshots, beta, and release readiness.

Use GitHub Issues for independently trackable work; link them here rather than duplicating their content.
