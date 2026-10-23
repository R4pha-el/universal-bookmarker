import SwiftUI

struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width * 0.09, 18)
        let tabHeight = rect.height * 0.15
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 0.38, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.48, y: tabHeight), control: CGPoint(x: rect.width * 0.44, y: 0))
        path.addLine(to: CGPoint(x: rect.width - radius, y: tabHeight))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: tabHeight + radius), control: CGPoint(x: rect.width, y: tabHeight))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}
