import AppKit
import Foundation

// Sendable conformances the macOS 26 SDK ships and the macOS 15 SDK does not.
//
// Sonoma port: the main line is built against the macOS 26 SDK, where `NSImage` is `Sendable` and
// images cross isolation boundaries freely. The 15.2 SDK we have to build with leaves them
// non-`Sendable`, which turns every one of those crossings into a hard error.
//
// Rather than rewrite each crossing into a carrier type, this restores the 26 SDK's behaviour for
// the two types the app moves between actors, on the strength of the invariants the code already
// states — `ImageThumbnail.Decoded` puts it plainly: "a freshly-decoded, thereafter-immutable
// `NSImage` is safe to move across the actor boundary". Both types here are used immutably: images
// are decoded off-main and only ever read on-main, and `NSString` keys are never mutated after they
// are handed to a cache.
//
// If this branch is ever rebuilt against a macOS 26 SDK, this file should be deleted: those
// conformances come from the SDK itself, and re-declaring them would be redundant (and noisy).

extension NSImage: @retroactive @unchecked Sendable {}
extension NSString: @retroactive @unchecked Sendable {}
