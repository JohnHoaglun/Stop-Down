# Stop-Down

## Status

Planned and in active development; no app implementation is currently present. Current roadmap stage: exposure math and deterministic tests.

## Purpose

A simple reflected-light meter for iPhone photographers using a separate manual or film camera. It meters a scene, holds a reading, and translates equivalent ISO, aperture, and shutter-speed combinations.

## Platform

iPhone 11 and newer, including iPhone SE (2nd generation and later); iOS 26+; SwiftUI, AVFoundation, and SwiftData.

## Architecture status

No production architecture exists yet. Exposure math will be independent of camera and UI. Native auto-exposure metadata will provide EV; luminance analysis will report confidence without changing EV.
