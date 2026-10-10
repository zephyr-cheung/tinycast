import Foundation

/// Sonoma port stub.
///
/// Apple Intelligence's on-device model lives in `FoundationModels`, a macOS 26-only framework that
/// does not exist in the macOS 15 SDK this branch builds against — the module cannot even be
/// imported. So the provider is reduced to the one thing the rest of the app asks of it, and the
/// settings surface stays honest: the picker keeps its "why is it missing" line, driven by the
/// message below.
///
/// Everything around it is untouched — `AppleIntelligence` (the model metadata), the settings
/// plumbing and `AIModelSelection.appleIntelligence` — so restoring the real streaming
/// implementation is a matter of putting this file back and rebuilding against a macOS 26 SDK.
struct AppleIntelligenceProvider {
    /// Always unsupported on this branch: the framework that answers this question is not here.
    static func status() -> AppleIntelligenceStatus { .deviceNotEligible }
}
