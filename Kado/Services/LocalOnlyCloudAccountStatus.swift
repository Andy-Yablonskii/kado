import Observation
import KadoCore

/// The personal build's stand-in for `DefaultCloudAccountStatusObserver`.
/// That one opens a `CKContainer`, which traps without the iCloud
/// entitlement this build doesn't carry; there is no sync to report on.
@MainActor
@Observable
final class LocalOnlyCloudAccountStatus: CloudAccountStatusObserving {
    let status: CloudAccountStatus = .couldNotDetermine
    let syncHealth: CloudSyncHealth = .unknown

    func refresh() async {}
}
