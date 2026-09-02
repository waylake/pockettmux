import Foundation

/// Navigation stack routes. Root is Macs.
enum Route: Hashable {
    case sessions(HostProfile.ID)
    case terminal
}
