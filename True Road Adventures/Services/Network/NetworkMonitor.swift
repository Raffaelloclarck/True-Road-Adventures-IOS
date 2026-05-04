import Foundation
import Combine
import Network

/// Houdt netwerkstatus bij en biedt eenvoudige toegankelijkheid in SwiftUI via EnvironmentObject.
final class NetworkMonitor: ObservableObject {
    @Published private(set) var status: NWPath.Status
    @Published private(set) var interfaceType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "network-monitor-queue")

    /// Productie-init: start NWPathMonitor direct.
    init() {
        self.status = .requiresConnection
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.status = path.status
                self?.interfaceType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }

    /// Test/mock-init: laat status vooraf instellen en start geen monitor.
    init(mockStatus: NWPath.Status, interfaceType: NWInterface.InterfaceType? = nil) {
        self.status = mockStatus
        self.interfaceType = interfaceType
        self.monitor = nil
    }

    static var preview: NetworkMonitor { NetworkMonitor(mockStatus: .satisfied) }

    var isOnline: Bool {
        status == .satisfied
    }

    var description: String {
        if isOnline {
            if let interfaceType {
                return "Online (\(String(describing: interfaceType)))"
            }
            return "Online"
        } else {
            return "Offline"
        }
    }

    deinit {
        monitor?.cancel()
    }
}
