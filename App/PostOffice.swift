import SwiftUI

/// Enamel rangefinder used both as the Postbox shortcut and the moving press.
struct VintageCamera: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 100, size.height / 76)
            context.translateBy(x: (size.width - 100*scale)/2, y: (size.height - 76*scale)/2)
            context.scaleBy(x: scale, y: scale)
            let brass = Color(red: 0.79, green: 0.64, blue: 0.38)
            func panel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: Color) {
                let shape = Path(roundedRect: CGRect(x:x,y:y,width:w,height:h), cornerRadius:r)
                context.fill(shape, with: .color(color))
                context.stroke(shape, with: .color(Paper.ink), lineWidth:1.4)
            }
            func lens(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ color: Color) {
                let shape = Path(ellipseIn: CGRect(x:x,y:y,width:d,height:d))
                context.fill(shape, with:.color(color))
                context.stroke(shape, with:.color(Paper.ink), lineWidth:1.2)
            }
            panel(12,14,14,8,2,Paper.red)
            panel(56,8,25,14,3,brass)
            panel(4,19,92,52,6,Paper.stock)
            panel(5,34,90,29,2,Paper.board)
            panel(64,13,11,6,1,Paper.ink)
            panel(13,24,13,6,1,brass)
            for x in stride(from: 9, through: 24, by: 3) {
                panel(CGFloat(x),39,1,17,0,brass.opacity(0.55))
            }
            lens(34,24,43,brass); lens(39,29,33,Paper.stock)
            lens(43,33,25,Paper.ink); lens(48,38,15,Paper.board)
            lens(50,39,5,Paper.stock)
            lens(83,25,4,Paper.red)
        }
        .accessibilityHidden(true)
    }
}

struct PostalImprint: View {
    let day: String
    var body: some View {
        GeometryReader { g in
            let d = min(g.size.height, g.size.width * 0.59)
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    var lines = Path()
                    for row in -1...1 {
                        let y = size.height / 2 + CGFloat(row) * d * 0.12
                        lines.move(to: CGPoint(x: d * 0.91, y: y))
                        lines.addCurve(to: CGPoint(x: size.width, y: y), control1: CGPoint(x: d * 1.15, y: y-d*0.22),
                                       control2: CGPoint(x: size.width-d*0.21, y: y+d*0.20))
                    }
                    ctx.stroke(lines, with: .color(Paper.red), lineWidth: 1.5)
                }
                ZStack {
                    Circle().strokeBorder(lineWidth: 1.6)
                    Circle().inset(by: 3).stroke(lineWidth: 0.7)
                    VStack(spacing: 2) {
                        Text("POST").font(.system(size: d * 0.16, weight: .heavy, design: .serif))
                        Text(day).font(.system(size: d * 0.105, weight: .bold, design: .monospaced))
                    }
                }.frame(width: d, height: d)
            }.foregroundStyle(Paper.red)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct StampPress: View {
    let image: UIImage
    let day: String
    let commit: () async -> Bool
    let done: () -> Void
    let chooseAgain: () -> Void
    @State private var travel: CGFloat = 0
    @State private var working = false
    @State private var printed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contact = false

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                let travelLimit = h * 0.24
                let cameraWidth = min(115, w * 0.31)
                let plateWidth = w * 0.78
                let plateHeight = plateWidth / 1.26
                let x = w * 0.68
                let dockY = h * 0.14
                ZStack {
                    Paper.board
                    Rectangle().inset(by: 8).strokeBorder(Paper.stock.opacity(0.40),
                        style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
                    ZStack {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: plateWidth, height: plateHeight).clipped()
                            .opacity(contact ? 0 : 1)
                        StampArt(image: image, ratio: 1.26, inscription: day)
                            .opacity(contact ? 1 : 0)
                    }
                    .frame(width: plateWidth, height: plateHeight)
                    .shadow(color: .black.opacity(0.34), radius: contact ? 1 : 3, y: contact ? 1 : 4)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (printed ? -3 : -1)))
                    .position(x: w * 0.50, y: h * 0.59)

                    PostalImprint(day: day).frame(width: w * 0.31, height: w * 0.17)
                        .rotationEffect(.degrees(-9))
                        .position(x: x + w * 0.045, y: dockY + travelLimit)
                        .opacity(contact ? 1 : 0)

                    VintageCamera().frame(width: cameraWidth, height: cameraWidth * 0.76)
                        .shadow(color: .black.opacity(0.35), radius: 1 + 5 * (1 - travel), y: 2 + 6 * (1 - travel))
                        .scaleEffect(reduceMotion ? 1 : 1 - 0.045 * travel, anchor: .bottom)
                        .contentShape(Rectangle())
                        .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                            .onChanged { value in
                                guard !working else { return }
                                travel = min(1, max(0, value.translation.height / travelLimit))
                            }.onEnded { value in
                                guard !working else { return }
                                if value.translation.height >= travelLimit * 0.7 { press() }
                                else { withAnimation(motion(.easeOut(duration: 0.2))) { travel = 0 } }
                            })
                        .position(x: x, y: dockY + (reduceMotion ? 0 : travel * travelLimit))
                }
                .clipped()
            }
            .aspectRatio(1.03, contentMode: .fit)
            .accessibilityHidden(true)
            .sensoryFeedback(.impact(weight: .medium), trigger: contact) { _, down in down }
            Text(working ? (printed ? "Stamped and filed." : "Posting your stamp…")
                 : (travel >= 0.7 ? "Let go to stamp it." : "Pull the camera down onto your photo."))
                .font(.system(.body, design: .serif))
            HStack {
                Button("Choose again", action: chooseAgain).disabled(working)
                Spacer()
                Button(action: press) { Label("Press stamp", systemImage: "seal") }
                    .font(.headline).disabled(working)
                    .accessibilityHint("Posts this photo in your stamp book for today.")
            }.frame(minHeight: 44)
        }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard Storage.captureTab == "pressDemo" else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                withAnimation(.easeInOut(duration: 0.65)) { travel = 0.84 }
                try await Task.sleep(for: .milliseconds(680))
                press()
            } catch {}
        }
        #endif
    }

    private func motion(_ animation: Animation) -> Animation? { reduceMotion ? nil : animation }

    private func press() {
        guard !working else { return }
        working = true
        Task { @MainActor in
            withAnimation(motion(.easeIn(duration: 0.13))) { travel = 1 }
            try? await Task.sleep(for: .milliseconds(135))
            withAnimation(motion(.easeOut(duration: 0.15))) { contact = true }
            let saved = await commit()
            if saved {
                withAnimation(motion(.spring(response: 0.38, dampingFraction: 0.82))) {
                    printed = true
                    travel = 0
                }
                try? await Task.sleep(for: .milliseconds(760))
                done()
            } else {
                withAnimation(motion(.easeOut(duration: 0.22))) { contact = false; travel = 0 }
                working = false
            }
        }
    }
}

struct StampActions: View {
    let page: Shelf.Page
    @EnvironmentObject private var library: Library
    @State private var comments = false

    var body: some View {
        let notes = library.shelf.replies(to: page)
        let likes = notes.filter { $0.message.action == "like" }
        let liked = likes.contains { $0.book.mine }
        HStack(spacing: 22) {
            Button {
                Task { _ = await library.act(.like, on: page, remove: liked) }
            } label: {
                Label("\(likes.count)", systemImage: liked ? "heart.fill" : "heart")
                    .foregroundStyle(liked ? Paper.red : Paper.ink)
            }.accessibilityLabel(liked ? "Unlike stamp" : "Like stamp").accessibilityValue("\(likes.count) likes")
            Button { comments = true } label: {
                Label("\(notes.filter { $0.message.action == "comment" }.count)", systemImage: "text.bubble")
            }.accessibilityLabel("Comments")
            Spacer()
            if !page.book.mine {
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    let pinned = library.shelf.own.map { book in
                        library.shelf.pins(in: book, on: time.date).contains { $0.id == page.id }
                    } ?? false
                    Button {
                        Task { _ = await library.act(.pin, on: page, remove: pinned) }
                    } label: {
                        Label(pinned ? "Pinned" : "Pin for today", systemImage: pinned ? "pin.fill" : "pin")
                    }
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(PostActionStyle()).disabled(library.saving)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: $comments) { CommentSheet(page: page) }
    }
}

private struct PostActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).opacity(configuration.isPressed ? 0.55 : 1)
    }
}

private struct CommentSheet: View {
    let page: Shelf.Page
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var requestID = UUID().uuidString

    var body: some View {
        let source = library.shelf.books.first { $0.id == page.book.id }
        let current = source.flatMap { book in book.stamps.first(where: { $0.id == page.stamp.id }).map { Shelf.Page(book: book, stamp: $0) } }
        VStack(alignment: .leading, spacing: 12) {
            HStack { PageTitle(title: "Comments"); Button("Done") { dismiss() } }
            if let current {
                let notes = library.shelf.replies(to: current).filter { $0.message.action == "comment" }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if notes.isEmpty { Text("No comments yet.").foregroundStyle(.secondary) }
                        ForEach(notes) { note in
                            HStack(alignment: .top, spacing: 8) {
                                BookPortrait(book: note.book, size: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.book.author).font(.headline)
                                    Text(note.message.text)
                                }
                                Spacer()
                                if note.book.mine {
                                    Button(role: .destructive) {
                                        Task { _ = await library.act(.comment, on: current,
                                            id: String(note.activity.id.dropFirst("comment-".count)), remove: true) }
                                    } label: { Image(systemName: "trash") }.accessibilityLabel("Delete comment")
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if current.book.discussionKey != nil, library.shelf.own != nil {
                    HStack {
                        TextField("Leave a comment", text: $draft, axis: .vertical).lineLimit(1...4)
                            .onChange(of: draft) { _, value in if value.count > 500 { draft = String(value.prefix(500)) } }
                        Button("Send") {
                            Task {
                                if await library.act(.comment, on: current, text: draft, id: requestID) {
                                    draft = ""; requestID = UUID().uuidString
                                }
                            }
                        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.saving)
                    }.padding(12).background(Paper.stock).disabled(library.saving)
                    Text("Visible to mutual friends who can open this stamp.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Share books with each other to join the conversation.").font(.subheadline)
                }
            } else { Text("This stamp is no longer available.") }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Paper.page).presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}
