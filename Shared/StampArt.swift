import SwiftUI
import UIKit

enum Paper {
    static let page = Color(red: 0.982, green: 0.977, blue: 0.966)
    static let plum = Color(red: 0.29, green: 0.18, blue: 0.35)
    static let lilac = Color(red: 0.88, green: 0.84, blue: 0.98)
    static let melon = Color(red: 1, green: 0.76, blue: 0.65)
    static let stock = Color(red: 1, green: 0.985, blue: 0.94)
    static let ink = Color(red: 0.13, green: 0.105, blue: 0.145)
    static let red = Color(red: 0.72, green: 0.18, blue: 0.16)
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
    var ratio: CGFloat = 1
    var body: some View {
        GeometryReader { geo in
            let pad = min(geo.size.width, geo.size.height) * 0.043
            ZStack {
                PerforatedPaper().fill(Paper.stock)
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else {
                        ZStack {
                            Paper.lilac
                            Image(systemName: "camera.aperture").font(.system(size: max(14, pad * 2.3), weight: .ultraLight))
                                .foregroundStyle(Paper.ink)
                        }
                    }
                }
                .frame(width: max(0, geo.size.width - 2 * pad), height: max(0, geo.size.height - 2 * pad))
                .clipped()
            }
        }.aspectRatio(ratio, contentMode: .fit)
    }
}

extension Stamp {
    func image(small: Bool = true) -> UIImage? {
        guard let path = Storage.root?.appendingPathComponent(small ? thumbnail : photo).path else { return nil }
        return UIImage(contentsOfFile: path)
    }
}
