# Decisions

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-09-15 | Native auto-exposure metadata is the EV authority. | The product is a reflected-light exposure guide, not a laboratory calibration tool. |
| 2026-09-15 | Keep the app local-first. | The product requires no accounts, analytics, network calls, or app-operated cloud sync. |
| 2026-09-22 | Canonical dial values are conventional photographic numbers, not exact stop grids. | The spec's third-stop lists are nice-number fixtures and the standard full/half series do not sit on exact factor-of-two grids. The dial value is the source of truth; stop offsets are always derived from it, never the reverse. |
| 2026-09-22 | ND-filter compensation lowers the target setting-EV (`target − comp`). | A filter removes light, so the dial setting must be slower (more exposure) to compensate. |
| 2026-09-22 | The meter engine is pure and timestamp-driven; luminance never changes EV. | The EV comes only from native metadata. Luminance/clipping/noise only set `ConfidenceLevel` (stabilizing/dark/clipped), so confidence can never silently alter a reported exposure. |
| 2026-09-22 | Stability = ≥3 recent samples within ±0.1 EV over a rolling 300 ms window, sampled at ≤10 Hz. | A short, bounded window gives a fast "live" feel while rejecting flicker and hand shake; the 10 Hz cap keeps CPU and smoothing predictable. |
| 2026-09-22 | Missing metadata preserves the last reading as `.stale`; if none exists it reports `.unavailable`. | The camera occasionally emits frames without complete AE metadata; showing a clearly-labeled stale value is more useful than a hard blank, while `.unavailable` keeps the UI honest before the first reading. |
