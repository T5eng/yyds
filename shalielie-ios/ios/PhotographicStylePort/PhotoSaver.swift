import Foundation
import Photos
import UniformTypeIdentifiers

enum PhotoSaveError: LocalizedError {
    case notDeterminedDenied
    case failed

    var errorDescription: String? {
        switch self {
        case .notDeterminedDenied:
            return "没有相册写入权限。请在设置里允许「风格移植」添加照片。"
        case .failed:
            return "写入相册失败。"
        }
    }
}

/// Saves the patched HEIC bytes as a photo resource so Photos keeps the container.
/// Using JPEG export APIs would strip the style metadata this tool adds.
enum PhotoSaver {
    static func saveHEIC(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaveError.notDeterminedDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.heic.identifier
            options.shouldMoveFile = false
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}
