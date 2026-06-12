import Foundation

public struct IOBForecast {
    public let forecasts: [Decimal]
    public let minGuardGlucose: Decimal
    public let minForecastGlucose: Decimal
    public let maxForecastGlucose: Decimal
    public let lastForecastGlucose: Decimal
}

public struct COBForecast {
    public let forecasts: [Decimal]
    public let minGuardGlucose: Decimal
    public let minForecastGlucose: Decimal
    public let maxForecastGlucose: Decimal
    public let lastForecastGlucose: Decimal
}

public struct UAMForecast {
    public let forecasts: [Decimal]
    public let minGuardGlucose: Decimal
    public let minForecastGlucose: Decimal
    public let maxForecastGlucose: Decimal
    public let duration: Decimal
    public let lastForecastGlucose: Decimal
}

public struct ZTForecast {
    public let forecasts: [Decimal]
    public let minGuardGlucose: Decimal
}

public struct IndividualForecast {
    public let forecasts: [Decimal]
    public let minGuardGlucose: Decimal
    public let rawForecasts: [Decimal]
    public let duration: Decimal? // only set by UAM
}

public struct AllForecasts {
    public let iob: IOBForecast
    public let zt: ZTForecast
    public let cob: COBForecast
    public let uam: UAMForecast
}
