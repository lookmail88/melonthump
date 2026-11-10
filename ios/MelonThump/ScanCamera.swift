import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

// MARK: - FIX11: scan-style camera for appearance photos
//
// Replaces the system camera UI (CameraPicker) for the appearance photos
// (rind close-up / whole melon) on the record page's Step 1 and in the
// FIX10 journey sheet. A live rear-camera preview, dimmed outside a
// centred frame with corner brackets and a sweeping scan line; the frame
// and hint follow the photo kind. The captured photo goes through the
// SAME encoding (PhotoCapture.cameraJPEG: full-resolution JPEG, quality
// 1.0) and the caller's existing save path (MelonRecordStore.addPhoto).
// The library button opens the existing system picker with the existing
// PhotoCapture.libraryPhoto handling (original bytes).

/// The AVFoundation side: session, rear camera, photo output. All session
/// work happens on one serial queue (Apple's recommended pattern); the
/// main-actor model below only hands it requests.
final class ScanCaptureWorker: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "melonthump.scan-camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var pending: (@Sendable (Data?) -> Void)?

    /// Configures once, then starts the session. Reports whether a rear
    /// camera is running and whether it has a torch.
    func start(_ done: @escaping @Sendable (_ running: Bool, _ hasTorch: Bool) -> Void) {
        queue.async { [self] in
            if !configured {
                configured = true
                configure()
            }
            guard let device else { done(false, false); return }
            if !session.isRunning { session.startRunning() }
            done(session.isRunning, device.hasTorch && device.isTorchAvailable)
        }
    }

    func stop() {
        queue.async { [self] in
            applyTorch(false)
            if session.isRunning { session.stopRunning() }
        }
    }

    func setTorch(_ on: Bool) {
        queue.async { [self] in applyTorch(on) }
    }

    /// The device orientation drives the stored photo's orientation, as in
    /// the system camera: the caller passes the rotation coordinator's
    /// horizon-level capture angle, set on the photo connection per shot.
    func makeRotationCoordinator(previewLayer: CALayer) -> AVCaptureDevice.RotationCoordinator? {
        queue.sync { device }.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: previewLayer) }
    }

    func capture(rotationAngle: CGFloat, _ done: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            guard session.isRunning, pending == nil else { done(nil); return }
            let settings: AVCapturePhotoSettings
            if output.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            // Full resolution: the largest dimensions the active format offers.
            settings.maxPhotoDimensions = output.maxPhotoDimensions
            settings.photoQualityPrioritization = output.maxPhotoQualityPrioritization
            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            pending = done
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: (any Error)?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            let done = pending
            pending = nil
            done?(data)
        }
    }

    // MARK: queue-only

    private func configure() {
        // Rear camera only. Prefer the virtual multi-camera devices so the
        // phone can switch lenses (e.g. macro for rind close-ups) the way
        // the system camera does; fall back to the plain wide camera.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .back)
        guard let camera = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.addOutput(output)
        if let largest = camera.activeFormat.supportedMaxPhotoDimensions
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            output.maxPhotoDimensions = largest
        }
        output.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()
        // Virtual devices start on their widest lens; open at "1x" (the
        // wide camera), like the system camera.
        if let wide = camera.virtualDeviceSwitchOverVideoZoomFactors.first,
           (try? camera.lockForConfiguration()) != nil {
            camera.videoZoomFactor = CGFloat(truncating: wide)
            camera.unlockForConfiguration()
        }
        device = camera
    }

    private func applyTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard device.torchMode != mode, device.isTorchModeSupported(mode),
              (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = mode
        device.unlockForConfiguration()
    }
}

@MainActor
final class ScanCameraModel: ObservableObject {
    enum Phase { case starting, running, denied, unavailable }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var hasTorch = false
    @Published private(set) var torchOn = false
    @Published private(set) var capturing = false
    let worker = ScanCaptureWorker()
    private var active = false
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    func start() {
        guard !active else { return }
        active = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self, self.active else { return }
                    if granted { self.run() } else { self.phase = .denied }
                }
            }
        default:
            // Denied / restricted: no session; the view shows the
            // settings guidance and keeps cancel + library usable.
            phase = .denied
        }
    }

    func stop() {
        active = false
        torchOn = false
        rotationObservation = nil
        rotation = nil
        worker.stop()
    }

    func toggleTorch() {
        guard hasTorch, phase == .running else { return }
        torchOn.toggle()
        worker.setTorch(torchOn)
    }

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        setupRotation()
    }

    /// Takes one full-resolution photo and encodes it exactly as the
    /// system-camera path did (PhotoCapture.cameraJPEG). nil on failure.
    func capture(_ done: @escaping @MainActor @Sendable (Data?) -> Void) {
        guard phase == .running, !capturing else { return }
        capturing = true
        // Portrait (90°) is the UI's own orientation, the fallback.
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
        worker.capture(rotationAngle: angle) { raw in
            Task { @MainActor [weak self] in
                let jpeg = await ScanCameraModel.encode(raw)
                self?.capturing = false
                done(jpeg)
            }
        }
    }

    nonisolated static func encode(_ raw: Data?) async -> Data? {
        // UIImage(data:) carries the shot's EXIF orientation into
        // imageOrientation, and jpegData writes it back out — the same
        // as the UIImage the system camera used to hand over.
        guard let raw, let image = UIImage(data: raw) else { return nil }
        return PhotoCapture.cameraJPEG(image)
    }

    private func run() {
        worker.start { running, torch in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.active else { self.worker.stop(); return }
                self.phase = running ? .running : .unavailable
                self.hasTorch = running && torch
                self.setupRotation()
            }
        }
    }

    private func setupRotation() {
        guard phase == .running, rotation == nil, let previewLayer,
              let coordinator = worker.makeRotationCoordinator(previewLayer: previewLayer) else { return }
        rotation = coordinator
        applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor [weak self] in self?.applyPreviewAngle(angle) }
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}

final class ScanPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct ScanPreview: UIViewRepresentable {
    let model: ScanCameraModel

    func makeUIView(context: Context) -> ScanPreviewUIView {
        let view = ScanPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = model.worker.session
        model.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: ScanPreviewUIView, context: Context) {}
}

// MARK: - The scan UI

struct ScanCameraView: View {
    /// Drives the frame shape and hint. The journey sheet passes its own
    /// kind choice (switchable here too); the record page passes the
    /// section's fixed kind.
    @Binding var kind: PhotoKind
    var allowsKindSwitch = false
    let onPhoto: (Data, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(L10n.storageKey) private var languagePref = L10n.followSystem
    @StateObject private var camera = ScanCameraModel()
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var loadingLibrary = false
    @State private var failed = false
    private var l: L10n { L10n(preference: languagePref) }

    var body: some View {
        ZStack {
            viewfinder.ignoresSafeArea()
            controls
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            loadingLibrary = true
            Task {
                // The existing library handling: original bytes when accepted.
                if let (data, mime) = await PhotoCapture.libraryPhoto(item) {
                    onPhoto(data, mime)
                    dismiss()
                } else {
                    failed = true
                }
                loadingLibrary = false
            }
        }
        .onChange(of: kind) { _, _ in failed = false }
    }

    // MARK: Viewfinder (full screen, under the safe-area controls)

    private var viewfinder: some View {
        GeometryReader { geo in
            let rect = Self.frameRect(for: kind, in: geo.size)
            ZStack {
                Color.black
                if camera.phase == .starting || camera.phase == .running {
                    ScanPreview(model: camera)
                }
                // Dim everything outside the frame.
                Color.black.opacity(0.55)
                    .mask {
                        ZStack {
                            Rectangle()
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                ScanBrackets()
                    .stroke(MelonTheme.background, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                if camera.phase == .running {
                    ScanLine(reduceMotion: reduceMotion)
                        .frame(width: rect.width - 20, height: rect.height - 20)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: kind)
        }
        .allowsHitTesting(false)
    }

    /// Rind close-up: a squarish frame. Whole melon: larger and wider.
    static func frameRect(for kind: PhotoKind, in size: CGSize) -> CGRect {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        let frameSize: CGSize
        switch kind {
        case .wholeMelon:
            let width = min(size.width * 0.9, size.height * 0.6)
            frameSize = CGSize(width: width, height: width * 0.72)
        default:
            let side = min(size.width * 0.7, size.height * 0.42)
            frameSize = CGSize(width: side, height: side)
        }
        return CGRect(x: center.x - frameSize.width / 2, y: center.y - frameSize.height / 2,
                      width: frameSize.width, height: frameSize.height)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                roundButton(systemImage: "xmark", label: l.t("common.cancel")) { dismiss() }
                    .accessibilityIdentifier("scan.close")
                Spacer()
                if camera.hasTorch {
                    roundButton(systemImage: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                label: l.t("capture.torch"), highlighted: camera.torchOn) { camera.toggleTorch() }
                        .accessibilityIdentifier("scan.torch")
                }
            }
            if allowsKindSwitch {
                Picker(l.t("capture.step1"), selection: $kind) {
                    Text(l.t("capture.kindRind")).tag(PhotoKind.rindCloseUp)
                    Text(l.t("capture.kindWhole")).tag(PhotoKind.wholeMelon)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 30)
                .accessibilityIdentifier("scan.kind")
            }
            Spacer()
            guidance
            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var guidance: some View {
        VStack(spacing: 6) {
            switch camera.phase {
            case .denied, .unavailable:
                Text(l.t(camera.phase == .denied ? "capture.cameraDenied" : "capture.cameraUnavailable"))
                    .font(.subheadline.weight(.semibold))
                if camera.phase == .denied {
                    Button(l.t("capture.openSettings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(MelonTheme.background)
                    .accessibilityIdentifier("scan.openSettings")
                }
            default:
                Text(l.t(kind == .wholeMelon ? "capture.scanWhole" : "capture.scanRind"))
                    .font(.headline)
                if kind == .wholeMelon {
                    Text(l.t("capture.cardGuide"))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.85))
                }
                if failed {
                    Text(l.t("capture.saveFailed"))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(MelonTheme.recordRed)
                }
            }
        }
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("scan.hint")
    }

    private var bottomBar: some View {
        HStack {
            roundButton(systemImage: "photo.on.rectangle", label: l.t("capture.library"), size: 54) {
                showLibrary = true
            }
            .disabled(camera.capturing || loadingLibrary)
            .accessibilityIdentifier("scan.library")
            Spacer()
            shutter
            Spacer()
            Color.clear.frame(width: 54, height: 54)
        }
        .padding(.horizontal, 12)
    }

    private var shutter: some View {
        let enabled = camera.phase == .running && !camera.capturing && !loadingLibrary
        return Button {
            failed = false
            camera.capture { data in
                if let data {
                    onPhoto(data, "image/jpeg")
                    dismiss()
                } else {
                    failed = true
                }
            }
        } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 5).frame(width: 82, height: 82)
                Circle().fill(MelonTheme.background).frame(width: 66, height: 66)
                if camera.capturing || loadingLibrary {
                    ProgressView().tint(MelonTheme.deepGreen)
                } else {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(MelonTheme.deepGreen)
                }
            }
            .opacity(enabled || camera.capturing || loadingLibrary ? 1 : 0.4)
        }
        .disabled(!enabled)
        .accessibilityLabel(l.t("capture.camera"))
        .accessibilityIdentifier("scan.shutter")
    }

    private func roundButton(systemImage: String, label: String, size: CGFloat = 44,
                             highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(highlighted ? MelonTheme.deepGreen : .white)
                .frame(width: size, height: size)
                .background(highlighted ? MelonTheme.background : Color.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

/// Four L-shaped corner brackets around the frame.
struct ScanBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(34, min(rect.width, rect.height) * 0.18)
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }
}

/// A soft line sweeping down and up inside the frame; static (centred)
/// when Reduce Motion is on.
struct ScanLine: View {
    let reduceMotion: Bool
    private static let period: Double = 2.6

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                line(width: geo.size.width).position(x: geo.size.width / 2, y: geo.size.height / 2)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = (sin(t * 2 * .pi / Self.period) + 1) / 2
                    line(width: geo.size.width).position(x: geo.size.width / 2, y: geo.size.height * phase)
                }
            }
        }
    }

    private func line(width: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(colors: [MelonTheme.background.opacity(0), MelonTheme.background, MelonTheme.background.opacity(0)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: 2.5)
            .shadow(color: MelonTheme.background.opacity(0.8), radius: 6)
    }
}
