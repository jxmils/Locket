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
        #if DEBUG && targetEnvironment(simulator)
        .task { if Storage.captureTab == "comments", !page.book.mine { comments = true } }
        #endif
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
