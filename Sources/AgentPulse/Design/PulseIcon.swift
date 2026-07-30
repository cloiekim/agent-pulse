import SwiftUI
import AppKit

/// 메뉴바 아이콘의 파형.
///
/// 디자인의 `pulse-dark.svg` / `pulse-light.svg` 는 같은 path 에 stroke 색만
/// 다릅니다: `M2 12h4l3-8 4 16 3-8h6` (24×24 viewBox).
///
/// ⚠️ 왜 SwiftUI `Shape` 가 아니라 `NSImage` 인가:
/// `MenuBarExtra` 의 label 은 임의의 SwiftUI 뷰를 제대로 렌더하지 못하는 경우가
/// 많습니다. 커스텀 Shape 를 넣으면 메뉴바 아이템이 **폭 0으로 잡혀 아예 안 보입니다.**
/// 안정적으로 동작하는 건 `Text` 와 `Image` 뿐입니다.
///
/// 그리고 메뉴바 아이콘은 `isTemplate = true` 여야 합니다.
/// 그래야 라이트/다크 메뉴바, 강조 상태, 접근성 대비 설정에 macOS 가 알아서 맞춰줍니다.
enum PulseIcon {

    /// 메뉴바용 템플릿 이미지. 프로세스당 한 번만 그립니다.
    static let menuBar: NSImage = make(size: 16)

    static func make(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let s = size / 24
            // SVG 좌표계는 좌상단 원점, NSBezierPath 는 좌하단 원점 → y 를 뒤집습니다.
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: x * s, y: (24 - y) * s)
            }

            let path = NSBezierPath()
            path.move(to: p(2, 12))
            path.line(to: p(6, 12))
            path.line(to: p(9, 4))
            path.line(to: p(13, 20))
            path.line(to: p(16, 12))
            path.line(to: p(22, 12))

            path.lineWidth = 2.4 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // 템플릿 이미지는 색이 무시되고 알파만 쓰입니다.
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// 팝오버 안 등 일반 SwiftUI 컨텍스트에서 쓰는 파형.
/// (메뉴바 라벨에는 쓰지 마세요 — 위 주석 참고)
struct PulseWave: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.minX + (rect.width  - 24 * s) / 2
        let oy = rect.minY + (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var path = Path()
        path.move(to: p(2, 12))
        path.addLine(to: p(6, 12))
        path.addLine(to: p(9, 4))
        path.addLine(to: p(13, 20))
        path.addLine(to: p(16, 12))
        path.addLine(to: p(22, 12))
        return path
    }
}
