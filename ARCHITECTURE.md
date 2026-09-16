# Architecture

No production code exists yet. The intended boundary is:

`SwiftUI views → exposure domain → camera/persistence/Photos adapters`

Exposure math must be pure and deterministic. AVFoundation supplies native auto-exposure metadata as the EV authority. Luminance confidence, camera permissions, Photos saves, SwiftData history, and haptics are isolated behind testable adapters. A DEBUG-only Test Meter injects known readings.
