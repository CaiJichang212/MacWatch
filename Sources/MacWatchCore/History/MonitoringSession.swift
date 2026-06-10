import Foundation

public struct MonitoringSession: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public let appVersion: String?
    public let model: String?
    public let chip: String?
    public let osVersion: String?

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        appVersion: String? = nil,
        model: String? = nil,
        chip: String? = nil,
        osVersion: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.appVersion = appVersion
        self.model = model
        self.chip = chip
        self.osVersion = osVersion
    }
}
