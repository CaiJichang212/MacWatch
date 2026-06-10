import Foundation

public struct TemperatureCapability: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let domain: TemperatureDomain
    public let source: TemperatureSource
    public let supported: Bool
    public let readable: Bool
    public let reasonCode: String
    public let reasonMessage: String
    public let rawKey: String?
    public let detectedAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        sessionID: UUID,
        domain: TemperatureDomain,
        source: TemperatureSource,
        supported: Bool,
        readable: Bool,
        reasonCode: String,
        reasonMessage: String,
        rawKey: String?,
        detectedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.domain = domain
        self.source = source
        self.supported = supported
        self.readable = readable
        self.reasonCode = reasonCode
        self.reasonMessage = reasonMessage
        self.rawKey = rawKey
        self.detectedAt = detectedAt
        self.updatedAt = updatedAt
    }
}
