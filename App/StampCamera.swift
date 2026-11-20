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

private enum StampCut {
    static let widthFraction: CGFloat = 0.91

    /// Match the portrait aspect-fill preview, then cut the photograph inside the paper guide.
    static func expose(_ data: Data) throws -> (viewfinder: UIImage, print: Data) {
        let normalized = try Storage.bytes(data, limit: 2048)
        guard let raw = UIImage(data: normalized)?.cgImage else { throw LocketIssue.photo }
        let width = min(CGFloat(raw.width), CGFloat(raw.height) / StampLayout.heightPerWidth)
        let height = width * StampLayout.heightPerWidth
        let viewport = CGRect(x: (CGFloat(raw.width) - width) / 2, y: (CGFloat(raw.height) - height) / 2,
                              width: width, height: height).integral
        guard let frame = raw.cropping(to: viewport) else { throw LocketIssue.photo }
        let paperWidth = CGFloat(frame.width) * widthFraction
        let margin = paperWidth * StampLayout.photoInset
        let side = floor(paperWidth - 2 * margin)
        let rect = CGRect(x: floor((CGFloat(frame.width) - side) / 2),
                          y: floor((CGFloat(frame.height) - paperWidth * StampLayout.heightPerWidth) / 2 + margin),
                          width: side, height: side)
        guard let print = frame.cropping(to: rect),
              let jpeg = UIImage(cgImage: print).jpegData(compressionQuality: 0.94) else { throw LocketIssue.photo }
        return (UIImage(cgImage: frame), jpeg)
    }
}

private enum PressPosition { case off, raised, down, lifting }

/// A turned wooden grip on a brass cutting plate. The die shares its footprint with the paper.
private struct PostagePress: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let brass = Color(red: 0.70, green: 0.49, blue: 0.25)
            let rim = Color(red: 0.29, green: 0.21, blue: 0.16)
            ZStack {
                PerforatedPaper().fill(rim)
                RoundedRectangle(cornerRadius: w * 0.048)
                    .fill(LinearGradient(colors: [Color(red: 0.94, green: 0.82, blue: 0.62), brass, rim],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(w * 0.016)
                RoundedRectangle(cornerRadius: w * 0.032)
                    .fill(LinearGradient(colors: [Color(red: 0.26, green: 0.38, blue: 0.37),
                                                  Color(red: 0.09, green: 0.17, blue: 0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(w * 0.04)
                RoundedRectangle(cornerRadius: w * 0.024)
                    .strokeBorder(brass.opacity(0.8), lineWidth: 1).padding(w * 0.060)
                ForEach(0..<4) { i in
                    Circle().fill(brass)
                        .overlay { Capsule().fill(rim).frame(width: w * 0.017, height: 1).rotationEffect(.degrees(-28)) }
                        .frame(width: w * 0.032, height: w * 0.032)
                        .position(x: w * (i.isMultiple(of: 2) ? 0.094 : 0.906), y: h * (i < 2 ? 0.09 : 0.91))
                }
                Ellipse().fill(.black.opacity(0.32)).frame(width: w * 0.40, height: w * 0.13)
                    .blur(radius: w * 0.014).offset(x: w * 0.025, y: h * 0.082)
                Ellipse().fill(brass.gradient).frame(width: w * 0.34, height: w * 0.12).offset(y: h * 0.065)
                Path { p in
                    p.move(to: CGPoint(x: 0.43*w, y: 0.57*h))
                    p.addQuadCurve(to: CGPoint(x: 0.40*w, y: 0.40*h), control: CGPoint(x: 0.47*w, y: 0.43*h))
                    p.addCurve(to: CGPoint(x: 0.34*w, y: 0.29*h), control1: CGPoint(x: 0.35*w, y: 0.37*h), control2: CGPoint(x: 0.32*w, y: 0.34*h))
                    p.addCurve(to: CGPoint(x: 0.66*w, y: 0.29*h), control1: CGPoint(x: 0.37*w, y: 0.20*h), control2: CGPoint(x: 0.63*w, y: 0.20*h))
                    p.addCurve(to: CGPoint(x: 0.60*w, y: 0.40*h), control1: CGPoint(x: 0.68*w, y: 0.34*h), control2: CGPoint(x: 0.65*w, y: 0.37*h))
                    p.addQuadCurve(to: CGPoint(x: 0.57*w, y: 0.57*h), control: CGPoint(x: 0.53*w, y: 0.43*h))
                    p.addQuadCurve(to: CGPoint(x: 0.43*w, y: 0.57*h), control: CGPoint(x: 0.50*w, y: 0.60*h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.29, green: 0.12, blue: 0.07), location: 0),
                    .init(color: Color(red: 0.73, green: 0.43, blue: 0.24), location: 0.32),
                    .init(color: Color(red: 0.48, green: 0.22, blue: 0.12), location: 0.55),
                    .init(color: Color(red: 0.22, green: 0.10, blue: 0.07), location: 1)
                ], startPoint: .leading, endPoint: .trailing))
            }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
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
    @State private var press: PressPosition = .off
    @State private var exposure: UIImage?
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
            let width = max(1, min(geo.size.width - 20, (geo.size.height - 170) / 1.105, 490))
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today’s stamp").font(.system(.title, design: .serif).italic())
                    Spacer()
                    Text(impression ? "" : date.uppercased())
                        .font(.caption2.monospaced().weight(.medium))
                }.padding(.horizontal, 22).padding(.top, 12)
                Spacer(minLength: 8)
                cutViewfinder(width: width)
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
            if ["press","pressDemo","proof"].contains(Storage.captureTab ?? ""), let root = Storage.root {
                fixture = try? Data(contentsOf: root.appendingPathComponent("1.jpg"))
                if Storage.captureTab != "press" {
                    do {
                        if Storage.captureTab == "pressDemo" {
                            let cue = root.appendingPathComponent("record-shutter")
                            while !FileManager.default.fileExists(atPath: cue.path) {
                                try await Task.sleep(for: .milliseconds(100))
                            }
                        } else {
                            try await Task.sleep(for: .milliseconds(150))
                        }
                        try Task.checkCancellation()
                        shutter()
                    } catch {}
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
        .onDisappear { run = UUID(); lens.stop(); taking = false; press = .off; impression = lockedPhoto != nil }
    }

    @ViewBuilder private var liveSurface: some View {
        if let fixture, let img = UIImage(data: fixture) {
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

    private func cutViewfinder(width: CGFloat) -> some View {
        let height = width * StampLayout.heightPerWidth
        let cut = width * StampCut.widthFraction
        let cutHeight = cut * StampLayout.heightPerWidth
        return ZStack {
            Group {
                if let exposure { Image(uiImage: exposure).resizable().scaledToFill() }
                else { liveSurface }
            }
            .frame(width: width, height: height).clipped()
            .opacity(impression ? 0.12 : 1)

            PerforatedPaper().stroke(Paper.stock.opacity(0.86), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                .frame(width: cut, height: cutHeight)
                .shadow(color: .black.opacity(0.8), radius: 1)
                .opacity(impression ? 0 : 1).allowsHitTesting(false)

            if impression, let lockedPhoto, let picture = UIImage(data: lockedPhoto) {
                PostageFace(date: date) { Image(uiImage: picture).resizable().scaledToFill() }
                    .frame(width: cut, height: cutHeight)
                    .shadow(color: .black.opacity(0.55), radius: 5, y: 4)
                    .transition(.opacity)
            }
            if !reduceMotion && press != .off {
                PostagePress()
                    .frame(width: cut, height: cutHeight)
                    .rotation3DEffect(.degrees(press == .down ? 0 : 38), axis: (x: 1, y: 0, z: 0))
                    .rotationEffect(.degrees(press == .down ? 0 : -8))
                    .shadow(color: .black.opacity(0.58), radius: press == .down ? 2 : 11, y: press == .down ? 2 : 17)
                    .offset(y: press == .down ? 0 : -height * 0.94)
                    .opacity(press == .lifting ? 0 : 1)
                    .transition(.identity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(lockedPhoto == nil ? "Stamp-shaped camera viewfinder" : "Captured photo stamp")
    }

    private func reset() {
        run = UUID()
        lockedPhoto = nil
        press = .off
        exposure = nil
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
        let shot = try await Task.detached { try StampCut.expose(bytes) }.value
        guard ticket == run, !Task.isCancelled else { return }
        exposure = shot.viewfinder
        lockedPhoto = shot.print
        if !reduceMotion {
            press = .raised
            try await Task.sleep(for: .milliseconds(30))
            guard ticket == run else { return }
            withAnimation(.easeIn(duration: 0.17)) { press = .down }
            try await Task.sleep(for: .milliseconds(170))
            guard ticket == run else { return }
        }
        withAnimation(.easeOut(duration: 0.12)) { impression = true }
        if !reduceMotion {
            try await Task.sleep(for: .milliseconds(90))
            guard ticket == run else { return }
            withAnimation(.easeOut(duration: 0.23)) { press = .lifting }
            try await Task.sleep(for: .milliseconds(230))
            guard ticket == run else { return }
        }
        press = .off
        taking = false
    }
}
