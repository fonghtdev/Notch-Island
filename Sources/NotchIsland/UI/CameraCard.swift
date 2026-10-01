import AVFoundation
import SwiftUI

/// Xem trước camera ngay trên đảo (như Photo Booth, lật gương). Chỉ chạy khi thẻ này đang hiện:
/// rời thẻ / đảo thu gọn là tắt camera.
struct CameraCard: View {
    private enum Status { case checking, ready, denied, unavailable, needsBundle }
    @State private var status = Status.checking

    var body: some View {
        Group {
            switch status {
            case .ready:
                CameraPreview()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .checking:
                ProgressView().controlSize(.small)
            case .denied:
                message("Cần quyền Camera", "Bật NotchIsland trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Camera.", showSettings: true)
            case .unavailable:
                message("Không thấy camera", "Máy không có camera hoặc đang bị app khác chiếm.")
            case .needsBundle:
                message("Cần chạy từ NotchIsland.app", "Bản chạy bằng swift run không xin được quyền Camera.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await prepare() }
    }

    private func prepare() async {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else { return status = .needsBundle }
        guard AVCaptureDevice.default(for: .video) != nil else { return status = .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: status = .ready
        case .notDetermined: status = await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        default: status = .denied
        }
    }

    private func message(_ title: String, _ detail: String, showSettings: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            if showSettings {
                Button("Mở Cài đặt hệ thống") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }
    func updateNSView(_ view: CameraPreviewView, context: Context) {}
    static func dismantleNSView(_ view: CameraPreviewView, coordinator: ()) { view.stop() }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "notchisland.camera")
    private let preview: AVCaptureVideoPreviewLayer

    init() {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        preview.videoGravity = .resizeAspectFill
        layer = preview
        wantsLayer = true

        queue.async { [session] in
            session.beginConfiguration()
            session.sessionPreset = .medium
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async { [weak self] in
                // Lật gương như soi gương / Photo Booth.
                guard let connection = self?.preview.connection, connection.isVideoMirroringSupported else { return }
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func stop() { queue.async { [session] in session.stopRunning() } }
}
