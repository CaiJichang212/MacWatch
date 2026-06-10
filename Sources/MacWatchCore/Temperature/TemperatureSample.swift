import Foundation

public struct TemperatureSample: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let timestamp: Date
    public let metricName: String
    public let domain: TemperatureDomain
    public let deviceID: String
    public let displayName: String
    public let valueCelsius: Double?
    public let source: TemperatureSource
    public let quality: TemperatureQuality
    public let rawKey: String?
    public let errorCode: String?
    public let attributes: [String: String]

    public init(
        id: UUID,
        sessionID: UUID,
        timestamp: Date,
        metricName: String,
        domain: TemperatureDomain,
        deviceID: String,
        displayName: String,
        valueCelsius: Double?,
        source: TemperatureSource,
        quality: TemperatureQuality,
        rawKey: String? = nil,
        errorCode: String? = nil,
        attributes: [String: String] = [:]
    ) throws {
        try Self.validate(quality: quality, valueCelsius: valueCelsius)
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.metricName = metricName
        self.domain = domain
        self.deviceID = deviceID
        self.displayName = displayName
        self.valueCelsius = valueCelsius
        self.source = source
        self.quality = quality
        self.rawKey = rawKey
        self.errorCode = errorCode
        self.attributes = attributes
    }

    public static func makeValid(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        metricName: String,
        domain: TemperatureDomain,
        deviceID: String,
        displayName: String,
        valueCelsius: Double,
        source: TemperatureSource,
        rawKey: String? = nil,
        errorCode: String? = nil,
        attributes: [String: String] = [:]
    ) throws -> TemperatureSample {
        return try TemperatureSample(
            id: id,
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: metricName,
            domain: domain,
            deviceID: deviceID,
            displayName: displayName,
            valueCelsius: valueCelsius,
            source: source,
            quality: .valid,
            rawKey: rawKey,
            errorCode: errorCode,
            attributes: attributes
        )
    }

    public static func makeInvalid(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date,
        metricName: String,
        domain: TemperatureDomain,
        deviceID: String,
        displayName: String,
        quality: TemperatureQuality,
        valueCelsius: Double? = nil,
        source: TemperatureSource,
        rawKey: String? = nil,
        errorCode: String? = nil,
        attributes: [String: String] = [:]
    ) throws -> TemperatureSample {
        return try TemperatureSample(
            id: id,
            sessionID: sessionID,
            timestamp: timestamp,
            metricName: metricName,
            domain: domain,
            deviceID: deviceID,
            displayName: displayName,
            valueCelsius: valueCelsius,
            source: source,
            quality: quality,
            rawKey: rawKey,
            errorCode: errorCode,
            attributes: attributes
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            sessionID: container.decode(UUID.self, forKey: .sessionID),
            timestamp: container.decode(Date.self, forKey: .timestamp),
            metricName: container.decode(String.self, forKey: .metricName),
            domain: container.decode(TemperatureDomain.self, forKey: .domain),
            deviceID: container.decode(String.self, forKey: .deviceID),
            displayName: container.decode(String.self, forKey: .displayName),
            valueCelsius: container.decodeIfPresent(Double.self, forKey: .valueCelsius),
            source: container.decode(TemperatureSource.self, forKey: .source),
            quality: container.decode(TemperatureQuality.self, forKey: .quality),
            rawKey: container.decodeIfPresent(String.self, forKey: .rawKey),
            errorCode: container.decodeIfPresent(String.self, forKey: .errorCode),
            attributes: container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        )
    }

    private static func validate(
        quality: TemperatureQuality,
        valueCelsius: Double?
    ) throws {
        switch (quality, valueCelsius) {
        case (.valid, .some):
            return
        case (.valid, .none):
            throw TemperatureModelError.invalidSample
        case (_, .some):
            throw TemperatureModelError.invalidSample
        case (_, .none):
            return
        }
    }
}
