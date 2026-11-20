import PhotosUI
import SwiftUI
import AVFoundation

private enum SectionTab: String, Hashable { case today, postbox, books }

struct Home: View {
    @EnvironmentObject private var library: Library
    @State private var tab: SectionTab = .postbox
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ["press","pressDemo","proof","welcome"].contains(Storage.captureTab ?? "") { _tab = State(initialValue: .today) }
        if ["detail","pins","friend"].contains(Storage.captureTab ?? "") { _tab = State(initialValue: .books) }
        if let tabName = Storage.captureTab, let selected = SectionTab(rawValue: tabName) {
            _tab = State(initialValue: selected)
        }
        #endif
    }

    @ViewBuilder var body: some View {
        #if DEBUG && targetEnvironment(simulator)
        if let tab = Storage.captureTab, tab.hasPrefix("widget-"), let page = library.shelf.mail.first {
            let size: CGSize = tab == "widget-small" ? .init(width: 158, height: 158) :
                tab == "widget-medium" ? .init(width: 338, height: 158) : .init(width: 338, height: 354)
            FriendWidgetFace(name: page.book.author, day: page.stamp.dateLabel, image: page.stamp.image(), portrait: page.book.portrait)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Paper.board.ignoresSafeArea()).preferredColorScheme(.light)
        } else { tabs }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Postbox().tabItem { Label("Postbox", image: "TabMail") }.tag(SectionTab.postbox)
            Today(active: tab == .today).tabItem { Label("Today", image: "TabCamera") }.tag(SectionTab.today)
            Books().tabItem { Label("Stamp books", image: "TabAlbum") }.tag(SectionTab.books)
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
    var body: some View {
        Text(title).font(.system(size: 40, weight: .semibold, design: .serif)).tracking(-1.7)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

struct PaperPage<Content: View>: View {
    @EnvironmentObject private var library: Library
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content() }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(Paper.page.ignoresSafeArea())
        .foregroundStyle(Paper.ink)
        .refreshable { await library.refresh() }
    }
}

struct PrintMount: View {
    var image: UIImage?
    var caption: String
    var body: some View {
        StampArt(image: image, inscription: caption)
            .shadow(color: Paper.ink.opacity(0.18), radius: 2.5, y: 2)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
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
    let active: Bool
    @EnvironmentObject private var library: Library
    @State private var name = ""

    var body: some View {
        if let book = library.shelf.own {
            TimelineView(.periodic(from: .now, by: 15)) { time in
                if let issued = book.stamps.first(where: { $0.day == book.day(time.date) }) {
                    PaperPage {
                        PageTitle(title: "Today’s stamp")
                        HStack {
                            BookPortrait(book: book, size: 34)
                            Text(book.author).font(.headline)
                            Spacer()
                            Label("In your book", systemImage: "checkmark").font(.caption)
                        }
                        PrintMount(image: issued.image(small: false), caption: issued.dateLabel)
                        StampActions(page: Shelf.Page(book: book, stamp: issued))
                    }
                } else { StampCamera(book: book, active: active).id(book.id) }
            }
        } else {
            PaperPage {
                VintageCamera().frame(width: 96, height: 78)
                PageTitle(title: "Your first stamp")
                Text("What name goes on your book?").font(.title3)
                TextField("Your first name", text: $name).textContentType(.givenName).padding(14)
                    .background(Paper.stock, in: RoundedRectangle(cornerRadius: 10))
                Button(library.saving ? "Opening…" : "Open my stamp book") { Task { await library.create(name) } }
                    .buttonStyle(PrimaryButton()).disabled(library.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct BookPortrait: View {
    let book: Book
    var size: CGFloat = 44
    var body: some View {
        SenderPortrait(name: book.author, data: book.portrait, size: size)
    }
}

private struct DeckPrint: View {
    let stamp: Stamp
    var body: some View {
        PrintMount(image: stamp.image(small: false), caption: stamp.dateLabel)
    }
}

private struct StampDeck: View {
    let front: Stamp
    let next: Stamp?
    let previous: Stamp?
    let advance: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var departing = false
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { area in
            let width = max(area.size.width, 1)
            let progress = min(abs(offset) / (width * 0.8), 1)
            ZStack {
                if let behind = offset > 0 ? previous : next {
                    DeckPrint(stamp: behind)
                        .scaleEffect(0.96 + 0.04 * progress)
                        .rotationEffect(.degrees(reduceMotion ? 0 : -2 * Double(1 - progress)))
                        .offset(y: 5 * (1 - progress))
                }
                DeckPrint(stamp: front)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset / width) * 13), anchor: .bottom)
                    .offset(x: offset)
            }
            .padding(.horizontal, 7)
            .frame(width: area.size.width, height: area.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .updating($touching) { _, active, _ in active = true }
                .onChanged { value in
                    guard !departing, next != nil else { return }
                    let d = value.translation
                    if abs(d.width) > abs(d.height) || offset != 0 { offset = d.width }
                }
                .onEnded { value in
                    guard !departing, next != nil else { return }
                    let d = value.translation
                    let projected = value.predictedEndTranslation.width
                    if abs(d.width) > abs(d.height),
                       abs(d.width) > width * 0.26 || (abs(d.width) > 14 && abs(projected) > width * 0.50 && d.width * projected > 0) {
                        release(d.width < 0 ? 1 : -1, width: width)
                    } else { settle() }
                })
            .onChange(of: touching) { _, active in
                if !active && !departing && offset != 0 { settle() }
            }
            #if DEBUG && targetEnvironment(simulator)
            .task {
                guard Storage.captureTab == "swipeDemo", next != nil else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                withAnimation(.easeInOut(duration: 0.5)) { offset = -width * 0.32 }
                do { try await Task.sleep(for: .milliseconds(560)) } catch { return }
                release(1, width: width)
            }
            #endif
        }
    }

    private func settle() {
        withAnimation(.spring(duration: 0.32, bounce: 0.16)) { offset = 0 }
    }

    private func release(_ step: Int, width: CGFloat) {
        departing = true
        if reduceMotion { advance(step); return }
        withAnimation(.easeOut(duration: 0.24), completionCriteria: .logicallyComplete) {
            offset = -CGFloat(step) * width * 1.45
        } completion: {
            advance(step)
        }
    }
}

private struct StampPager: View {
    let pages: [Shelf.Page]
    @Binding var selected: String?

    var body: some View {
        if let page = pages.first(where: { $0.id == selected }) ?? pages.first {
            HStack(alignment: .firstTextBaseline) {
                Text("From \(page.book.author)").font(.system(.title2, design: .serif).italic())
                Spacer()
                if pages.count > 1 {
                    Text("\((pages.firstIndex { $0.id == page.id } ?? 0) + 1) / \(pages.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }.padding(.top, 2)
            let index = pages.firstIndex { $0.id == page.id } ?? 0
            let startingSelection = selected
            StampDeck(front: page.stamp,
                      next: pages.count > 1 ? pages[(index + 1) % pages.count].stamp : nil,
                      previous: pages.count > 1 ? pages[(index + pages.count - 1) % pages.count].stamp : nil) { step in
                guard selected == startingSelection else { return }
                selected = pages[(index + step + pages.count) % pages.count].id
            }
            .id(page.id)
            .aspectRatio(0.91, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stamp from \(page.book.author), \(page.stamp.dateLabel)")
            .accessibilityValue("\((pages.firstIndex { $0.id == page.id } ?? 0) + 1) of \(pages.count)")
            .accessibilityAdjustableAction { direction in
                let position = pages.firstIndex { $0.id == page.id } ?? 0
                let step = direction == .increment ? 1 : -1
                selected = pages[(position + step + pages.count) % pages.count].id
            }
            StampActions(page: page).id(page.id)
        }
    }
}

struct OpenBook: View {
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
            HStack(alignment: .firstTextBaseline) {
                PageTitle(title: "Postbox")
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .font(.caption2.monospaced().weight(.semibold)).fixedSize()
            }
            if !mail.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(library.shelf.friends.filter { !$0.stamps.isEmpty }) { friend in
                            Button { selected = mail.first { $0.book.id == friend.id }?.id } label: {
                                VStack(spacing: 5) {
                                    BookPortrait(book: friend, size: 43).padding(3)
                                        .overlay { Circle().strokeBorder((mail.first { $0.id == selected } ?? mail.first)?.book.id == friend.id ? Paper.red : .clear, lineWidth: 1.5) }
                                    if (mail.first { $0.id == selected } ?? mail.first)?.book.id != friend.id {
                                        Text(friend.author).font(.caption).lineLimit(1)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityLabel("Stamps from \(friend.author)")
                        }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.hidden)
                StampPager(pages: mail, selected: $selected)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Paper.lining.opacity(0.54))
                    Image(systemName: "envelope").font(.system(size: 94, weight: .ultraLight))
                        .foregroundStyle(Paper.board).rotationEffect(.degrees(-7))
                }.aspectRatio(1.6, contentMode: .fit).accessibilityHidden(true)
                Text("No mail yet").font(.system(.title2, design: .serif))
                Text("Open a friend’s stamp book invitation to see their photos here.").foregroundStyle(.secondary)

            }
        }
    }
}

struct Books: View {
    @EnvironmentObject private var library: Library
    @State private var selected: String?
    @State private var monthChoice: String?
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
                        ForEach(books) { b in Button(b.mine ? "My stamp book" : b.author) { selected = b.id; monthChoice = nil } }
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
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    let pins = library.shelf.pins(in: book, on: time.date)
                    if !pins.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Pinned today", systemImage: "pin.fill").font(.headline)
                            ScrollView(.horizontal) {
                                HStack(spacing: 12) {
                                    ForEach(pins) { page in
                                        Button { detail = page } label: {
                                            VStack(alignment: .leading) {
                                                StampArt(image: page.stamp.image(), inscription: page.stamp.dateLabel).frame(width: 112)
                                                Text(page.book.author).font(.caption)
                                            }
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                    }
                }
                if book.stamps.isEmpty { Text("The first stamp will go here.").foregroundStyle(.secondary) }
                let months = Dictionary(grouping: book.stamps) { String($0.day.prefix(7)) }
                let monthsInOrder = months.keys.sorted(by: >)
                if let month = monthChoice.flatMap({ months[$0] == nil ? nil : $0 }) ?? monthsInOrder.first,
                   let pages = months[month] {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            if monthsInOrder.count > 1 {
                                Menu {
                                    ForEach(monthsInOrder, id: \.self) { key in
                                        Button(months[key]?.first?.monthLabel ?? key) { monthChoice = key }
                                    }
                                } label: {
                                    Label(pages.first?.monthLabel ?? month, systemImage: "calendar")
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                            } else { Text(pages.first?.monthLabel ?? month) }
                            Spacer()
                            Text("\((monthsInOrder.firstIndex(of: month) ?? 0) + 1) / \(monthsInOrder.count)")
                                .font(.caption2.monospacedDigit())
                        }.font(.subheadline.weight(.semibold))
                        Divider()
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 17) {
                            ForEach(pages) { stamp in
                                Button { detail = Shelf.Page(book: book, stamp: stamp) } label: {
                                    StampArt(image: stamp.image(), inscription: stamp.dateLabel)
                                        .shadow(color: Paper.ink.opacity(0.22), radius: 1.5, y: 2)
                                }.buttonStyle(.plain).accessibilityLabel("Open stamp, \(stamp.dateLabel)")
                            }
                        }
                    }.padding(13)
                    .background {
                        Canvas { context, size in
                            var lines = Path()
                            for x in stride(from: 0, to: size.width, by: 14) {
                                lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height))
                            }
                            for y in stride(from: 0, to: size.height, by: 14) {
                                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
                            }
                            context.stroke(lines, with: .color(Paper.board.opacity(0.09)), lineWidth: 0.5)
                        }.background(Paper.stock.opacity(0.75))
                    }
                    .overlay { Rectangle().strokeBorder(Paper.board.opacity(0.16), lineWidth: 0.7) }
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
        #if DEBUG && targetEnvironment(simulator)
        .task {
            if Storage.captureTab == "friend" { selected = library.shelf.friends.first?.id }
            if Storage.captureTab == "detail", let book = library.shelf.own, let stamp = book.stamps.first {
                detail = Shelf.Page(book: book, stamp: stamp)
            }
        }
        #endif
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
