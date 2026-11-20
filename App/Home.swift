import PhotosUI
import SwiftUI
import AVFoundation

private enum SectionTab: String, Hashable { case today, postbox, books }

struct Home: View {
    @EnvironmentObject private var library: Library
    @State private var tab: SectionTab = .today
    init() {
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

struct PageTitle: View {
    var title: String
    var body: some View { Text(title).font(.system(size: 44, weight: .medium, design: .serif)).tracking(-2).foregroundStyle(Paper.ink)
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader) }
}

struct PaperPage<Content: View>: View {
    @EnvironmentObject private var library: Library
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20, content: content)
                .padding(.horizontal, 24).padding(.vertical, 24).frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .background(Paper.page.ignoresSafeArea())
        .foregroundStyle(Paper.ink)
        .refreshable { await library.refresh() }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(15)
            .background(Paper.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Paper.stock)
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
            PageTitle(title: "Today’s stamp")
            if let book = library.shelf.own {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    let today = book.day(timeline.date)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(today).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Paper.red)
                        if let issued = book.stamps.first(where: { $0.day == today }) {
                            StampArt(image: issued.image(small: false)).shadow(color: .black.opacity(0.13), radius: 5, y: 4)
                            Label("Filed in your stamp book", systemImage: "checkmark.seal")
                                .font(.headline)
                            Text("A new page opens tomorrow.").foregroundStyle(.secondary)
                        } else {
                            StampArt(image: draft.flatMap { UIImage(data: $0) })
                                .shadow(color: .black.opacity(0.13), radius: 5, y: 4)
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
                    Label(inviting ? "Opening invitation…" : "Invite to my stamp book", systemImage: "person.crop.circle.badge.plus")
                }.disabled(inviting)
                Text("Invited friends can see past and future stamps. They can invite you to their book too.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                StampArt(image: nil).frame(maxWidth: 190).rotationEffect(.degrees(-5)).padding(.vertical, 8)
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
    var body: some View {
        Group {
            if let data = book.portrait, let photo = UIImage(data: data) {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                let initials = book.author.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
                Text(String(initials).uppercased()).font(.system(.headline, design: .serif))
                    .foregroundStyle(Paper.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Paper.ink.opacity(0.09))
            }
        }
        .frame(width: 44, height: 44).clipShape(Circle())
        .overlay { Circle().strokeBorder(Paper.ink.opacity(0.15)) }
        .accessibilityHidden(true)
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
                HStack {
                    BookPortrait(book: page.book)
                    Text(page.book.author).font(.system(.title2, design: .serif))
                    Spacer()
                    Text(page.stamp.dateLabel).font(.system(.caption, design: .monospaced))
                }
                Button {
                    selected = Shelf.nextID(page.id, in: mail.map(\.id))
                } label: {
                    StampArt(image: page.stamp.image(small: false)).rotationEffect(.degrees(-1.5))
                        .shadow(color: .black.opacity(0.15), radius: 5, y: 4)
                }.buttonStyle(.plain).accessibilityLabel("Stamp from \(page.book.author), \(page.stamp.dateLabel)")
                    .accessibilityHint(mail.count > 1 ? "Shows the next stamp" : "The only stamp in your postbox")
                if mail.count > 1 {
                    Button("Next stamp  →") { selected = Shelf.nextID(page.id, in: mail.map(\.id)) }
                        .buttonStyle(PrimaryButton())
                    Text("\((mail.firstIndex { $0.id == page.id } ?? 0) + 1) of \(mail.count)").font(.caption.monospacedDigit())
                }
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
                    BookPortrait(book: book)
                    Menu {
                    ForEach(books) { b in Button(b.mine ? "My stamp book" : b.author) { selected = b.id } }
                } label: { Label(book.mine ? "My stamp book" : book.author, systemImage: "books.vertical").font(.headline)
                    Image(systemName: "chevron.down").font(.caption) }
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
                if book.stamps.isEmpty { Text("The first stamp will go here.").foregroundStyle(.secondary) }
                let months = Dictionary(grouping: book.stamps) { String($0.day.prefix(7)) }
                ForEach(months.keys.sorted(by: >), id: \.self) { month in
                    Text(month).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Paper.red)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(months[month] ?? []) { stamp in
                            Button { detail = Shelf.Page(book: book, stamp: stamp) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    StampArt(image: stamp.image()).shadow(color: .black.opacity(0.1), radius: 2, y: 2)
                                    Text(stamp.dateLabel).font(.caption.monospacedDigit())
                                }
                            }.buttonStyle(.plain)
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
        .sheet(item: $detail) { page in
            PaperPage {
                Button("Done") { detail = nil }
                PageTitle(title: page.book.author)
                if let stamp = library.shelf.books.first(where: { $0.id == page.book.id })?.stamps.first(where: { $0.id == page.stamp.id }) {
                    StampArt(image: stamp.image(small: false))
                    Text(stamp.dateLabel).font(.system(.subheadline, design: .monospaced))
                }
            }.presentationDragIndicator(.visible)
        }
    }
}
