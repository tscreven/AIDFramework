import Foundation

public struct TrioSettings: JSON, Equatable {
    public var units: GlucoseUnits = .mgdL
    public var closedLoop: Bool = false
    public var isUploadEnabled: Bool = false
    public var isDownloadEnabled: Bool = false
    public var useLocalGlucoseSource: Bool = false
    public var localGlucosePort: Int = 8080
    public var debugOptions: Bool = false
    public var cgm: CGMType = .none
    public var cgmPluginIdentifier: String = ""
    public var uploadGlucose: Bool = true
    public var useCalendar: Bool = false
    public var displayCalendarIOBandCOB: Bool = false
    public var displayCalendarEmojis: Bool = false
    public var glucoseBadge: Bool = false
    public var notificationsPump: Bool = true
    public var notificationsCgm: Bool = true
    public var notificationsCarb: Bool = true
    public var notificationsAlgorithm: Bool = true
    public var glucoseNotificationsOption: GlucoseNotificationsOption = .onlyAlarmLimits
    public var addSourceInfoToGlucoseNotifications: Bool = false
    public var lowGlucose: Decimal = 72
    public var highGlucose: Decimal = 270
    public var carbsRequiredThreshold: Decimal = 10
    public var showCarbsRequiredBadge: Bool = true
    public var useFPUconversion: Bool = true
    public var individualAdjustmentFactor: Decimal = 0.5
    public var timeCap: Decimal = 8
    public var minuteInterval: Decimal = 30
    public var delay: Decimal = 60
    public var useAppleHealth: Bool = false
    public var smoothGlucose: Bool = false
    public var eA1cDisplayUnit: EstimatedA1cDisplayUnit = .percent
    public var high: Decimal = 180
    public var low: Decimal = 70
    public var glucoseColorScheme: GlucoseColorScheme = .staticColor
    public var xGridLines: Bool = true
    public var yGridLines: Bool = true
    public var rulerMarks: Bool = true
    public var forecastDisplayType: ForecastDisplayType = .cone
    public var maxCarbs: Decimal = 250
    public var maxFat: Decimal = 250
    public var maxProtein: Decimal = 250
    public var confirmBolusFaster: Bool = false
    public var overrideFactor: Decimal = 0.8
    public var fattyMeals: Bool = false
    public var fattyMealFactor: Decimal = 0.7
    public var sweetMeals: Bool = false
    public var sweetMealFactor: Decimal = 1
    public var displayPresets: Bool = true
    public var confirmBolus: Bool = false
    public var useLiveActivity: Bool = false
    public var lockScreenView: LockScreenView = .simple
    public var smartStackView: LockScreenView = .simple
    public var bolusShortcut: BolusShortcutLimit = .notAllowed
    public var timeInRangeType: TimeInRangeType = .timeInTightRange
    public var useSwiftOref: Bool = false

    public init() {}
}

extension TrioSettings: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = TrioSettings()

        if let units = try? container.decode(GlucoseUnits.self, forKey: .units) {
            settings.units = units
        }
        if let closedLoop = try? container.decode(Bool.self, forKey: .closedLoop) {
            settings.closedLoop = closedLoop
        }
        if let isUploadEnabled = try? container.decode(Bool.self, forKey: .isUploadEnabled) {
            settings.isUploadEnabled = isUploadEnabled
        }
        if let isDownloadEnabled = try? container.decode(Bool.self, forKey: .isDownloadEnabled) {
            settings.isDownloadEnabled = isDownloadEnabled
        }
        if let useLocalGlucoseSource = try? container.decode(Bool.self, forKey: .useLocalGlucoseSource) {
            settings.useLocalGlucoseSource = useLocalGlucoseSource
        }
        if let localGlucosePort = try? container.decode(Int.self, forKey: .localGlucosePort) {
            settings.localGlucosePort = localGlucosePort
        }
        if let debugOptions = try? container.decode(Bool.self, forKey: .debugOptions) {
            settings.debugOptions = debugOptions
        }
        if let cgm = try? container.decode(CGMType.self, forKey: .cgm) {
            settings.cgm = cgm
        }
        if let cgmPluginIdentifier = try? container.decode(String.self, forKey: .cgmPluginIdentifier) {
            settings.cgmPluginIdentifier = cgmPluginIdentifier
        }
        if let uploadGlucose = try? container.decode(Bool.self, forKey: .uploadGlucose) {
            settings.uploadGlucose = uploadGlucose
        }
        if let useCalendar = try? container.decode(Bool.self, forKey: .useCalendar) {
            settings.useCalendar = useCalendar
        }
        if let displayCalendarIOBandCOB = try? container.decode(Bool.self, forKey: .displayCalendarIOBandCOB) {
            settings.displayCalendarIOBandCOB = displayCalendarIOBandCOB
        }
        if let displayCalendarEmojis = try? container.decode(Bool.self, forKey: .displayCalendarEmojis) {
            settings.displayCalendarEmojis = displayCalendarEmojis
        }
        if let useAppleHealth = try? container.decode(Bool.self, forKey: .useAppleHealth) {
            settings.useAppleHealth = useAppleHealth
        }
        if let glucoseBadge = try? container.decode(Bool.self, forKey: .glucoseBadge) {
            settings.glucoseBadge = glucoseBadge
        }
        if let useFPUconversion = try? container.decode(Bool.self, forKey: .useFPUconversion) {
            settings.useFPUconversion = useFPUconversion
        }
        if let individualAdjustmentFactor = try? container.decode(Decimal.self, forKey: .individualAdjustmentFactor) {
            settings.individualAdjustmentFactor = individualAdjustmentFactor
        }
        if let fattyMeals = try? container.decode(Bool.self, forKey: .fattyMeals) {
            settings.fattyMeals = fattyMeals
        }
        if let fattyMealFactor = try? container.decode(Decimal.self, forKey: .fattyMealFactor) {
            settings.fattyMealFactor = fattyMealFactor
        }
        if let sweetMeals = try? container.decode(Bool.self, forKey: .sweetMeals) {
            settings.sweetMeals = sweetMeals
        }
        if let sweetMealFactor = try? container.decode(Decimal.self, forKey: .sweetMealFactor) {
            settings.sweetMealFactor = sweetMealFactor
        }
        if let overrideFactor = try? container.decode(Decimal.self, forKey: .overrideFactor) {
            settings.overrideFactor = overrideFactor
        }
        if let timeCap = try? container.decode(Decimal.self, forKey: .timeCap) {
            settings.timeCap = timeCap
        }
        if let minuteInterval = try? container.decode(Decimal.self, forKey: .minuteInterval) {
            settings.minuteInterval = minuteInterval
        }
        if let delay = try? container.decode(Decimal.self, forKey: .delay) {
            settings.delay = delay
        }
        if let notificationsPump = try? container.decode(Bool.self, forKey: .notificationsPump) {
            settings.notificationsPump = notificationsPump
        }
        if let notificationsCgm = try? container.decode(Bool.self, forKey: .notificationsCgm) {
            settings.notificationsCgm = notificationsCgm
        }
        if let notificationsCarb = try? container.decode(Bool.self, forKey: .notificationsCarb) {
            settings.notificationsCarb = notificationsCarb
        }
        if let notificationsAlgorithm = try? container.decode(Bool.self, forKey: .notificationsAlgorithm) {
            settings.notificationsAlgorithm = notificationsAlgorithm
        }
        if let glucoseNotificationsOption = try? container.decode(
            GlucoseNotificationsOption.self,
            forKey: .glucoseNotificationsOption
        ) {
            settings.glucoseNotificationsOption = glucoseNotificationsOption
        }
        if let addSourceInfoToGlucoseNotifications = try? container.decode(
            Bool.self,
            forKey: .addSourceInfoToGlucoseNotifications
        ) {
            settings.addSourceInfoToGlucoseNotifications = addSourceInfoToGlucoseNotifications
        }
        if let lowGlucose = try? container.decode(Decimal.self, forKey: .lowGlucose) {
            settings.lowGlucose = lowGlucose
        }
        if let highGlucose = try? container.decode(Decimal.self, forKey: .highGlucose) {
            settings.highGlucose = highGlucose
        }
        if let carbsRequiredThreshold = try? container.decode(Decimal.self, forKey: .carbsRequiredThreshold) {
            settings.carbsRequiredThreshold = carbsRequiredThreshold
        }
        if let showCarbsRequiredBadge = try? container.decode(Bool.self, forKey: .showCarbsRequiredBadge) {
            settings.showCarbsRequiredBadge = showCarbsRequiredBadge
        }
        if let smoothGlucose = try? container.decode(Bool.self, forKey: .smoothGlucose) {
            settings.smoothGlucose = smoothGlucose
        }
        if let low = try? container.decode(Decimal.self, forKey: .low) {
            settings.low = low
        }
        if let high = try? container.decode(Decimal.self, forKey: .high) {
            settings.high = high
        }
        if let glucoseColorScheme = try? container.decode(GlucoseColorScheme.self, forKey: .glucoseColorScheme) {
            settings.glucoseColorScheme = glucoseColorScheme
        }
        if let xGridLines = try? container.decode(Bool.self, forKey: .xGridLines) {
            settings.xGridLines = xGridLines
        }
        if let yGridLines = try? container.decode(Bool.self, forKey: .yGridLines) {
            settings.yGridLines = yGridLines
        }
        if let rulerMarks = try? container.decode(Bool.self, forKey: .rulerMarks) {
            settings.rulerMarks = rulerMarks
        }
        if let forecastDisplayType = try? container.decode(ForecastDisplayType.self, forKey: .forecastDisplayType) {
            settings.forecastDisplayType = forecastDisplayType
        }
        if let eA1cDisplayUnit = try? container.decode(EstimatedA1cDisplayUnit.self, forKey: .eA1cDisplayUnit) {
            settings.eA1cDisplayUnit = eA1cDisplayUnit
        }
        if let maxCarbs = try? container.decode(Decimal.self, forKey: .maxCarbs) {
            settings.maxCarbs = maxCarbs
        }
        if let maxFat = try? container.decode(Decimal.self, forKey: .maxFat) {
            settings.maxFat = maxFat
        }
        if let maxProtein = try? container.decode(Decimal.self, forKey: .maxProtein) {
            settings.maxProtein = maxProtein
        }
        if let confirmBolusFaster = try? container.decode(Bool.self, forKey: .confirmBolusFaster) {
            settings.confirmBolusFaster = confirmBolusFaster
        }
        if let displayPresets = try? container.decode(Bool.self, forKey: .displayPresets) {
            settings.displayPresets = displayPresets
        }
        if let confirmBolus = try? container.decode(Bool.self, forKey: .confirmBolus) {
            settings.confirmBolus = confirmBolus
        }
        if let useLiveActivity = try? container.decode(Bool.self, forKey: .useLiveActivity) {
            settings.useLiveActivity = useLiveActivity
        }
        if let lockScreenView = try? container.decode(LockScreenView.self, forKey: .lockScreenView) {
            settings.lockScreenView = lockScreenView
        }
        if let smartStackView = try? container.decode(LockScreenView.self, forKey: .smartStackView) {
            settings.smartStackView = smartStackView
        }
        if let bolusShortcut = try? container.decode(BolusShortcutLimit.self, forKey: .bolusShortcut) {
            settings.bolusShortcut = bolusShortcut
        }
        if let timeInRangeType = try? container.decode(TimeInRangeType.self, forKey: .timeInRangeType) {
            settings.timeInRangeType = timeInRangeType
        }
        if let useSwiftOref = try? container.decode(Bool.self, forKey: .useSwiftOref) {
            settings.useSwiftOref = useSwiftOref
        }

        self = settings
    }
}
