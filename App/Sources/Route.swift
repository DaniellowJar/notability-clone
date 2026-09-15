import NotabilityCore
import Foundation

/// Typed navigation routes for the NavigationStack path. A single destination
/// type removes the ambiguity of registering multiple `navigationDestination(for:)`
/// types on one stack — fragile with `[AnyHashable]` paths on recent iOS.
enum Route: Hashable {
    case notebook(Notebook)
    case record(Record)
}