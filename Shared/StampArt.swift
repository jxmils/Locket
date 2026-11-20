import SwiftUI
import UIKit

enum Paper {
    static let page = Color(red: 0.958, green: 0.951, blue: 0.933)
    static let board = Color(red: 0.23, green: 0.22, blue: 0.35)
    static let lining = Color(red: 0.80, green: 0.81, blue: 0.91)
    static let stock = Color(red: 1, green: 0.985, blue: 0.948)
    static let ink = Color(red: 0.13, green: 0.12, blue: 0.16)
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Stampnote").italic().font(.system(size: w * 0.066, weight: .semibold, design: .serif))
                    Spacer()
                    Text(date.uppercased()).font(.system(size: w * 0.032, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Paper.ink).frame(width: side)
                .position(x: w/2, y: w * 1.016)
                if inked {
                    Postmark().frame(width: w * 0.245, height: w * 0.14)
                        .rotationEffect(.degrees(-12))
                        .position(x: w * 0.89, y: w * 0.918)
                }
            }.clipShape(PerforatedPaper())
        }.aspectRatio(Self.aspect, contentMode: .fit)
    }
}

struct Postmark: View {
    var body: some View {
        Canvas { ctx, size in
            let d = size.height
            let pigment = GraphicsContext.Shading.color(Paper.red.opacity(0.95))
            let circle = CGRect(x: 1, y: 1, width: d-2, height: d-2)
            ctx.stroke(Path(ellipseIn: circle), with: pigment, lineWidth: max(1, d * 0.035))
            ctx.stroke(Path(ellipseIn: circle.insetBy(dx: d*0.07, dy: d*0.07)), with: pigment, lineWidth: max(0.5, d*0.016))
            ctx.draw(Text("POST").font(.system(size: d*0.23, weight: .black, design: .serif)).foregroundStyle(Paper.red),
                     at: CGPoint(x: d/2, y: d/2))
            for row in -1...1 {
                let y = d * (0.50 + CGFloat(row)*0.13)
                var line = Path()
                line.move(to: CGPoint(x: d*0.88, y: y))
                line.addCurve(to: CGPoint(x: size.width, y: y-d*0.02), control1: CGPoint(x: d*1.22, y: y-d*0.20), control2: CGPoint(x: size.width-d*0.18, y: y+d*0.16))
                ctx.stroke(line, with: pigment, lineWidth: max(0.8, d*0.031))
            }
        }.accessibilityHidden(true)
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
