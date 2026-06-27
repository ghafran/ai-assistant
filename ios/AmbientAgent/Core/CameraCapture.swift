import Foundation
import AVFoundation
import UIKit

/// Grabs a single keyframe at the start of a session. By design we only open the
/// camera for a moment — capture one still, then tear the session down.
@MainActor
final class CameraCapture: NSObject {

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var configured = false

    func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Returns JPEG data for one frame, or nil if the camera is unavailable.
    func captureKeyframe() async -> Data? {
        guard await requestAuthorization() else { return nil }
        guard configureIfNeeded() else { return nil }

        session.startRunning()
        let data = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            self.continuation = cont
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
        session.stopRunning()
        return data
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            return false
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        configured = true
        return true
    }
}

extension CameraCapture: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.continuation?.resume(returning: data)
            self.continuation = nil
        }
    }
}
