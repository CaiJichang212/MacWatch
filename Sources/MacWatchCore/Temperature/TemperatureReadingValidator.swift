public enum TemperatureReadingValidator {
    public static func isValidCelsius(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 110
    }
}
