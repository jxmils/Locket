import SwiftUI
import UIKit

enum Paper {
    static let page = Color(red: 0.967, green: 0.955, blue: 0.918)
    static let board = Color(red: 0.16, green: 0.29, blue: 0.43)
    static let lining = Color(red: 0.79, green: 0.84, blue: 0.86)
    static let stock = Color(red: 1, green: 0.985, blue: 0.948)
    static let ink = Color(red: 0.08, green: 0.17, blue: 0.28)
    static let red = Color(red: 0.70, green: 0.19, blue: 0.105)
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

/// One physical layout for the lens, the frozen proof, the feed and the book.
struct PostageFace<Picture: View>: View {
    static var aspect: CGFloat { 1 / 1.105 }
    let date: String
    var inked = true
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let margin = w * 0.043
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

struct FriendWidgetFace: View {
    let name: String
    let day: String
    let image: UIImage?
    var wide = false
    var body: some View {
        GeometryReader { g in
            let width = min(g.size.width * (wide ? 0.55 : 1), (g.size.height - (wide ? 4 : 23)) / 1.105)
            let layout = wide ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 3))
            layout {
                StampArt(image: image, inscription: day)
                    .frame(width: max(1,width), height: max(1,width) * 1.105)
                    .shadow(color: Paper.ink.opacity(0.18), radius: 1, y: 1)
                Text("From \(name)").font(.system(wide ? .title3 : .caption, design: .serif).italic())
                    .lineLimit(wide ? 2 : 1).minimumScaleFactor(0.8).foregroundStyle(Paper.ink)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
