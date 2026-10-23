import SwiftUI

struct AccountAtmosphere: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 22
            for column in 0...Int(size.width / step) {
                for row in 0...Int(size.height / step) {
                    let x = CGFloat(column) * step
                    let y = CGFloat(row) * step
                    let fade = max(0, 1 - abs(x - size.width * 0.7) / max(size.width, 1))
                    let radius: CGFloat = column.isMultiple(of: 4) ? 1.7 : 0.8
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.04 + fade * 0.12)))
                }
            }
        }
        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
