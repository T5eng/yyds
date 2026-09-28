import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PortedItem: Identifiable {
    let id = UUID()
    let originalName: String
    let outputName: String
    let data: Data
    let mode: String
}

struct ContentView: View {
    @State private var picking = false
    @State private var working = false
    @State private var status: String?
    @State private var error: String?
    @State private var items: [PortedItem] = []
    @State private var shareItem: SharePayload?
    @State private var texture = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    warning
                    controls
                    if working {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在改写 HEIC 元数据…")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                    if let status {
                        Text(status)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    resultList
                    footer
                }
                .padding()
            }
            .navigationTitle("风格移植")
            .fileImporter(
                isPresented: $picking,
                allowedContentTypes: [UTType.heic, UTType.heif],
                allowsMultipleSelection: true
            ) { result in
                handlePick(result)
            }
            .sheet(item: $shareItem) { payload in
                ActivityView(items: [payload.url])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("给旧款 iPhone 的 HEIC 加上摄影风格调色盘")
                .font(.title3.weight(.semibold))
            Text("像素不动，只补 Apple Photos 识别风格/质感所需的元数据。引擎来自 Shalielie v\(PortEngine.shared.version)。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("必须从「文件」选择原始 HEIC", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("从「照片」挑图会被 iOS 转成 JPEG，风格数据全部丢失。处理好的文件可以用下面的「存入相册」写回去，编辑时才会出现调色盘。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Toggle("加入 iOS 27 质感/颗粒", isOn: $texture)
            Button {
                picking = true
            } label: {
                Label("从文件选择 HEIC", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(working)
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.outputName)
                        .font(.headline)
                    Text(item.mode == "texture" ? "已补质感/颗粒" : "已加摄影风格")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("分享文件") { share(item) }
                        Button("存入相册") { save(item) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快捷指令")
                .font(.headline)
            Text("装好本 App 后，打开「快捷指令」，搜索动作「Port Photographic Style / 加上摄影风格」。把「文件」交给它，再「存储文件」。也可以安装 Scriptable 脚本，见项目 README。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("Shalielie 原项目", destination: URL(string: "https://github.com/nathanatgit/Shalielie")!)
                .font(.footnote)
        }
        .padding(.top, 8)
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            error = err.localizedDescription
        case .success(let urls):
            Task { await port(urls: urls) }
        }
    }

    @MainActor
    private func port(urls: [URL]) async {
        working = true
        error = nil
        status = nil
        defer { working = false }
        var ok = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let result = try PortEngine.shared.port(data: data, texture: texture)
                let original = url.lastPathComponent
                items.insert(
                    PortedItem(
                        originalName: original,
                        outputName: result.outputFilename(from: original),
                        data: result.data,
                        mode: result.mode
                    ),
                    at: 0
                )
                ok += 1
            } catch {
                self.error = error.localizedDescription
            }
        }
        if ok > 0 {
            status = "已处理 \(ok) 张"
        }
    }

    private func share(_ item: PortedItem) {
        do {
            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent(item.outputName)
            try item.data.write(to: url, options: .atomic)
            shareItem = SharePayload(url: url)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(_ item: PortedItem) {
        Task {
            do {
                try await PhotoSaver.saveHEIC(item.data)
                status = "已写入相册：\(item.outputName)"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
