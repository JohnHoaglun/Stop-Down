# Decisions

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-09-15 | Native auto-exposure metadata is the EV authority. | The product is a reflected-light exposure guide, not a laboratory calibration tool. |
| 2026-09-15 | Keep the app local-first. | The product requires no accounts, analytics, network calls, or app-operated cloud sync. |
| 2026-09-22 | Canonical dial values are conventional photographic numbers, not exact stop grids. | The spec's third-stop lists are nice-number fixtures and the standard full/half series do not sit on exact factor-of-two grids. The dial value is the source of truth; stop offsets are always derived from it, never the reverse. |
| 2026-09-22 | ND-filter compensation lowers the target setting-EV (`target − comp`). | A filter removes light, so the dial setting must be slower (more exposure) to compensate. |
