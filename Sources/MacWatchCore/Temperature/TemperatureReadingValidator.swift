public enum TemperatureReadingValidator {
    public static func isValidCelsius(_ value: Double) -> Bool {
        TemperatureSample.isValidTemperatureValue(value)
    }
}
