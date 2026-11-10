import SwiftUI

/// 仅用于明确标识的演示资料：与 Mac 客户端一致的原创几何封面。
struct DemoArtworkView: View {
    let title: String
    let seed: String

    private var palette: [Color] {
        let colors: [[Color]] = [
            [Color(red: 0.65, green: 0.53, blue: 0.40), Color(red: 0.94, green: 0.89, blue: 0.78), Color(red: 0.36, green: 0.40, blue: 0.38)],
            [Color(red: 0.39, green: 0.33, blue: 0.42), Color(red: 0.84, green: 0.73, blue: 0.74), Color(red: 0.70, green: 0.46, blue: 0.40)],
            [Color(red: 0.35, green: 0.38, blue: 0.29), Color(red: 0.87, green: 0.84, blue: 0.68), Color(red: 0.66, green: 0.58, blue: 0.40)],
            [Color(red: 0.85, green: 0.44, blue: 0.31), Color(red: 0.96, green: 0.82, blue: 0.64), Color(red: 0.43, green: 0.22, blue: 0.23)]
        ]
        let index = seed.utf8.reduce(0) { $0 + Int($1) } % colors.count
        return colors[index]
    }

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack(alignment: .bottomLeading) {
                palette[0]
                Circle().fill(palette[1])
                    .frame(width: side * 0.64, height: side * 0.64)
                    .offset(x: side * 0.44, y: -side * 0.55)
                Ellipse().fill(palette[2])
                    .frame(width: side * 1.4, height: side * 1.2)
                    .offset(x: -side * 0.2, y: side * 0.4)
                Ellipse().fill(palette[1].opacity(0.55))
                    .frame(width: side * 1.4, height: side * 0.8)
                    .offset(x: -side * 0.15, y: side * 0.45)
                VStack(alignment: .leading) {
                    Text("SYNO / STUDIO")
                        .font(.system(size: max(6, side * 0.028), weight: .medium))
                        .tracking(side * 0.005)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(title)
                        .font(.system(size: max(9, side * 0.055), weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(side * 0.075)
            }
        }
        .clipped()
        .accessibilityLabel(title)
    }
}
