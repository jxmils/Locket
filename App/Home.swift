import PhotosUI
import SwiftUI
import AVFoundation

private enum SectionTab: String, Hashable { case today, postbox, books }

struct Home: View {
    @EnvironmentObject private var library: Library
    @State private var tab: SectionTab = .today
    init() {
        _tab = State(initialValue: Storage.read().mail.isEmpty ? .today : .postbox)
        #if DEBUG && targetEnvironment(simulator)
        if let tabName = Storage.captureTab, let selected = SectionTab(rawValue: tabName) {
            _tab = State(initialValue: selected)
        }
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            Today().tabItem { Label("Today", systemImage: "camera") }.tag(SectionTab.today)
            Postbox().tabItem { Label("Postbox", systemImage: "tray") }.tag(SectionTab.postbox)
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
            Text("stampnote").font(.system(size: 32, weight: .black, design: .serif)).italic().tracking(-2)
            Spacer()
            Image(systemName: "seal.fill").foregroundStyle(Paper.red).accessibilityHidden(true)
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                .font(.caption2.monospaced().weight(.bold))
        }
        .padding(.bottom, 10).overlay(alignment: .bottom) { Rectangle().frame(height: 1) }
    }
}

struct PageTitle: View {
    var title: String
    var body: some View {
        Text(title).font(.system(.largeTitle, design: .default, weight: .heavy)).tracking(-1.7)
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
        VStack(spacing: 0) {
            StampArt(image: image, ratio: 1.08)
                .rotationEffect(.degrees(-3))
                .shadow(color: .black.opacity(0.22), radius: 3, y: 3)
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 16)
            HStack {
                Image(systemName: "seal.fill")
                Text(caption.uppercased()).font(.caption2.monospaced().weight(.bold))
                Spacer()
                Image(systemName: "water.waves").imageScale(.large)
            }.foregroundStyle(Paper.plum).padding(.horizontal, 18).padding(.bottom, 12)
        }
        .background {
            ZStack {
                Paper.lilac
                Canvas { context, size in
                    for index in 0..<12 {
                        let x = size.width - CGFloat(index * 10)
                        var line = Path()
                        line.move(to: CGPoint(x: x + 70, y: 0))
                        line.addLine(to: CGPoint(x: x - 80, y: size.height))
                        context.stroke(line, with: .color(Paper.plum.opacity(0.09)), lineWidth: 1)
                    }
                }.accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
    @State private var invite: Invitation?
    @State private var inviting = false

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
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Paper.plum)
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
                Divider()
                Button { Task { await share(book) } } label: {
                    Label(inviting ? "Opening invitation…" : "Invite a friend", systemImage: "person.badge.plus")
                }.buttonStyle(PrimaryButton()).disabled(inviting)
                Text("Invited friends can see past and future stamps. They can invite you to their book too.")
                    .font(.footnote).foregroundStyle(.secondary)
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
        .sheet(item: $invite) { invitation in
            Sharing(invitation: invitation, finished: { Task { await library.refresh() } }, failed: { library.message = $0 })
        }
    }

    private func showCamera() async {
        if await AVCaptureDevice.requestAccess(for: .video) { camera = true }
        else { library.message = "Allow camera access in Settings, or choose a photo from your library." }
    }

    private func share(_ book: Book) async {
        inviting = true
        defer { inviting = false }
        do { invite = Invitation(share: try await library.cloud.invitation(author: book.author), container: library.cloud.container) }
        catch { library.message = error.localizedDescription }
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
                    .background(Paper.melon)
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
                            ZStack(alignment: .bottomLeading) {
                                StampArt(image: item.stamp.image(small: false), ratio: 0.94)
                                HStack(spacing: 8) {
                                    BookPortrait(book: item.book, size: 27)
                                    Text(item.book.author).font(.subheadline.weight(.bold))
                                }
                                .padding(6).padding(.trailing, 7).background(.white, in: Capsule()).padding(22)
                            }
                            .frame(width: geometry.size.width - 8)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
                            .frame(width: geometry.size.width)
                            .id(item.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollIndicators(.hidden).scrollTargetBehavior(.paging).scrollPosition(id: $selected)
            }
            .aspectRatio(0.94, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stamp from \(page.book.author), \(page.stamp.dateLabel)")
            .accessibilityValue("\((pages.firstIndex { $0.id == page.id } ?? 0) + 1) of \(pages.count)")
            .accessibilityAdjustableAction { direction in
                let position = pages.firstIndex { $0.id == page.id } ?? 0
                let step = direction == .increment ? 1 : -1
                selected = pages[max(0, min(pages.count - 1, position + step))].id
            }
            HStack {
                Text(page.stamp.dateLabel).font(.subheadline.weight(.semibold))
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
    @EnvironmentObject private var library: Library
    @State private var selected: String?
    var body: some View {
        let mail = library.shelf.mail
        PaperPage {
            PageTitle(title: "Postbox")
            if let page = mail.first(where: { $0.id == selected }) ?? mail.first {
                ScrollView(.horizontal) {
                    HStack(spacing: 15) {
                        ForEach(library.shelf.friends.filter { !$0.stamps.isEmpty }) { friend in
                            Button {
                                selected = mail.first { $0.book.id == friend.id }?.id
                            } label: {
                                VStack(spacing: 5) {
                                    BookPortrait(book: friend).padding(3)
                                        .overlay { Circle().stroke(friend.id == page.book.id ? Paper.red : Color.secondary.opacity(0.2), lineWidth: 2) }
                                    Text(friend.author).font(.caption.weight(.semibold)).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(2)
                }.scrollIndicators(.hidden)
                StampPager(pages: mail, selected: $selected)
            } else {
                Text("Your friends’ stamps will arrive here.").font(.system(.title2, design: .serif))
                Text("Ask a friend to invite you to their stamp book. Open their invitation on this iPhone to add it.").foregroundStyle(.secondary)
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
                            Button(book.portrait == nil ? "Add profile photo" : "Change profile photo") { choosingPortrait = true }
                            if book.portrait != nil {
                                Button("Remove profile photo", role: .destructive) {
                                    Task { await library.setPortrait(nil, for: book) }
                                }
                            }
                        } label: {
                            Image(systemName: "camera").frame(width: 44, height: 44)
                        }.accessibilityLabel("Edit profile photo").disabled(library.saving)
                    }
                }
                .padding(14).background(Paper.melon.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                if book.stamps.isEmpty { Text("The first stamp will go here.").foregroundStyle(.secondary) }
                let months = Dictionary(grouping: book.stamps) { String($0.day.prefix(7)) }
                ForEach(months.keys.sorted(by: >), id: \.self) { month in
                    let pages = months[month] ?? []
                    Text(pages.first?.monthLabel ?? month).font(.headline.bold())
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(0..<2) { column in
                            LazyVStack(spacing: 16) {
                                ForEach(Array(pages.enumerated()).filter { $0.offset % 2 == column }, id: \.element.id) { index, stamp in
                                    Button { detail = Shelf.Page(book: book, stamp: stamp) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            StampArt(image: stamp.image(), ratio: index % 4 == 0 || index % 4 == 3 ? 0.82 : 1.08)
                                                .shadow(color: .black.opacity(0.17), radius: 1.8, y: 2)
                                            Text(stamp.dateLabel).font(.caption.weight(.medium)).padding(.leading, 2)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }.frame(maxWidth: .infinity)
                        }
                    }
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
    }
}
