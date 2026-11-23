import SwiftUI
import UIKit

enum Paper {
    static let page = Color(red: 242/255, green: 240/255, blue: 240/255)
    static let board = Color(red: 0.32, green: 0.37, blue: 0.33)
    static let lining = Color(red: 0.86, green: 0.85, blue: 0.86)
    static let stock = Color(red: 0.992, green: 0.991, blue: 0.992)
    static let ink = Color(red: 0.16, green: 0.15, blue: 0.16)
    static let red = Color(red: 0.52, green: 0.205, blue: 0.235)
    static let rule = ink.opacity(0.26)
}

/// Perforations follow the four edges at the same physical pitch.
struct PerforatedPaper: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let pitch = max(7, min(r.width, r.height) / 20)
        let corners = [CGPoint(x: r.minX,y: r.minY), CGPoint(x: r.maxX,y: r.minY),
                       CGPoint(x: r.maxX,y: r.maxY), CGPoint(x: r.minX,y: r.maxY)]
        path.move(to: corners[0])
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % 4]
            let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
            guard length > 0 else { continue }
            let count = max(1, Int((length / pitch).rounded()))
            let step = length / CGFloat(count), notch = step * 0.28
            func point(_ distance: CGFloat, _ depth: CGFloat = 0) -> CGPoint {
                CGPoint(x: a.x + (dx * distance - dy * depth) / length,
                        y: a.y + (dy * distance + dx * depth) / length)
            }
            for j in 0..<count {
                let mid = (CGFloat(j) + 0.5) * step
                path.addLine(to: point(mid - notch))
                path.addQuadCurve(to: point(mid, notch), control: point(mid - notch, notch))
                path.addQuadCurve(to: point(mid + notch), control: point(mid + notch, notch))
            }
            path.addLine(to: b)
        }
        path.closeSubpath()
        return path
    }
}

enum StampLayout {
    static let heightPerWidth: CGFloat = 1.105
    static let photoInset: CGFloat = 0.043
}

/// One physical layout for the lens, the frozen proof, the feed and the book.
struct PostageFace<Picture: View>: View {
    static var aspect: CGFloat { 1 / StampLayout.heightPerWidth }
    let date: String
    var inked = true
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let margin = w * StampLayout.photoInset
            let side = w - 2 * margin
            ZStack(alignment: .topLeading) {
                PerforatedPaper().fill(Paper.stock)
                picture()
                    .frame(width: side, height: side).clipped()
                    .overlay { Rectangle().strokeBorder(Paper.ink.opacity(0.22), lineWidth: 0.7) }
                    .offset(x: margin, y: margin)
                Text("Stampnote").italic().font(.system(size: w * 0.076, weight: .semibold, design: .serif))
                    .foregroundStyle(Paper.ink)
                    .position(x: w * 0.23, y: w * 1.018)
                if inked {
                    Postmark(date: date).frame(width: w * 0.43, height: w * 0.128)
                        .rotationEffect(.degrees(-6)).position(x: w * 0.81, y: w * 0.991)
                }
            }.clipShape(PerforatedPaper())
        }.aspectRatio(Self.aspect, contentMode: .fit)
    }
}

struct Postmark: View {
    let date: String
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let box = g.size.width * 0.72
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    for row in -1...1 {
                        let y = h * (0.5 + CGFloat(row)*0.14)
                        var line = Path()
                        line.move(to: CGPoint(x: box-1, y: y))
                        line.addCurve(to: CGPoint(x: size.width, y: y), control1: CGPoint(x: box+h*0.3, y: y-h*0.21), control2: CGPoint(x: size.width-h*0.24, y: y+h*0.20))
                        ctx.stroke(line, with: .color(Paper.red), lineWidth: max(0.6, h*0.032))
                    }
                }
                VStack(spacing: h * 0.026) {
                    Text("POST").font(.system(size: h * 0.22, weight: .black, design: .serif))
                    Text(date.uppercased()).font(.system(size: h * 0.245, weight: .bold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.66)
                }.padding(.horizontal, h * 0.08).frame(width: box, height: h*0.80)
                    .background(Paper.stock.opacity(0.92), in: Capsule())
                    .overlay { Capsule().strokeBorder(Paper.red, lineWidth: max(0.7,h*0.032)) }
            }.foregroundStyle(Paper.red)
        }.accessibilityHidden(true)
    }
}

struct SenderPortrait: View {
    let name: String
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let photo = UIImage(data: data) {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                let initials = name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
                Text(String(initials).uppercased()).font(.system(size: size * 0.39, weight: .medium, design: .serif))
                    .foregroundStyle(Paper.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Paper.lining)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay { Circle().strokeBorder(Paper.ink.opacity(0.15)) }
        .accessibilityHidden(true)
    }
}

struct FriendWidgetFace: View {
    let name: String
    let day: String
    let image: UIImage?
    let portrait: Data?

    var body: some View {
        GeometryReader { g in
            let compact = g.size.width < 200
            let edge: CGFloat = compact ? 6 : 8
            let avatar: CGFloat = compact ? 25 : 33
            VStack(spacing: 0) {
                GeometryReader { photo in
                    ZStack {
                        Paper.lining
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .frame(width: photo.size.width, height: photo.size.height).clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if compact {
                            Postmark(date: day).frame(width: 78, height: 27)
                                .rotationEffect(.degrees(-6)).padding(3)
                        }
                    }
                }
                HStack(spacing: 6) {
                    SenderPortrait(name: name, data: portrait, size: avatar)
                    Text(name).italic().font(.system(compact ? .subheadline : .headline, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(Paper.ink)
                    Spacer(minLength: 0)
                    if !compact {
                        Postmark(date: day).frame(width: 112, height: 34).rotationEffect(.degrees(-6))
                    }
                }
                .padding(.horizontal, 4).padding(.top, 3)
            }
            .padding(edge)
            .background(Paper.stock)
            .clipShape(PerforatedPaper())
            .background(Paper.board)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stamp from \(name), \(day)")
    }
}

struct StampArt: View {
    var image: UIImage?
    var inscription: String?
    var body: some View {
        PostageFace(date: inscription ?? "", inked: image != nil) {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Paper.lining.overlay { Image(systemName: "camera").foregroundStyle(Paper.ink) } }
        }
    }
}

extension Stamp {
    func image(small: Bool = true) -> UIImage? {
        guard let path = Storage.root?.appendingPathComponent(small ? thumbnail : photo).path else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
