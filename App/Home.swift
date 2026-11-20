import PhotosUI
import SwiftUI
import AVFoundation

private enum SectionTab: String, Hashable { case today, postbox, books }

struct Home: View {
    @EnvironmentObject private var library: Library
    @State private var tab: SectionTab = .postbox
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if let tabName = Storage.captureTab, let selected = SectionTab(rawValue: tabName) {
            _tab = State(initialValue: selected)
        }
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            Postbox { tab = .today }.tabItem { Label("Postbox", systemImage: "envelope") }.tag(SectionTab.postbox)
            Today().tabItem { Label("Today", systemImage: "camera") }.tag(SectionTab.today)
            Books().tabItem { Label("Stamp books", systemImage: "books.vertical") }.tag(SectionTab.books)
        }
        .tint(Paper.ink)
        .preferredColorScheme(.light)
        .onOpenURL { url in if url.scheme == "locketstamps" { tab = url.host == "today" ? .today : .postbox } }
        .alert("Stampnote", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("OK") { library.message = nil }
        } message: { Text(library.message ?? "") }
    }
}

private struct Masthead: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Stampnote").font(.system(size: 26, weight: .semibold, design: .serif)).tracking(-1.2)
            Spacer()
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                .font(.caption2.monospaced().weight(.bold))
        }
        .padding(.bottom, 10).overlay(alignment: .bottom) { Rectangle().frame(height: 1) }
    }
}

struct PageTitle: View {
    var title: String
    var body: some View {
        Text(title).font(.system(size: 43, weight: .regular, design: .serif)).tracking(-2)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

struct PaperPage<Content: View>: View {
    @EnvironmentObject private var library: Library
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { Masthead(); content() }
                .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Paper.page.ignoresSafeArea())
        .foregroundStyle(Paper.ink)
        .refreshable { await library.refresh() }
    }
}

private struct PrintMount: View {
    var image: UIImage?
    var caption: String
    var body: some View {
        ZStack {
            Paper.board
            Canvas { context, size in
                let inset: CGFloat = 8
                context.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)),
                               with: .color(Paper.stock.opacity(0.4)), style: StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
            }.accessibilityHidden(true)
            StampArt(image: image, ratio: 1.26, inscription: caption)
                .shadow(color: .black.opacity(0.32), radius: 2, y: 3)
                .rotationEffect(.degrees(-3))
                .padding(.horizontal, 30)
            // A postal cancellation crosses the edge of the print onto its mount.
            Canvas { context, size in
                let origin = CGPoint(x: size.width * 0.83, y: size.height * 0.24)
                let radius = size.width * 0.088
                var mark = Path()
                for scale in [1.0, 0.85] {
                    let r = radius * scale
                    mark.addEllipse(in: CGRect(x: origin.x-r, y: origin.y-r, width: 2*r, height: 2*r))
                }
                for row in -1...1 {
                    let y = origin.y + CGFloat(row) * 6
                    mark.move(to: CGPoint(x: origin.x - radius * 0.3, y: y))
                    mark.addCurve(to: CGPoint(x: size.width + 1, y: y - 1),
                                  control1: CGPoint(x: origin.x + radius * 0.5, y: y - 9),
                                  control2: CGPoint(x: size.width - 10, y: y + 5))
                }
                context.stroke(mark, with: .color(Paper.ink.opacity(0.67)), lineWidth: 1.4)
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .aspectRatio(1.03, contentMode: .fit)
        .clipped()
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(14)
            .background(Paper.ink.opacity(configuration.isPressed ? 0.76 : 1), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct Today: View {
    @EnvironmentObject private var library: Library
    @State private var name = ""
    @State private var draft: Data?
    @State private var picker: PhotosPickerItem?
    @State private var camera = false

    var body: some View {
        PaperPage {
            PageTitle(title: library.shelf.own == nil ? "Your first stamp" : "Today’s stamp")
            if let book = library.shelf.own {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    let today = book.day(timeline.date)
                    VStack(alignment: .leading, spacing: 16) {
                        if let issued = book.stamps.first(where: { $0.day == today }) {
                            PrintMount(image: issued.image(small: false), caption: issued.dateLabel)
                            HStack(spacing: 10) {
                                BookPortrait(book: book)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.author).font(.headline)
                                    Text("Filed in your book").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Paper.board)
                            }
                        } else {
                            PrintMount(image: draft.flatMap { UIImage(data: $0) }, caption: today)
                            if let draft {
                                Button(library.saving ? "Saving…" : "Save today’s stamp") {
                                    Task { if await library.publish(draft) { self.draft = nil } }
                                }.buttonStyle(PrimaryButton()).disabled(library.saving)
                                Button("Choose again") { self.draft = nil }.disabled(library.saving)
                            } else {
                                Text("One photo for \(book.author)’s book today.").font(.system(.title3, design: .serif))
                                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                    Button { Task { await showCamera() } } label: { Label("Take a photo", systemImage: "camera") }
                                        .buttonStyle(PrimaryButton())
                                }
                                PhotosPicker(selection: $picker, matching: .images) {
                                    Label("Choose a photo", systemImage: "photo.on.rectangle").padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
            } else {
                PrintMount(image: nil, caption: "One photo a day").frame(maxWidth: 300).frame(maxWidth: .infinity)
                Text("Whose stamp book is this?").font(.system(.title2, design: .serif))
                TextField("Your first name", text: $name).textContentType(.givenName).padding(14)
                    .background(Paper.stock, in: RoundedRectangle(cornerRadius: 10))
                Button(library.saving ? "Opening…" : "Start my stamp book") { Task { await library.create(name) } }
                    .buttonStyle(PrimaryButton()).disabled(library.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Your book lives in your iCloud. Invite friends whenever you’re ready.").font(.footnote)
            }
        }
        .task(id: picker) {
            guard let picker else { return }
            do {
                guard let data = try await picker.loadTransferable(type: Data.self) else { throw LocketIssue.photo }
                let small = try await Task.detached { try Storage.bytes(data, limit: 1600) }.value
                guard !Task.isCancelled else { return }
                draft = small
            } catch { if !Task.isCancelled { library.message = LocketIssue.photo.localizedDescription } }
            self.picker = nil
        }
        .sheet(isPresented: $camera) { Camera { data in camera = false; if let data { draft = data } } }

    }

    private func showCamera() async {
        if await AVCaptureDevice.requestAccess(for: .video) { camera = true }
        else { library.message = "Allow camera access in Settings, or choose a photo from your library." }
    }


}

private struct BookPortrait: View {
    let book: Book
    var size: CGFloat = 44
    var body: some View {
        Group {
            if let data = book.portrait, let photo = UIImage(data: data) {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                let initials = book.author.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
                Text(String(initials).uppercased()).font(.system(.headline, design: .serif))
                    .foregroundStyle(Paper.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Paper.lining)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay { Circle().strokeBorder(Paper.ink.opacity(0.15)) }
        .accessibilityHidden(true)
    }
}

private struct StampPager: View {
    let pages: [Shelf.Page]
    @Binding var selected: String?

    var body: some View {
        if let page = pages.first(where: { $0.id == selected }) ?? pages.first {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages) { item in
                            PrintMount(image: item.stamp.image(small: false), caption: item.stamp.dateLabel)
                                .frame(width: geometry.size.width)
                            .id(item.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollIndicators(.hidden).scrollTargetBehavior(.paging).scrollPosition(id: $selected)
            }
            .aspectRatio(1.03, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stamp from \(page.book.author), \(page.stamp.dateLabel)")
            .accessibilityValue("\((pages.firstIndex { $0.id == page.id } ?? 0) + 1) of \(pages.count)")
            .accessibilityAdjustableAction { direction in
                let position = pages.firstIndex { $0.id == page.id } ?? 0
                let step = direction == .increment ? 1 : -1
                selected = pages[max(0, min(pages.count - 1, position + step))].id
            }
            HStack {
                BookPortrait(book: page.book, size: 36)
                Text("From \(page.book.author)").font(.system(.title3, design: .serif)).italic()
                Spacer()
                if pages.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack")
                        Text("\((pages.firstIndex { $0.id == page.id } ?? 0) + 1) / \(pages.count)")
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct OpenBook: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    @State private var selected: String?

    init(page: Shelf.Page) {
        bookID = page.book.id
        _selected = State(initialValue: page.id)
    }

    var body: some View {
        PaperPage {
            HStack {
                PageTitle(title: library.shelf.books.first { $0.id == bookID }?.author ?? "Stamp book")
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Close book")
            }
            if let book = library.shelf.books.first(where: { $0.id == bookID }) {
                StampPager(pages: book.stamps.map { Shelf.Page(book: book, stamp: $0) }, selected: $selected)
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct Postbox: View {
    let openToday: () -> Void
    @EnvironmentObject private var library: Library
    @State private var selected: String?
    var body: some View {
        let mail = library.shelf.mail
        PaperPage {
            HStack(alignment: .center) {
                PageTitle(title: "Postbox")
                if library.shelf.friends.contains(where: { !$0.stamps.isEmpty }) {
                    Menu {
                        ForEach(library.shelf.friends.filter { !$0.stamps.isEmpty }) { friend in
                            Button(friend.author) { selected = mail.first { $0.book.id == friend.id }?.id }
                        }
                    } label: {
                        Label("Senders", systemImage: "person.2").font(.subheadline.weight(.medium))
                            .fixedSize().padding(.vertical, 12)
                    }
                }
            }
            if !mail.isEmpty {
                StampPager(pages: mail, selected: $selected)
            } else {
                ZStack {
                    Paper.board
                    Image(systemName: "envelope.open").font(.system(size: 82, weight: .ultraLight))
                        .foregroundStyle(Paper.stock).rotationEffect(.degrees(-6))
                }.aspectRatio(1.6, contentMode: .fit).accessibilityHidden(true)
                Text("No mail yet").font(.system(.title2, design: .serif))
                Text("Open a friend’s stamp book invitation to see their photos here.").foregroundStyle(.secondary)
                if library.shelf.own == nil {
                    Button("Start my stamp book", action: openToday).buttonStyle(PrimaryButton())
                }
            }
        }
    }
}

struct Books: View {
    @EnvironmentObject private var library: Library
    @State private var selected: String?
    @State private var detail: Shelf.Page?
    @State private var portraitChoice: PhotosPickerItem?
    @State private var choosingPortrait = false
    @State private var invite: Invitation?
    @State private var inviting = false
    var body: some View {
        let books = [library.shelf.own].compactMap { $0 } + library.shelf.friends
        let book = books.first { $0.id == selected } ?? books.first
        PaperPage {
            PageTitle(title: "Stamp books")
            if let book {
                HStack(spacing: 12) {
                    BookPortrait(book: book, size: 52)
                    Menu {
                        ForEach(books) { b in Button(b.mine ? "My stamp book" : b.author) { selected = b.id } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(book.author).font(.title3.bold()); Image(systemName: "chevron.down").font(.caption2) }
                            Text("\(book.stamps.count) \(book.stamps.count == 1 ? "stamp" : "stamps")").font(.caption)
                        }
                    }
                    Spacer()
                    if book.mine {
                        Menu {
                            Button { Task { await share(book) } } label: {
                                Label("Share stamp book", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(book.portrait == nil ? "Add profile photo" : "Change profile photo") { choosingPortrait = true }
                            if book.portrait != nil {
                                Button("Remove profile photo", role: .destructive) {
                                    Task { await library.setPortrait(nil, for: book) }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("Book options").disabled(library.saving || inviting)
                    }
                }
                .padding(.vertical, 8).overlay(alignment: .bottom) { Divider() }
                if book.stamps.isEmpty { Text("The first stamp will go here.").foregroundStyle(.secondary) }
                let months = Dictionary(grouping: book.stamps) { String($0.day.prefix(7)) }
                ForEach(months.keys.sorted(by: >), id: \.self) { month in
                    let pages = months[month] ?? []
                    Text(pages.first?.monthLabel ?? month).font(.headline.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        ForEach(pages) { stamp in
                            Button { detail = Shelf.Page(book: book, stamp: stamp) } label: {
                                StampArt(image: stamp.image(), ratio: 1.16, inscription: stamp.dateLabel)
                                    .shadow(color: .black.opacity(0.24), radius: 1.3, y: 2)
                            }.buttonStyle(.plain).accessibilityLabel("Open stamp, \(stamp.dateLabel)")
                        }
                    }
                    .padding(14).background(Paper.board)
                }
            } else { Text("Start your first book on the Today tab.").font(.system(.title2, design: .serif)) }
        }
        .photosPicker(isPresented: $choosingPortrait, selection: $portraitChoice, matching: .images)
        .task(id: portraitChoice) {
            guard let portraitChoice, let owner = library.shelf.own else { return }
            do {
                guard let data = try await portraitChoice.loadTransferable(type: Data.self) else { throw LocketIssue.photo }
                let jpeg = try await Task.detached { try Storage.bytes(data, limit: 256) }.value
                try Task.checkCancellation()
                await library.setPortrait(jpeg, for: owner)
            } catch { if !Task.isCancelled { library.message = error.localizedDescription } }
            if !Task.isCancelled { self.portraitChoice = nil }
        }
        .sheet(item: $detail) { page in OpenBook(page: page) }
        .sheet(item: $invite) { invitation in
            Sharing(invitation: invitation, finished: { Task { await library.refresh() } }, failed: { library.message = $0 })
        }
    }

    private func share(_ book: Book) async {
        inviting = true
        defer { inviting = false }
        do { invite = Invitation(share: try await library.cloud.invitation(author: book.author), container: library.cloud.container) }
        catch { library.message = error.localizedDescription }
    }
}
