import Foundation
import JavaScriptCore

enum PortError: LocalizedError {
    case missingEngine
    case javaScript(String)
    case timedOut
    case notHeic
    case alreadyHasTexture
    case noThumbnail
    case unsupported
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingEngine:
            return "内置处理引擎缺失，请重新编译 App。"
        case .javaScript(let message):
            return Self.message(forCode: message)
        case .timedOut:
            return "处理超时。请换一张较小的 HEIC 再试。"
        case .notHeic:
            return Self.message(forCode: "NOT_HEIC")
        case .alreadyHasTexture:
            return Self.message(forCode: "ALREADY_HAS_TEXTURE")
        case .noThumbnail:
            return Self.message(forCode: "NO_THUMBNAIL")
        case .unsupported:
            return Self.message(forCode: "UNSUPPORTED")
        case .emptyOutput:
            return "引擎没有返回文件。"
        }
    }

    static func message(forCode code: String) -> String {
        switch code {
        case "NOT_HEIC":
            return "这不是原始 HEIC。请从「文件」App 选择照片，不要从「照片」里选（iOS 会转成 JPEG，风格数据会丢）。"
        case "ALREADY_HAS_TEXTURE":
            return "这张照片已经带有质感/颗粒，无需再处理。"
        case "NO_THUMBNAIL":
            return "这张照片没有内嵌缩略图，手机端无法处理，请用电脑上的命令行工具。"
        case "UNSUPPORTED":
            return "这张 HEIC 的排布还不支持（目前只有 48/12 和 45/15 两种布局）。"
        default:
            return "处理失败：\(code)"
        }
    }

    static func fromEngineCode(_ code: String) -> PortError {
        switch code {
        case "NOT_HEIC": return .notHeic
        case "ALREADY_HAS_TEXTURE": return .alreadyHasTexture
        case "NO_THUMBNAIL": return .noThumbnail
        case "UNSUPPORTED": return .unsupported
        default: return .javaScript(code)
        }
    }
}

struct PortResult: Sendable {
    var data: Data
    var filenameSuffix: String
    var mode: String
    var reportJSON: String

    func outputFilename(from original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        return base + filenameSuffix
    }
}

/// Runs Shalielie's HEIC porter inside JavaScriptCore. Must be used on the main thread
/// so Promise microtasks can flush on the current run loop.
@MainActor
final class PortEngine {
    static let shared = PortEngine()

    private let context: JSContext

    private init() {
        guard let context = JSContext() else {
            fatalError("JavaScriptCore unavailable")
        }
        self.context = context
        context.exceptionHandler = { _, exception in
            NSLog("PhotographicStylePort JS exception: %@", exception?.toString() ?? "?")
        }
        guard let url = Bundle.main.url(forResource: "Engine", withExtension: "js")
                ?? Bundle(for: PortEngine.self).url(forResource: "Engine", withExtension: "js") else {
            fatalError("Engine.js is missing from the app bundle")
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            fatalError("Could not read Engine.js: \(error)")
        }
        context.evaluateScript(source, withSourceURL: url)
        if context.objectForKeyedSubscript("PhotographicStylePort")?.isUndefined != false {
            fatalError("Engine.js did not register PhotographicStylePort")
        }
    }

    var version: String {
        context.objectForKeyedSubscript("PhotographicStylePort")
            .objectForKeyedSubscript("VERSION")
            .toString() ?? "unknown"
    }

    func port(data: Data, texture: Bool = true) throws -> PortResult {
        let input = data.base64EncodedString()
        context.setObject(input, forKeyedSubscript: "PORT_IN_B64" as NSString)
        context.setObject(texture, forKeyedSubscript: "PORT_TEXTURE" as NSString)
        defer {
            context.setObject(NSNull(), forKeyedSubscript: "PORT_IN_B64" as NSString)
        }
        guard let promise = context.evaluateScript(
            "PhotographicStylePort.portBase64(PORT_IN_B64, {texture: PORT_TEXTURE})"
        ) else {
            throw PortError.missingEngine
        }
        if let exception = context.exception {
            context.exception = nil
            throw PortError.fromEngineCode(exception.toString() ?? "UNSUPPORTED")
        }
        let value = try waitForPromise(promise)
        guard let dict = value.toDictionary() else { throw PortError.emptyOutput }
        guard let b64 = dict["dataBase64"] as? String, let out = Data(base64Encoded: b64) else {
            throw PortError.emptyOutput
        }
        let suffix = dict["filenameSuffix"] as? String ?? "_PhotographicStyle.HEIC"
        let mode = dict["mode"] as? String ?? "port"
        let report: String
        if let reportObject = dict["report"],
           JSONSerialization.isValidJSONObject(reportObject),
           let reportData = try? JSONSerialization.data(withJSONObject: reportObject),
           let text = String(data: reportData, encoding: .utf8) {
            report = text
        } else {
            report = "{}"
        }
        return PortResult(data: out, filenameSuffix: suffix, mode: mode, reportJSON: report)
    }

    private func waitForPromise(_ promise: JSValue) throws -> JSValue {
        if promise.isUndefined || promise.isNull { throw PortError.emptyOutput }
        if !promise.hasProperty("then") { return promise }

        var fulfilled: JSValue?
        var rejected: String?
        let onFulfilled: @convention(block) (JSValue) -> Void = { value in
            fulfilled = value
        }
        let onRejected: @convention(block) (JSValue) -> Void = { err in
            rejected = err.toString()
        }
        promise.invokeMethod("then", withArguments: [
            JSValue(object: onFulfilled, in: context) as Any,
            JSValue(object: onRejected, in: context) as Any,
        ])

        let deadline = Date().addingTimeInterval(60)
        while fulfilled == nil && rejected == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        if let rejected { throw PortError.fromEngineCode(rejected) }
        guard let fulfilled else { throw PortError.timedOut }
        return fulfilled
    }
}
