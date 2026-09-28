import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "正在加上摄影风格…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        spinner.startAnimating()
        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        Task { await processAll() }
    }

    @MainActor
    private func processAll() async {
        var saved = 0
        var lastError: String?
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                do {
                    let data = try await loadHEIC(from: provider)
                    let result = try PortEngine.shared.port(data: data, texture: true)
                    try await PhotoSaver.saveHEIC(result.data)
                    saved += 1
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
        if saved > 0 {
            statusLabel.text = "已写入相册 \(saved) 张。打开照片 App 编辑即可看到风格调色盘。"
        } else {
            statusLabel.text = lastError ?? PortError.notHeic.localizedDescription
        }
        spinner.stopAnimating()
        let done = UIButton(type: .system)
        done.setTitle("完成", for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }, for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(done)
        NSLayoutConstraint.activate([
            done.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            done.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func loadHEIC(from provider: NSItemProvider) async throws -> Data {
        let types = [UTType.heic.identifier, UTType.heif.identifier, "public.heic", "public.heif"]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            if let data = try? await loadData(provider, type: type), isHEIC(data) {
                return data
            }
            if let data = try? await loadFile(provider, type: type), isHEIC(data) {
                return data
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let data = try? await loadFileURL(provider), isHEIC(data) {
            return data
        }
        throw PortError.notHeic
    }

    private func loadData(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { cont.resume(throwing: error) }
                else if let data { cont.resume(returning: data) }
                else { cont.resume(throwing: PortError.notHeic) }
            }
        }
    }

    private func loadFile(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error { cont.resume(throwing: error) }
                else if let url, let data = try? Data(contentsOf: url) { cont.resume(returning: data) }
                else { cont.resume(throwing: PortError.notHeic) }
            }
        }
    }

    private func loadFileURL(_ provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error { cont.resume(throwing: error); return }
                let url = (item as? URL) ?? (item as? NSURL) as URL?
                if let url, let data = try? Data(contentsOf: url) { cont.resume(returning: data) }
                else { cont.resume(throwing: PortError.notHeic) }
            }
        }
    }

    private func isHEIC(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return String(data: data.subdata(in: 4..<8), encoding: .ascii) == "ftyp"
    }
}
