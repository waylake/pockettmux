import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idle-sleeping while a phone is attached (F1). The
/// display may still sleep; only the system stays up.
final class SleepInhibitor {
    private var assertion: IOPMAssertionID = 0
    private(set) var isActive = false

    func set(active: Bool) {
        guard active != isActive else { return }
        if active {
            let ok = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "PocketTmux: an iPhone is attached to a tmux session" as CFString,
                &assertion)
            isActive = ok == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isActive = false
        }
    }

    deinit { set(active: false) }
}
