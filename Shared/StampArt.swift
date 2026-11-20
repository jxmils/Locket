import SwiftUI
import UIKit

enum Paper {
    static let page = Color(red: 0.968, green: 0.953, blue: 0.907)
    static let board = Color(red: 0.115, green: 0.255, blue: 0.24)
    static let lining = Color(red: 0.79, green: 0.81, blue: 0.69)
    static let stock = Color(red: 1, green: 0.976, blue: 0.873)
    static let ink = Color(red: 0.125, green: 0.19, blue: 0.168)
    static let red = Color(red: 0.64, green: 0.21, blue: 0.105)
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

struct StampArt: View {
    var image: UIImage?
    var ratio: CGFloat = 1
    var inscription: String?
    var body: some View {
        GeometryReader { geo in
            let pad = min(geo.size.width, geo.size.height) * 0.067
            ZStack {
                PerforatedPaper().fill(Paper.stock)
                VStack(spacing: 0) {
                    GeometryReader { space in
                        ZStack {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .saturation(0.74).contrast(1.05)
                                    .colorMultiply(Color(red: 1, green: 0.976, blue: 0.907))
                            } else {
                                Paper.lining
                                Image(systemName: "camera.aperture")
                                    .font(.system(size: max(16, pad * 2), weight: .light))
                                    .foregroundStyle(Paper.ink)
                            }
                        }
                        .frame(width: space.size.width, height: space.size.height)
                        .clipped()
                        .overlay { Rectangle().strokeBorder(Paper.ink.opacity(0.45), lineWidth: 0.7) }
                    }
                    if let inscription {
                        HStack {
                            Image(systemName: "envelope").accessibilityHidden(true)
                            Spacer()
                            Text(inscription.uppercased()).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .font(.system(size: max(9, pad * 0.59), weight: .bold, design: .monospaced))
                        .tracking(1).foregroundStyle(Paper.ink)
                        .padding(.top, pad * 0.45)
                    }
                }
                .padding(pad * 0.27)
                .overlay { Rectangle().strokeBorder(Paper.ink.opacity(0.65), lineWidth: 1) }
                .padding(pad * 0.76)
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
