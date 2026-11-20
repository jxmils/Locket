import SwiftUI
import UIKit

enum Paper {
    static let page = Color(red: 0.96, green: 0.94, blue: 0.88)
    static let stock = Color(red: 1, green: 0.985, blue: 0.94)
    static let ink = Color(red: 0.10, green: 0.22, blue: 0.17)
    static let red = Color(red: 0.63, green: 0.20, blue: 0.13)
}

/// Perforations follow the four edges at the same physical pitch.
struct PerforatedPaper: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let pitch = max(7, min(r.width, r.height) / 13)
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

struct StampArt: View {
    var image: UIImage?
    var body: some View {
        GeometryReader { geo in
            let pad = min(geo.size.width, geo.size.height) * 0.074
            ZStack {
                PerforatedPaper().fill(Paper.stock)
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else {
                        ZStack {
                            Color(red: 0.83, green: 0.85, blue: 0.75)
                            Image(systemName: "camera.aperture").font(.system(size: max(14, pad * 2.3), weight: .ultraLight))
                                .foregroundStyle(Paper.ink)
                        }
                    }
                }
                .frame(width: max(0, geo.size.width - 2 * pad), height: max(0, geo.size.height - 2 * pad))
                .clipped()
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}

extension Stamp {
    func image(small: Bool = true) -> UIImage? {
        guard let path = Storage.root?.appendingPathComponent(small ? thumbnail : photo).path else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
