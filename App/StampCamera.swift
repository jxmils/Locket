import AVFoundation
import PhotosUI
import SwiftUI

private enum LensIssue: Error { case unavailable, interrupted }

/// All device and session changes run on the same queue, including completion of a shot.
private final class StampLens: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "stampnote.lens")
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var pending: CheckedContinuation<Data, Error>?
    private var shotID: Int64?

    func start(front: Bool) async throws {
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure(front: front)
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning else { throw LensIssue.unavailable }
                    reply.resume()
                } catch { reply.resume(throwing: error) }
            }
        }
    }

    private func configure(front: Bool) throws {
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard input?.device.position != position else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        else { throw LensIssue.unavailable }
        let newInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            throw LensIssue.unavailable
        }
        session.addInput(newInput)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { session.removeInput(newInput); throw LensIssue.unavailable }
            session.addOutput(output)
        }
        input = newInput
        Self.orient(output.connection(with: .video), mirror: front)
    }

    static func orient(_ connection: AVCaptureConnection?, mirror: Bool) {
        guard let connection else { return }
        // Stampnote is portrait-only. Both the lens and the saved photo use this orientation.
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirror
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.pending?.resume(throwing: LensIssue.interrupted)
            self.pending = nil
        }
    }

    func shoot() async throws -> Data {
        try await withCheckedThrowingContinuation { reply in
            queue.async {
                guard self.session.isRunning, self.pending == nil else {
                    reply.resume(throwing: LensIssue.interrupted); return
                }
                let settings = AVCapturePhotoSettings()
                self.shotID = settings.uniqueID
                self.pending = reply
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        queue.async {
            guard self.shotID == photo.resolvedSettings.uniqueID, let reply = self.pending else { return }
            self.pending = nil
            if let data, error == nil { reply.resume(returning: data) }
            else { reply.resume(throwing: error ?? LensIssue.unavailable) }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard let error else { return }
        queue.async {
            guard self.shotID == resolvedSettings.uniqueID else { return }
            self.pending?.resume(throwing: error)
            self.pending = nil
        }
    }
}

private final class LensSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
private struct LivePicture: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool
    let ready: Bool
    func makeUIView(context: Context) -> LensSurface {
        let view = LensSurface()
        view.preview.videoGravity = .resizeAspectFill
        view.preview.session = session
        return view
    }
    func updateUIView(_ view: LensSurface, context: Context) {
        if ready { StampLens.orient(view.preview.connection, mirror: front) }
    }
}

/// Normalize EXIF orientation first, then keep the centered square shown by the viewfinder.
private func stampPhoto(_ data: Data) throws -> Data {
    let normalized = try Storage.bytes(data, limit: 2048)
    guard let bitmap = UIImage(data: normalized)?.cgImage else { throw LocketIssue.photo }
    let size = min(bitmap.width, bitmap.height)
    let rect = CGRect(x: (bitmap.width-size)/2, y: (bitmap.height-size)/2, width: size, height: size)
    guard let crop = bitmap.cropping(to: rect), let bytes = UIImage(cgImage: crop).jpegData(compressionQuality: 0.94)
    else { throw LocketIssue.photo }
    return bytes
}

struct StampCamera: View {
    let book: Book
    let active: Bool
    @EnvironmentObject private var library: Library
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var lens = StampLens()
    @State private var front = false
    @State private var ready = false
    @State private var taking = false
    @State private var contact = false
    @State private var impression = false
    @State private var lockedPhoto: Data?
    @State private var selected: PhotosPickerItem?
    @State private var problem: String?
    @State private var accessDenied = false
    @State private var run = UUID()
    @State private var fixture: Data?
    private let dark = Color(red: 0.105, green: 0.10, blue: 0.135)

    private var useLens: Bool { active && phase == .active && lockedPhoto == nil }
    private var date: String {
        let day = book.day(.now)
        return Stamp(id: day, day: day, posted: .now, photo: "", thumbnail: "").dateLabel
    }
    var body: some View {
        GeometryReader { geo in
            let width = max(1, min(geo.size.width - 34, (geo.size.height - 170) / 1.105, 490))
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today’s stamp").font(.system(.title, design: .serif).italic())
                    Spacer()
                    Label(date.uppercased(), systemImage: "calendar")
                        .font(.caption2.monospaced().weight(.medium))
                }.padding(.horizontal, 22).padding(.top, 12)
                Spacer(minLength: 8)
                PostageFace(date: date, inked: impression) {
                    if let lockedPhoto, let img = UIImage(data: lockedPhoto) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else if let fixture, let img = UIImage(data: fixture) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        ZStack {
                            dark
                            LivePicture(session: lens.session, front: front, ready: ready).opacity(ready ? 1 : 0)
                            if !ready && problem == nil { ProgressView().tint(.white) }
                            if let problem {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera").font(.title)
                                    Text(problem).font(.callout).multilineTextAlignment(.center)
                                    if accessDenied {
                                        Button("Open Settings") {
                                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                        }.underline()
                                    }
                                }.padding(24).foregroundStyle(.white)
                            }
                        }
                    }
                }
                .frame(width: width, height: width * 1.105)
                .scaleEffect(reduceMotion ? 1 : contact ? 0.964 : 1)
                .overlay {
                    // The full die descends onto the frozen print and leaves the perforations and ink behind.
                    ZStack {
                        PerforatedPaper().stroke(Paper.stock, lineWidth: max(3, width * 0.018))
                        Rectangle().strokeBorder(Paper.red.opacity(0.85), lineWidth: 1.5)
                            .padding(width * 0.034)
                        Postmark().frame(width: width * 0.245, height: width * 0.14)
                            .rotationEffect(.degrees(-12))
                            .position(x: width * 0.89, y: width * 0.918)
                    }
                        .shadow(color: .black.opacity(contact ? 0 : 0.5), radius: 4, y: 5)
                        .scaleEffect(reduceMotion ? 1 : (contact ? 1 : 1.16), anchor: .center)
                        .offset(y: reduceMotion ? 0 : (contact ? 0 : -28))
                        .opacity(taking && lockedPhoto != nil && !impression ? 0.94 : 0)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(contact ? 0.14 : 0.38), radius: contact ? 1 : 7, y: contact ? 1 : 6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(lockedPhoto == nil ? "Stamp-shaped camera viewfinder" : "Captured photo stamp")
                Spacer(minLength: 8)
                if lockedPhoto != nil && !taking {
                    HStack(spacing: 18) {
                        Button("Retake") { reset() }.frame(minHeight: 48)
                        Button {
                            guard let data = lockedPhoto else { return }
                            Task { _ = await library.publish(data) }
                        } label: {
                            HStack {
                                if library.saving { ProgressView().tint(Paper.ink) }
                                Text(library.saving ? "Posting…" : "Post stamp")
                                Image(systemName: "arrow.up.right")
                            }.font(.headline).padding(.horizontal, 24).frame(height: 50)
                                .background(Paper.stock, in: Capsule()).foregroundStyle(Paper.ink)
                        }
                    }.disabled(library.saving).frame(height: 76)
                } else {
                    HStack {
                        PhotosPicker(selection: $selected, matching: .images) {
                            Image(systemName: "photo.on.rectangle").frame(width: 48, height: 48)
                        }.accessibilityLabel("Choose from Photos").disabled(taking)
                        Spacer()
                        Button { shutter() } label: {
                            ZStack {
                                Circle().strokeBorder(Paper.stock, lineWidth: 2)
                                Circle().fill(Color(red: 0.98, green: 0.38, blue: 0.24)).padding(6)
                                Circle().strokeBorder(.black.opacity(0.22), lineWidth: 1).padding(9)
                            }.frame(width: 72, height: 72)
                        }.disabled((!ready && fixture == nil) || taking)
                            .opacity(ready || fixture != nil ? 1 : 0.45)
                            .accessibilityLabel("Take stamp photo")
                        Spacer()
                        Button { ready = false; front.toggle() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 48, height: 48)
                        }.accessibilityLabel("Switch camera").disabled(!ready || taking)
                    }.font(.title3).padding(.horizontal, 38).frame(height: 76)
                }
                Spacer().frame(height: 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Paper.stock).tint(Paper.stock).buttonStyle(.plain)
        .background(dark.ignoresSafeArea())
        .toolbarBackground(dark, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .sensoryFeedback(.impact(weight: .medium), trigger: impression) { _, inked in inked }
        .task(id: "\(useLens)-\(front)") {
            guard useLens else { lens.stop(); ready = false; return }
            #if DEBUG && targetEnvironment(simulator)
            if ["press","pressDemo"].contains(Storage.captureTab ?? ""), let root = Storage.root {
                fixture = try? Data(contentsOf: root.appendingPathComponent("1.jpg"))
                if Storage.captureTab == "pressDemo" {
                    do { try await Task.sleep(for: .seconds(3)); shutter() } catch {}
                }
                return
            }
            #endif
            ready = false
            problem = nil
            let authorized = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled else { return }
            accessDenied = !authorized
            guard authorized else { problem = "Allow camera access, or choose a photo below."; return }
            do {
                try await lens.start(front: front)
                if !Task.isCancelled { ready = true }
            } catch {
                if !Task.isCancelled { problem = "Camera unavailable. You can choose a photo below." }
            }
        }
        .task(id: selected) {
            guard let selected else { return }
            do {
                guard let bytes = try await selected.loadTransferable(type: Data.self) else { throw LocketIssue.photo }
                try Task.checkCancellation()
                let ticket = run
                taking = true
                try await finish(bytes, ticket: ticket)
            } catch {
                if !Task.isCancelled { taking = false; library.message = LocketIssue.photo.localizedDescription }
            }
            if !Task.isCancelled { self.selected = nil }
        }
        .onDisappear { run = UUID(); lens.stop(); taking = false; contact = false; impression = lockedPhoto != nil }
    }

    private func reset() {
        run = UUID()
        lockedPhoto = nil
        contact = false
        impression = false
        taking = false
    }

    private func shutter() {
        guard !taking, lockedPhoto == nil, ready || fixture != nil else { return }
        taking = true
        let ticket = run
        Task { @MainActor in
            do {
                let data: Data
                if let fixture { data = fixture } else { data = try await lens.shoot() }
                try await finish(data, ticket: ticket)
            } catch {
                if ticket == run { taking = false; library.message = "Couldn’t take that photo. Try again." }
            }
        }
    }

    @MainActor private func finish(_ bytes: Data, ticket: UUID) async throws {
        let square = try await Task.detached { try stampPhoto(bytes) }.value
        guard ticket == run, !Task.isCancelled else { return }
        lockedPhoto = square
        try await Task.sleep(for: .milliseconds(45))
        guard ticket == run else { return }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) { contact = true }
        try await Task.sleep(for: .milliseconds(150))
        guard ticket == run else { return }
        withAnimation(.easeOut(duration: 0.12)) { impression = true }
        try await Task.sleep(for: .milliseconds(95))
        guard ticket == run else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.77)) { contact = false }
        taking = false
    }
}
