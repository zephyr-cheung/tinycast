import Foundation

// Accessibility attribute names that newer SDKs declare as constants.
//
// Sonoma port: the macOS 15.2 headers do not define `kAXSelectedTextMarkerRangeAttribute` or
// `kAXStringForTextMarkerRangeParameterizedAttribute`, although the attribute strings themselves
// have been stable since 10.9 (they are what the 26 SDK's constants expand to). Spelled out once
// here so every caller shares a single definition.

let axSelectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"

let axStringForTextMarkerRangeParameterizedAttribute = "AXStringForTextMarkerRange"
