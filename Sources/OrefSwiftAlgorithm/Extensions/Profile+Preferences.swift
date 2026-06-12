import Foundation
import OrefSwiftModels

extension Profile {
    mutating func update(from preferences: Preferences) {
        maxIob = preferences.maxIOB
        min5mCarbImpact = preferences.min5mCarbimpact
        maxCOB = preferences.maxCOB
        maxDailySafetyMultiplier = preferences.maxDailySafetyMultiplier
        currentBasalSafetyMultiplier = preferences.currentBasalSafetyMultiplier
        autosensMax = preferences.autosensMax
        autosensMin = preferences.autosensMin
        halfBasalExerciseTarget = preferences.halfBasalExerciseTarget
        remainingCarbsCap = preferences.remainingCarbsCap
        smbInterval = preferences.smbInterval
        maxSMBBasalMinutes = preferences.maxSMBBasalMinutes
        maxUAMSMBBasalMinutes = preferences.maxUAMSMBBasalMinutes
        bolusIncrement = preferences.bolusIncrement
        carbsReqThreshold = preferences.carbsReqThreshold
        remainingCarbsFraction = preferences.remainingCarbsFraction
        enableSMBHighBgTarget = preferences.enableSMB_high_bg_target
        maxDeltaBgThreshold = preferences.maxDeltaBGthreshold
        insulinPeakTime = preferences.insulinPeakTime
        noisyCGMTargetMultiplier = preferences.noisyCGMTargetMultiplier
        adjustmentFactor = preferences.adjustmentFactor
        adjustmentFactorSigmoid = preferences.adjustmentFactorSigmoid
        weightPercentage = preferences.weightPercentage
        thresholdSetting = preferences.threshold_setting
        maxMealAbsorptionTime = preferences.maxMealAbsorptionTime
        smbDeliveryRatio = preferences.smbDeliveryRatio

        highTemptargetRaisesSensitivity = preferences.highTemptargetRaisesSensitivity
        lowTemptargetLowersSensitivity = preferences.lowTemptargetLowersSensitivity
        sensitivityRaisesTarget = preferences.sensitivityRaisesTarget
        resistanceLowersTarget = preferences.resistanceLowersTarget
        skipNeutralTemps = preferences.skipNeutralTemps
        enableUAM = preferences.enableUAM
        a52RiskEnable = preferences.a52RiskEnable
        enableSMBWithCOB = preferences.enableSMBWithCOB
        enableSMBWithTemptarget = preferences.enableSMBWithTemptarget
        allowSMBWithHighTemptarget = preferences.allowSMBWithHighTemptarget
        enableSMBAlways = preferences.enableSMBAlways
        enableSMBAfterCarbs = preferences.enableSMBAfterCarbs
        rewindResetsAutosens = preferences.rewindResetsAutosens
        unsuspendIfNoTemp = preferences.unsuspendIfNoTemp
        enableSMBHighBg = preferences.enableSMB_high_bg
        useCustomPeakTime = preferences.useCustomPeakTime
        suspendZerosIob = preferences.suspendZerosIOB
        useNewFormula = preferences.useNewFormula
        sigmoid = preferences.sigmoid
        tddAdjBasal = preferences.tddAdjBasal

        curve = preferences.curve
    }
}
