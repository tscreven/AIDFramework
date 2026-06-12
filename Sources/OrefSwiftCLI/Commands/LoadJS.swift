import JavaScriptCore
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

/// Maps JavaScript related errors to string explanations.
public enum JSErrors: Error, CustomStringConvertible {
    case missingJSContext
    case invalidUTF8Input
    case jsException(String)
    case missingJSResult
    case couldNotLocateJSLib
    case missingModule(String)

    public var description: String {
        switch self {
        case .missingJSContext:
            return "Failed to create JavaScript context"
        case .invalidUTF8Input:
            return "Input JSON is not valid UTF-8"
        case .jsException(let message):
            return "JavaScript exception: \(message)"
        case .missingJSResult:
            return "JavaScript result was not produced"
        case .couldNotLocateJSLib:
            return "Could not locate algorithm library"
        case .missingModule(let path):
            return "JavaScript module not found: \(path)"
        }
    }
}

public func loadSourceAlgorithm(_ jsBug: Bool, _ jsIobFix: Bool, _ jsIobAutosensFix: Bool, _ jsIobAutosensDetBasalFix: Bool) throws -> String {
    if jsBug {
        return "Sources/BugOrefJSAlgorithm"
    }
    else if jsIobFix {
        return "Sources/Bug_IOB_Fix_OrefJSAlgorithm"
    }
    else if jsIobAutosensFix {
        return "Sources/Bug_IOB+AS_Fix_OrefJSAlgorithm"
    }
    else if jsIobAutosensDetBasalFix{
        return "Sources/Bug_IOB+AS+DB_Fix_OrefJSAlgorithm"
    }
    return "Sources/OrefJSAlgorithm"
}

/// Run JavaScript oref version of all commands. Each command runs through a
/// central method (e.g. runIOB()). Central methods share private methods which
/// process the appropriate JavaScript files.
public final class JavaScriptCommandRunner {
    private let context: JSContext
    private let libDirectory: URL
    private let fileManager: FileManager = FileManager.default
    private var loadedModules: Set<String> = Set<String>()

    init(lib: String) throws {
        guard let context = JSContext() else {
            throw JSErrors.missingJSContext
        }
        self.context = context
        self.libDirectory = try Self.locateJSLibDirectory(sourceLib: lib)
        context.exceptionHandler = { _, exception in
            if let exception: JSValue {
                fputs("JS Exception: \(exception)\n", stderr)
            }
        }
    }

    // Orchestration of JavaScript oref IOB algorithm.
    func runIOB(inputJSON: String) throws -> String {
        try evaluate(preludeScript())
        try registerBuiltinModules()
        try loadOrefModules(moduleID: "/lib/iob/index.js", jsFile: "index.js")

        context.setObject(inputJSON, forKeyedSubscript: "__swiftInputJSON" as NSString)
        try evaluate("""
        var __swiftParsedInput = JSON.parse(__swiftInputJSON);
        var generate = function(pumphistory, profile, clock, autosens) {
          var iobGenerate = __require('/lib/iob/index.js');
          return iobGenerate({
            history: pumphistory,
            profile: profile,
            clock: clock,
            autosens: autosens
          });
        };

        var __swiftHistory = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.history)) {
          __swiftHistory = __swiftParsedInput.history.slice().sort(function(a, b) {
            function timeValue(x) {
              if (!x) return Number.NEGATIVE_INFINITY;
              if (typeof x.date === 'number') return x.date;
              if (typeof x.timestamp === 'string') {
                var parsed = Date.parse(x.timestamp);
                if (!isNaN(parsed)) return parsed;
              }
              return Number.NEGATIVE_INFINITY;
            }
            return timeValue(b) - timeValue(a); // newest first for oref JS history parser
          });
        }
        var __swiftIobResult = generate(
          __swiftHistory,
          __swiftParsedInput ? __swiftParsedInput.profile : undefined,
          __swiftParsedInput ? __swiftParsedInput.clock : undefined,
          __swiftParsedInput ? __swiftParsedInput.autosens : undefined
        );
        var __swiftIobResultJSON = JSON.stringify(__swiftIobResult);
        """)

        guard let result = context.objectForKeyedSubscript("__swiftIobResultJSON")?.toString() else {
            throw JSErrors.missingJSResult
        }
        return result
    }

    // Orchestration of JavaScript oref Meal algorithm.
    func runMeal(inputJSON: String) throws -> String {
        try evaluate(preludeScript())
        try registerBuiltinModules()
        try loadOrefModules(moduleID: "/lib/meal/index.js", jsFile: "index.js")

        context.setObject(inputJSON, forKeyedSubscript: "__swiftInputJSON" as NSString)
        try evaluate("""
        var __swiftParsedInput = JSON.parse(__swiftInputJSON);
        var mealGenerate = __require('/lib/meal/index.js');

        function timeValue(x) {
          if (!x) return Number.NEGATIVE_INFINITY;
          if (typeof x.date === 'number') return x.date;
          if (typeof x.time === 'string') {
            var t = Date.parse(x.time);
            if (!isNaN(t)) return t;
          }
          if (typeof x.timestamp === 'string') {
            var ts = Date.parse(x.timestamp);
            if (!isNaN(ts)) return ts;
          }
          if (typeof x.dateString === 'string') {
            var ds = Date.parse(x.dateString);
            if (!isNaN(ds)) return ds;
          }
          if (typeof x.display_time === 'string') {
            var dt = Date.parse(x.display_time);
            if (!isNaN(dt)) return dt;
          }
          if (typeof x.created_at === 'string') {
            var ca = Date.parse(x.created_at);
            if (!isNaN(ca)) return ca;
          }
          return Number.NEGATIVE_INFINITY;
        }

        var __swiftPumpHistory = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.pumpHistory)) {
          __swiftPumpHistory = __swiftParsedInput.pumpHistory.slice().sort(function(a, b) {
            return timeValue(b) - timeValue(a); // newest first for oref JS history parser
          });
        }

        var __swiftGlucose = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.glucose)) {
          __swiftGlucose = __swiftParsedInput.glucose.slice().sort(function(a, b) {
            return timeValue(b) - timeValue(a); // newest first for oref JS glucose parser
          });
        }

        var __swiftMealResult = mealGenerate({
          history: __swiftPumpHistory,
          profile: __swiftParsedInput ? __swiftParsedInput.profile : undefined,
          basalprofile: __swiftParsedInput ? __swiftParsedInput.basalProfile : undefined,
          clock: __swiftParsedInput ? __swiftParsedInput.clock : undefined,
          carbs: __swiftParsedInput ? __swiftParsedInput.carbs : undefined,
          glucose: __swiftGlucose
        });
        var __swiftMealResultJSON = JSON.stringify(__swiftMealResult);
        """)

        guard let result = context.objectForKeyedSubscript("__swiftMealResultJSON")?.toString() else {
            throw JSErrors.missingJSResult
        }
        return result
    }

    // Orchestration of JavaScript oref Determine Basal algorithm.
    func runDetermineBasal(inputJSON: String) throws -> String {
        try evaluate(preludeScript())
        try registerBuiltinModules()
        try loadOrefModules(moduleID: "/lib/determine-basal/determine-basal.js", jsFile: "index.js")
        try loadOrefModules(moduleID: "/lib/glucose-get-last.js", jsFile: "index.js")
        try loadOrefModules(moduleID: "/lib/basal-set-temp.js", jsFile: "index.js")

        context.setObject(inputJSON, forKeyedSubscript: "__swiftInputJSON" as NSString)
        try evaluate("""
        var __swiftParsedInput = JSON.parse(__swiftInputJSON);
        var determineBasalGenerate = __require('/lib/determine-basal/determine-basal.js');
        var getLastGlucose = __require('/lib/glucose-get-last.js');
        var tempBasalFunctions = __require('/lib/basal-set-temp.js');

        function timeValue(x) {
          if (!x) return Number.NEGATIVE_INFINITY;
          if (typeof x.date === 'number') return x.date;
          if (typeof x.time === 'string') {
            var t = Date.parse(x.time);
            if (!isNaN(t)) return t;
          }
          if (typeof x.timestamp === 'string') {
            var ts = Date.parse(x.timestamp);
            if (!isNaN(ts)) return ts;
          }
          if (typeof x.dateString === 'string') {
            var ds = Date.parse(x.dateString);
            if (!isNaN(ds)) return ds;
          }
          if (typeof x.display_time === 'string') {
            var dt = Date.parse(x.display_time);
            if (!isNaN(dt)) return dt;
          }
          return Number.NEGATIVE_INFINITY;
        }

        var __swiftGlucose = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.glucose)) {
          __swiftGlucose = __swiftParsedInput.glucose.slice().sort(function(a, b) {
            return timeValue(b) - timeValue(a); // newest first for oref JS glucose parser
          });
        }

        var __swiftIob = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.iob)) {
          __swiftIob = __swiftParsedInput.iob.slice();
        }

        var __swiftGlucoseStatus = getLastGlucose(__swiftGlucose);
        var __swiftDetermineBasalResult = determineBasalGenerate(
          __swiftGlucoseStatus,
          __swiftParsedInput ? __swiftParsedInput.currentTemp : undefined,
          __swiftIob,
          __swiftParsedInput ? __swiftParsedInput.profile : undefined,
          __swiftParsedInput ? __swiftParsedInput.autosens : undefined,
          __swiftParsedInput ? __swiftParsedInput.meal : undefined,
          tempBasalFunctions,
          __swiftParsedInput ? __swiftParsedInput.microBolusAllowed : undefined,
          __swiftParsedInput ? __swiftParsedInput.reservoir : undefined,
          __swiftParsedInput ? __swiftParsedInput.clock : undefined,
          __swiftParsedInput ? __swiftParsedInput.pumpHistory : undefined,
          __swiftParsedInput ? __swiftParsedInput.preferences : undefined,
          __swiftParsedInput ? __swiftParsedInput.basalProfile : undefined,
          __swiftParsedInput ? __swiftParsedInput.trioCustomOrefVariables : undefined
        );
        var __swiftDetermineBasalResultJSON = JSON.stringify(__swiftDetermineBasalResult);
        """)

        guard let result = context.objectForKeyedSubscript("__swiftDetermineBasalResultJSON")?.toString() else {
            throw JSErrors.missingJSResult
        }
        flushJSLogs()
        return result
    }

    // Orchestration of JavaScript oref Autosens algorithm.
    func runAutosens(inputJSON: String) throws -> String {
        try evaluate(preludeScript())
        try registerBuiltinModules()
        try loadOrefModules(moduleID: "/lib/determine-basal/autosens.js", jsFile: "index.js")

        let inputData = Data(inputJSON.utf8)
        let autosensInput = try JSONCoding.decoder.decode(AutosensInputs.self, from: inputData)
        if autosensInput.glucose.count < 72 {
            let result = Autosens(ratio: 1, newisf: nil, error: "not enough glucose data to calculate autosens")
            let output = try JSONCoding.encoder.encode(result)
            return String(decoding: output, as: UTF8.self)
        }
        let treatments = try IobHistory.calcTempTreatments(
            history: autosensInput.history.map { $0.computedEvent() },
            profile: autosensInput.profile,
            clock: autosensInput.clock,
            autosens: nil,
            zeroTempDuration: nil
        )
        var iobByClock: [String: [String: Any]] = [:]
        for glucose in autosensInput.glucose {
            let iob = try IobCalculation.iobTotal(
                treatments: treatments,
                profile: autosensInput.profile,
                time: glucose.dateString
            )
            let key = Formatter.iso8601withFractionalSeconds.string(from: glucose.dateString)
            iobByClock[key] = [
                "iob": NSDecimalNumber(decimal: iob.iob).doubleValue,
                "activity": NSDecimalNumber(decimal: iob.activity).doubleValue,
                "basaliob": NSDecimalNumber(decimal: iob.basaliob).doubleValue,
                "bolusiob": NSDecimalNumber(decimal: iob.bolusiob).doubleValue,
                "netbasalinsulin": NSDecimalNumber(decimal: iob.netbasalinsulin).doubleValue,
                "bolusinsulin": NSDecimalNumber(decimal: iob.bolusinsulin).doubleValue,
                "time": key
            ]
        }
        let iobByClockData = try JSONSerialization.data(withJSONObject: iobByClock)
        let iobByClockJSON = String(decoding: iobByClockData, as: UTF8.self)
        context.setObject(iobByClockJSON, forKeyedSubscript: "__swiftIobByClockJSON" as NSString)

        context.setObject(inputJSON, forKeyedSubscript: "__swiftInputJSON" as NSString)
        try evaluate("""
        var __swiftParsedInput = JSON.parse(__swiftInputJSON);
        this.__swiftIobByTime = JSON.parse(__swiftIobByClockJSON);
        var detectSensitivity = __require('/lib/determine-basal/autosens.js');

        function timeValue(x) {
          if (!x) return Number.NEGATIVE_INFINITY;
          if (typeof x.date === 'number') return x.date;
          if (typeof x.dateString === 'string') {
            var ds = Date.parse(x.dateString);
            if (!isNaN(ds)) return ds;
          }
          if (typeof x.display_time === 'string') {
            var dt = Date.parse(x.display_time);
            if (!isNaN(dt)) return dt;
          }
          if (typeof x.timestamp === 'string') {
            var ts = Date.parse(x.timestamp);
            if (!isNaN(ts)) return ts;
          }
          return Number.NEGATIVE_INFINITY;
        }

        var __swiftGlucose = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.glucose)) {
          __swiftGlucose = __swiftParsedInput.glucose.slice().sort(function(a, b) {
            return timeValue(b) - timeValue(a); // newest first for oref JS autosens parser
          });
        }

        var __swiftHistory = [];
        if (__swiftParsedInput && Array.isArray(__swiftParsedInput.history)) {
          __swiftHistory = __swiftParsedInput.history.slice().sort(function(a, b) {
            return timeValue(b) - timeValue(a); // newest first for oref JS history parser
          });
        }

        function __swiftRunAutosens(deviations) {
          var __swiftInput = {
            glucose_data: __swiftGlucose.slice(),
            iob_inputs: {
              history: __swiftHistory.slice(),
              profile: __swiftParsedInput ? JSON.parse(JSON.stringify(__swiftParsedInput.profile)) : undefined,
              clock: __swiftParsedInput ? __swiftParsedInput.clock : undefined
            },
            basalprofile: __swiftParsedInput ? __swiftParsedInput.basalProfile : undefined,
            carbs: __swiftParsedInput ? __swiftParsedInput.carbs : undefined,
            temptargets: __swiftParsedInput ? __swiftParsedInput.tempTargets : undefined,
            deviations: deviations,
            retrospective: true
          };
          return detectSensitivity(__swiftInput);
        }

        var __swiftAutosens8h = __swiftRunAutosens(96);
        var __swiftAutosens24h = __swiftRunAutosens(288);
        var __swiftAutosensResult = __swiftAutosens8h.ratio < __swiftAutosens24h.ratio ? __swiftAutosens8h : __swiftAutosens24h;
        var __swiftAutosensResultJSON = JSON.stringify(__swiftAutosensResult);
        """)

        guard let result = context.objectForKeyedSubscript("__swiftAutosensResultJSON")?.toString() else {
            throw JSErrors.missingJSResult
        }
        return result
    }

    /// Attempt to interpret JavaScript code.
    private func evaluate(_ script: String) throws {
        context.evaluateScript(script)
        if let exception: JSValue = context.exception {
            let message: String = exception.toString() ?? "Unknown JS error"
            context.exception = nil
            throw JSErrors.jsException(message)
        }
    }

    /// Registering non-local shims JavaScript code requires. 
    private func registerBuiltinModules() throws {
        if !loadedModules.contains("lodash") {
            try registerModule(id: "lodash", source: lodashShim())
            loadedModules.insert("lodash")
        }
        if !loadedModules.contains("lodash/endsWith") {
            try registerModule(id: "lodash/endsWith", source: lodashEndsWithShim())
            loadedModules.insert("lodash/endsWith")
        }
        if !loadedModules.contains("moment") {
            try registerModule(id: "moment", source: momentShim())
            loadedModules.insert("moment")
        }
        if !loadedModules.contains("moment-timezone") {
            try registerModule(id: "moment-timezone", source: momentTimezoneShim())
            loadedModules.insert("moment-timezone")
        }
    }

    /// Load JavaScript Oref module and its dependencies from disk.
    private func loadOrefModules(moduleID: String, jsFile: String) throws {
        if loadedModules.contains(moduleID) { return }

        let fileURL: URL = try fileURL(forModuleID: moduleID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw JSErrors.missingModule(moduleID)
        }

        let source: String = try String(contentsOf: fileURL, encoding: .utf8)
        let transformed: String = transformModuleSource(source, moduleID: moduleID)
        for dependency: String in localDependencies(in: source, parentModuleID: moduleID, jsFile: jsFile) {
            try loadOrefModules(moduleID: dependency, jsFile: jsFile)
        }
        try registerModule(id: moduleID, source: transformed)
        loadedModules.insert(moduleID)
    }

    /// Register module into JavaScript module system.
    private func registerModule(id: String, source: String) throws {
        let encodedID: String = try toJSStringLiteral(id)
        try evaluate("""
        __define(\(encodedID), function(exports, module, require, __filename, __dirname) {
        \(source)
        });
        """)
    }

    /// Return file corresponding to the moduleID.
    private func fileURL(forModuleID moduleID: String) throws -> URL {
        let relative: String = moduleID.hasPrefix("/") ? String(moduleID.dropFirst()) : moduleID
        let trimmed: String = relative.hasPrefix("lib/") ? String(relative.dropFirst(4)) : relative
        return libDirectory.appendingPathComponent(trimmed)
    }

    // Find and return dependencies embedded in require() calls in JavaScript
    // oref files 
    private func localDependencies(in source: String, parentModuleID: String, jsFile: String) -> [String] {
        let pattern: String = #"require\(\s*['"]([^'"]+)['"]\s*\)"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsSource: NSString = source as NSString
        let matches: [NSTextCheckingResult] = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        var out: [String] = []
        var seen: Set<String> = Set<String>()

        for match: NSTextCheckingResult in matches where match.numberOfRanges > 1 {
            let raw: String = nsSource.substring(with: match.range(at: 1))
            guard raw.hasPrefix(".") else { continue }
            let resolved: String = resolveLocalModuleID(raw, parentModuleID: parentModuleID, jsFile: jsFile)
            if seen.insert(resolved).inserted {
                out.append(resolved)
            }
        }
        return out
    }

    /// Rewrites module id to be relative to be relative the parentModuleID
    /// directory.
    private func resolveLocalModuleID(_ request: String, parentModuleID: String, jsFile: String) -> String {
        let baseDir: String = (parentModuleID as NSString).deletingLastPathComponent
        let candidates: [String]
        if request.hasSuffix(".js") {
            candidates = ["\(baseDir)/\(request)"]
        } else {
            candidates = ["\(baseDir)/\(request).js", "\(baseDir)/\(request)/\(jsFile)"]
        }
        for candidate: String in candidates {
            let normalized: String = normalizeModuleID(candidate)
            if let url: URL = try? fileURL(forModuleID: normalized), fileManager.fileExists(atPath: url.path) {
                return normalized
            }
        }
        return normalizeModuleID(candidates[candidates.count - 1])
    }

    /// Normalize path for resolveLocalModuleID().
    private func normalizeModuleID(_ path: String) -> String {
        var parts: [String] = []
        for part: String.SubSequence in path.split(separator: "/", omittingEmptySubsequences: false) {
            let part: String = String(part)
            if part.isEmpty || part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Apply transformations to source for specific moduleIDs.
    private func transformModuleSource(_ source: String, moduleID: String) -> String {
        if moduleID == "/lib/iob/index.js" {
            return source.replacingOccurrences(of: "export function generate", with: "function generate")
        }
        if moduleID == "/lib/iob/total.js" {
            var transformed = source.replacingOccurrences(
                of: "    var activity = 0;",
                with: """
    var activity = 0;

function __swiftRound(value, scale) {
    var multiplier = Math.pow(10, scale);
    return Math.floor((value * multiplier) + 0.5) / multiplier;
}
"""
            )
            transformed = transformed.replacingOccurrences(
                of: "iob: Math.round(iob * 1000) / 1000,",
                with: "iob: __swiftRound(iob, 3),"
            )
            transformed = transformed.replacingOccurrences(
                of: "activity: Math.round(activity * 10000) / 10000,",
                with: "activity: __swiftRound(activity, 4),"
            )
            transformed = transformed.replacingOccurrences(
                of: "basaliob: Math.round(basaliob * 1000) / 1000,",
                with: "basaliob: __swiftRound(basaliob, 3),"
            )
            transformed = transformed.replacingOccurrences(
                of: "bolusiob: Math.round(bolusiob * 1000) / 1000,",
                with: "bolusiob: __swiftRound(bolusiob, 3),"
            )
            transformed = transformed.replacingOccurrences(
                of: "netbasalinsulin: Math.round(netbasalinsulin * 1000) / 1000,",
                with: "netbasalinsulin: __swiftRound(netbasalinsulin, 3),"
            )
            transformed = transformed.replacingOccurrences(
                of: "bolusinsulin: Math.round(bolusinsulin * 1000) / 1000,",
                with: "bolusinsulin: __swiftRound(bolusinsulin, 3),"
            )
            return transformed
        }
        if moduleID == "/lib/determine-basal/autosens.js" {
            var transformed = source.replacingOccurrences(
                of: "(!inputs.retrospective && iob.iob > 2 * currentBasal)",
                with: "(iob.iob > 2 * currentBasal)"
            )
            transformed = transformed.replacingOccurrences(
                of: "var get_iob = require('../iob');",
                with: """
var __swiftGetIobOriginal = require('../iob');
var get_iob = function(iob_inputs, currentIOBOnly, treatments) {
    if (typeof globalThis !== 'undefined' && globalThis.__swiftIobByTime && iob_inputs && iob_inputs.clock) {
        var key = new Date(iob_inputs.clock).toISOString();
        var value = globalThis.__swiftIobByTime[key];
        if (value) {
            return [value];
        }
    }
    return __swiftGetIobOriginal(iob_inputs, currentIOBOnly, treatments);
};
"""
            )
            transformed = transformed.replacingOccurrences(
                of: "avgDelta = avgDelta.toFixed(2);",
                with: "avgDelta = parseFloat(avgDelta);"
            )
            transformed = transformed.replacingOccurrences(
                of: """
        var bgi = Math.round(( -iob.activity * sens * 5 )*100)/100;
        bgi = bgi.toFixed(2);
""",
                with: """
        var rawBgi = ((-iob.activity * sens * 5) * 100) + 0.5;
        var bgi = Math.floor(rawBgi) / 100;
"""
            )
            transformed = transformed.replacingOccurrences(
                of: "deviation = deviation.toFixed(2);",
                with: "deviation = parseFloat(deviation);"
            )
            return transformed
        }
        if moduleID == "/lib/meal/total.js" {
            return source.replacingOccurrences(
                of: """
    var iob_inputs = {
        profile: profile_data
    ,   history: opts.pumphistory
    };
""",
                with: """
    var iob_inputs = {
        profile: profile_data
    ,   history: opts.pumphistory
    ,   clock: time
    };
"""
            )
        }
        return source
    }

    private func toJSStringLiteral(_ value: String) throws -> String {
        let data: Data = try JSONSerialization.data(withJSONObject: [value])
        let encoded: String = String(decoding: data, as: UTF8.self)
        return String(encoded.dropFirst().dropLast())
    }

    private func flushJSLogs() {
        guard let logValues = context.objectForKeyedSubscript("__swiftLogs"),
              !logValues.isUndefined,
              let logs = logValues.toArray() as? [String],
              !logs.isEmpty
        else {
            return
        }

        for line in logs {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// Find libary folder.
    private static func locateJSLibDirectory(sourceLib: String) throws -> URL {
        let fm: FileManager = FileManager.default
        let cwdBase: URL = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(sourceLib)
        if let cwdResolved = resolveLibDirectory(base: cwdBase, fileManager: fm) {
            return cwdResolved
        }

        let sourceURL: URL = URL(fileURLWithPath: #filePath)
        let sourceBase: URL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(sourceLib)
        if let sourceResolved = resolveLibDirectory(base: sourceBase, fileManager: fm) {
            return sourceResolved
        }

        throw JSErrors.couldNotLocateJSLib
    }

    /// Accept either an algorithm root directory containing `lib/` or `lib/` itself.
    private static func resolveLibDirectory(base: URL, fileManager fm: FileManager) -> URL? {
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let directIndex = base.appendingPathComponent("iob/index.js")
            if fm.fileExists(atPath: directIndex.path) {
                return base
            }

            let nestedLib = base.appendingPathComponent("lib")
            let nestedIndex = nestedLib.appendingPathComponent("iob/index.js")
            if fm.fileExists(atPath: nestedIndex.path) {
                return nestedLib
            }
        }
        return nil
    }

    /// JavaScript code building Node-like module runtime.
    private func preludeScript() -> String {
        """
        (function(global) {
          if (global.__require) return;
          var modules = Object.create(null);
          var cache = Object.create(null);
          function dirname(path) {
            var i = path.lastIndexOf('/');
            return i <= 0 ? '/' : path.slice(0, i);
          }
          function normalize(path) {
            var raw = path.split('/'), out = [];
            for (var i = 0; i < raw.length; i++) {
              var p = raw[i];
              if (!p || p === '.') continue;
              if (p === '..') { if (out.length) out.pop(); continue; }
              out.push(p);
            }
            return '/' + out.join('/');
          }
          function resolve(request, fromId) {
            if (request in modules) return request;
            if (request.charAt(0) !== '.') return request;
            var basePath = normalize(dirname(fromId || '/') + '/' + request);
            var candidates = [basePath, basePath + '.js', basePath + '/index.js'];
            for (var i = 0; i < candidates.length; i++) {
              if (candidates[i] in modules) return candidates[i];
            }
            return candidates[2];
          }
          global.__swiftLogs = global.__swiftLogs || [];
          global.process = global.process || {
            stderr: { write: function(){} },
            stdout: { write: function(){} }
          };
          global.console = global.console || {};
          global.console.log = global.console.log || function(){};
          global.console.error = function() {
            var line = '';
            for (var i = 0; i < arguments.length; i++) {
              if (i > 0) line += ' ';
              line += String(arguments[i]);
            }
            global.__swiftLogs.push(line);
          };
          global.__define = function(id, factory) { modules[id] = factory; };
          global.__require = function(request, fromId) {
            var id = resolve(request, fromId || '/');
            if (!(id in modules)) throw new Error('Module not found: ' + request + ' (resolved to ' + id + ')');
            if (cache[id]) return cache[id].exports;
            var module = { exports: {} };
            cache[id] = module;
            function localRequire(name) { return global.__require(name, id); }
            modules[id](module.exports, module, localRequire, id, dirname(id));
            return module.exports;
          };
        })(this);
        """
    }

    /// Implement and return subset of lodash.
    private func lodashShim() -> String {
        """
        function cloneDeep(value) {
          if (value === null || typeof value !== 'object') return value;
          if (value instanceof Date) return new Date(value.getTime());
          if (Array.isArray(value)) { var a = []; for (var i = 0; i < value.length; i++) a[i] = cloneDeep(value[i]); return a; }
          var out = {}; for (var k in value) if (Object.prototype.hasOwnProperty.call(value, k)) out[k] = cloneDeep(value[k]); return out;
        }
        function forEach(collection, iteratee) {
          if (!collection) return collection;
          var i, key, result;
          if (Array.isArray(collection)) {
            for (i = 0; i < collection.length; i++) { result = iteratee(collection[i], i, collection); if (result === false) break; }
          } else {
            for (key in collection) { if (!Object.prototype.hasOwnProperty.call(collection, key)) continue; result = iteratee(collection[key], key, collection); if (result === false) break; }
          }
          return collection;
        }
        function isEmpty(value) {
          if (value == null) return true;
          if (Array.isArray(value) || typeof value === 'string') return value.length === 0;
          for (var k in value) if (Object.prototype.hasOwnProperty.call(value, k)) return false;
          return true;
        }
        function iterateeFn(iteratee) {
          if (typeof iteratee === 'function') return iteratee;
          if (typeof iteratee === 'string') return function(o) { return o == null ? undefined : o[iteratee]; };
          return function(o) { return o; };
        }
        function sortBy(collection, iteratee) {
          var arr = (collection || []).slice();
          var fn = iterateeFn(iteratee);
          arr.sort(function(a, b) { var av = fn(a), bv = fn(b); if (av < bv) return -1; if (av > bv) return 1; return 0; });
          return arr;
        }
        function maxBy(collection, iteratee) {
          var fn = iterateeFn(iteratee), maxItem, maxValue;
          for (var i = 0; i < (collection || []).length; i++) {
            var item = collection[i], value = fn(item);
            if (i === 0 || value > maxValue) { maxItem = item; maxValue = value; }
          }
          return maxItem;
        }
        module.exports = { cloneDeep: cloneDeep, forEach: forEach, isEmpty: isEmpty, sortBy: sortBy, maxBy: maxBy };
        """
    }

    private func lodashEndsWithShim() -> String {
        """
        module.exports = function endsWith(value, target) {
          if (value == null || target == null) return false;
          var text = String(value);
          var suffix = String(target);
          if (suffix.length > text.length) return false;
          return text.slice(text.length - suffix.length) === suffix;
        };
        """
    }

    /// Return moment implementation.
    private func momentShim() -> String {
        """
        function moment(input) {
          var d = (input instanceof Date) ? new Date(input.getTime()) : new Date(input);
          return {
            _d: d,
            add: function(amount, unit) { if (unit !== 'minutes') throw new Error('moment shim only supports minutes'); this._d = new Date(this._d.getTime() + amount * 60000); return this; },
            format: function() { return this._d.toISOString(); }
          };
        }
        module.exports = moment;
        """
    }

    private func momentTimezoneShim() -> String {
        """
        function tz(input) { return input; }
        module.exports = tz;
        """
    }
}
