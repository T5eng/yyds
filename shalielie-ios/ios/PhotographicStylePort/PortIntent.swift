import AppIntents
import UniformTypeIdentifiers

struct PortPhotographicStyleIntent: AppIntent {
    static var title: LocalizedStringResource = "Port Photographic Style"
    static var description = IntentDescription(
        "给 iPhone 16 之前拍的 HEIC 加上摄影风格调色盘，或给 iPhone 16/17 的片子补上质感/颗粒。像素不变。"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "HEIC 照片",
        description: "必须是原始 HEIC 文件。不要从照片 App 导入，否则会被转成 JPEG。"
    )
    var photo: IntentFile

    @Parameter(title: "加入质感/颗粒", default: true)
    var texture: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("给 \(\.$photo) 加上摄影风格") {
            \.$texture
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let result = try PortEngine.shared.port(data: photo.data, texture: texture)
        let name = result.outputFilename(from: photo.filename ?? "IMG.HEIC")
        let file = IntentFile(data: result.data, filename: name, type: .heic)
        let dialog: IntentDialog
        switch result.mode {
        case "texture":
            dialog = "已补上质感/颗粒。请把结果当文件保存，不要再从照片 App 导出。"
        default:
            dialog = "已加上摄影风格调色盘。请把结果当文件保存，或用本 App 写入相册。"
        }
        return .result(value: file, dialog: dialog)
    }
}

struct PortAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PortPhotographicStyleIntent(),
            phrases: [
                "Port photographic style with \(.applicationName)",
                "用 \(.applicationName) 给照片加摄影风格",
                "用 \(.applicationName) 加上摄影风格",
            ],
            shortTitle: "加上摄影风格",
            systemImageName: "camera.filters"
        )
    }
}
