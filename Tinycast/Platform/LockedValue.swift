import Foundation

/// A back-deployment stand-in for Swift 6's `Mutex`.
///
/// `Synchronization.Mutex` is macOS 15+, so a branch that runs on 14 cannot use it. The obvious
/// substitute, `OSAllocatedUnfairLock`, is not a drop-in: its `withLock` takes a `@Sendable`
/// closure and demands `Sendable` state, which is exactly what a cache of `NSImage`s is not.
/// `NSLock` has no such restriction, and `Mutex` never had one either — this wrapper keeps the same
/// shape as `Mutex` (`LockedValue(_:)`, `withLock { ... }`) so call sites read identically.
///
/// `@unchecked Sendable` is earned by the lock, not assumed: every read and write of `value` happens
/// between `lock()` and `unlock()`.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
