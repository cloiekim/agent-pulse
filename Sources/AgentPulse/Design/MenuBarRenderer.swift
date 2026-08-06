import AppKit

/// 메뉴바 아이템을 **이미지 하나로 그립니다.**
///
/// ⚠️ 왜 이미지인가:
/// `MenuBarExtra` 의 label 에는 임의의 SwiftUI 뷰(Shape, GeometryReader 등)를
/// 넣을 수 없습니다 — 아이템 폭이 0 으로 잡혀 **아예 안 보이는** 경우가 있습니다.
/// 안정적인 건 `Image` 와 `Text` 뿐입니다.
///
/// 그런데 디자인은 캡슐 배경, 글리프, 라벨을 하나의 덩어리로 요구합니다.
/// 그래서 전부 `NSImage` 로 그려서 `Image` 하나로 넘깁니다.
/// 지오메트리·색·템플릿 여부를 전부 우리가 통제할 수 있게 됩니다.
enum MenuBarRenderer {

    /// 무엇을 그릴지.
    struct Spec {
        enum Kind {
            /// 맨 글리프. 뭔가 있으면 우상단에 상태색 점.
            case bare(dot: NSColor?)
            /// 실선 없는 얇은 테두리 캡슐 (실행 중).
            case outline(text: String)
            /// 꽉 찬 캡슐 (승인 대기·실패).
            case filled(text: String, background: NSColor, foreground: NSColor)
        }
        var kind: Kind
        /// 템플릿이면 시스템이 알아서 색을 반전시킵니다.
        /// 채워진 캡슐은 **템플릿이면 안 됩니다** — 색이 통째로 날아갑니다.
        var isTemplate: Bool
        /// 파형의 위상. `0 ..< frameCount`. 실행 중일 때만 0 이 아닙니다.
        var phase: Int = 0
    }

    /// 한 바퀴를 몇 장으로 나눌 것인가.
    ///
    /// ⚠️ 12장 / 1.2초 = 10fps. 파형이 흐르는 걸 보여주는 데는 이걸로 충분하고
    ///    그 이상은 배터리만 씁니다. 그리고 **그릴 때마다 새로 그리지 않습니다** —
    ///    12장을 캐시에 넣고 돌려 끼웁니다. 그래서 실행 중에 하는 일은
    ///    0.1초마다 이미 만들어둔 `NSImage` 하나를 갈아 끼우는 것뿐입니다.
    static let frameCount = 12

    // MARK: - 지오메트리 (스펙 값)

    /// 메뉴바에서 쓸 수 있는 세로 22px 중 캡슐이 19px.
    private static let capsuleHeight: CGFloat = 19
    private static let glyphInCapsule: CGFloat = 14
    private static let glyphBare: CGFloat = 15
    /// 글리프는 텍스트보다 시각적 여백이 덜 필요해서 좌우가 다릅니다.
    private static let padLeft: CGFloat = 5
    private static let padRight: CGFloat = 8
    private static let gap: CGFloat = 2
    private static let labelSize: CGFloat = 11

    // MARK: - 그리기

    /// 그려둔 이미지 보관함. 키가 같으면 다시 그리지 않습니다.
    private static var cache: [String: NSImage] = [:]

    private static func cacheKey(_ spec: Spec) -> String {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let kind: String
        switch spec.kind {
        case .bare(let dot):
            kind = "bare|\(dot?.description ?? "-")"
        case .outline(let text):
            kind = "outline|\(text)"
        case .filled(let text, let bg, let fg):
            kind = "filled|\(text)|\(bg.description)|\(fg.description)"
        }
        return "\(kind)|\(spec.isTemplate)|\(spec.phase)|\(dark)"
    }

    static func image(_ spec: Spec) -> NSImage {
        let key = cacheKey(spec)
        if let hit = cache[key] { return hit }
        let made = render(spec)
        // 라벨 문구가 바뀌면 키가 늘어납니다. 무한정 쌓이지 않게 잘라냅니다.
        if cache.count > 96 { cache.removeAll() }
        cache[key] = made
        return made
    }

    private static func render(_ spec: Spec) -> NSImage {
        switch spec.kind {
        case .bare(let dot):
            return bareImage(dot: dot, isTemplate: spec.isTemplate, phase: spec.phase)
        case .outline(let text):
            return capsuleImage(text: text, fill: nil,
                                content: .labelColor, isTemplate: spec.isTemplate,
                                phase: spec.phase)
        case .filled(let text, let background, let foreground):
            return capsuleImage(text: text, fill: background,
                                content: foreground, isTemplate: spec.isTemplate,
                                phase: spec.phase)
        }
    }

    private static func bareImage(dot: NSColor?, isTemplate: Bool, phase: Int) -> NSImage {
        // ⚠️ 점이 있을 때만 그만큼 넓힙니다.
        //    항상 여백을 두면 조용할 때 오른쪽에 빈 공간이 생기고,
        //    메뉴바에서 폭은 예산이라 그 4px 도 아까워집니다.
        let extra: CGFloat = dot == nil ? 0 : 4
        let size = NSSize(width: glyphBare + extra, height: capsuleHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            let glyphRect = NSRect(x: 0,
                                   y: (size.height - glyphBare) / 2,
                                   width: glyphBare, height: glyphBare)
            // ⚠️ 템플릿 이미지에서 알파는 **곧 마스크**입니다.
            //    55% 로 그리면 시스템이 그 투명도 그대로 벽지 위에 얹어서,
            //    아이콘이 빽빽한 메뉴바나 밝은 벽지에서는 사실상 안 보입니다.
            //    (실제로 "파형 아이콘이 안 보인다" 가 반복해서 나왔습니다.)
            //
            //    디자인의 55% 는 여유 있는 메뉴바 기준이었습니다.
            //    보이지 않는 아이콘은 조용한 게 아니라 없는 것이므로 85% 로 올립니다.
            drawGlyph(in: glyphRect, color: NSColor.labelColor.withAlphaComponent(0.85), phase: phase)

            if let dot {
                let d: CGFloat = 6
                let rect = NSRect(x: glyphRect.maxX - 3,
                                  y: glyphRect.maxY - d + 1,
                                  width: d, height: d)
                dot.setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        // 점이 있으면 색을 살려야 하므로 템플릿을 끕니다.
        image.isTemplate = isTemplate && dot == nil
        return image
    }

    private static func capsuleImage(text: String,
                                     fill: NSColor?,
                                     content: NSColor,
                                     isTemplate: Bool,
                                     phase: Int) -> NSImage {
        let font = NSFont.systemFont(ofSize: labelSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: content]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let width = padLeft + glyphInCapsule + gap + ceil(textSize.width) + padRight
        let size = NSSize(width: width, height: capsuleHeight)

        let image = NSImage(size: size, flipped: false) { _ in
            let bounds = NSRect(origin: .zero, size: size)
            let radius = size.height / 2
            let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

            if let fill {
                fill.setFill()
                path.fill()
            } else {
                // 실행 중은 얇은 테두리만. 라벨 색의 70% 로 눌러
                // 승인 대기(꽉 찬 앰버)보다 조용하게 유지합니다.
                content.withAlphaComponent(0.55).setStroke()
                let inset = path.lineWidth / 2
                let stroked = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                           xRadius: radius, yRadius: radius)
                stroked.lineWidth = 1
                stroked.stroke()
            }

            let glyphRect = NSRect(x: padLeft,
                                   y: (size.height - glyphInCapsule) / 2,
                                   width: glyphInCapsule, height: glyphInCapsule)
            drawGlyph(in: glyphRect, color: content, phase: phase)

            let textOrigin = NSPoint(x: glyphRect.maxX + gap,
                                     y: (size.height - textSize.height) / 2)
            (text as NSString).draw(at: textOrigin, withAttributes: attrs)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    // MARK: - 파형

    /// 24×24 뷰박스 기준 경로를 주어진 사각형에 맞춰 그립니다.
    ///
    /// 경로는 디자인에서 내보낸 SVG 와 같습니다:
    ///   `M3.5 12 h3.5 l2.5 -7 l4.5 14 l2.5 -7 h4`  (stroke 2.2, round cap/join)
    /// 파형 한 마디의 가로 길이 (24 뷰박스 기준).
    ///
    /// ⚠️ 3.5 에서 시작해 20.5 에서 끝나므로 마디 길이가 17 입니다.
    ///    이 값으로 이어 붙이면 앞 마디의 끝(20.5)과 뒤 마디의 시작(3.5+17=20.5)이
    ///    **정확히 만나서** 선이 끊기지 않습니다. 다른 값을 쓰면 이음매가 보입니다.
    private static let wavePeriod: CGFloat = 17

    private static func drawGlyph(in rect: NSRect, color: NSColor, phase: Int = 0) {
        let scale = rect.width / 24
        let shift = CGFloat(phase) / CGFloat(frameCount) * wavePeriod

        func point(_ x: CGFloat, _ y: CGFloat, _ offset: CGFloat) -> NSPoint {
            // SVG 는 y 가 아래로 증가하고 AppKit 은 위로 증가합니다.
            NSPoint(x: rect.minX + (x + offset - shift) * scale,
                    y: rect.maxY - y * scale)
        }

        NSGraphicsContext.saveGraphicsState()
        // ⚠️ 자르는 창을 오른쪽으로 2pt 좁힙니다.
        //
        //    파형을 이어 붙여 흐르게 만들면서 **잉크가 박스 끝까지 꽉 차게**
        //    됐습니다. 예전엔 한 마디만 그려서 20.5 에서 끝났고 오른쪽에
        //    여백이 저절로 남았는데, 이제는 안 남습니다.
        //    간격(2)은 그대로인데 눈에 보이는 여백만 사라져서 글자에
        //    붙어 보였습니다.
        //
        //    간격을 4 로 늘리는 대신 자르는 창을 좁힙니다.
        //    캡슐 전체 폭이 그대로 유지됩니다 — 메뉴바에서 폭은 예산입니다.
        let clip = NSRect(x: rect.minX, y: rect.minY,
                          width: rect.width - 2, height: rect.height)
        NSBezierPath(rect: clip).setClip()

        // 앞뒤로 한 마디씩 더 그려야 어느 위상에서도 빈 곳이 안 생깁니다.
        for i in -1...1 {
            let offset = CGFloat(i) * wavePeriod
            let path = NSBezierPath()
            path.move(to: point(3.5, 12, offset))
            path.line(to: point(7, 12, offset))
            path.line(to: point(9.5, 5, offset))
            path.line(to: point(14, 19, offset))
            path.line(to: point(16.5, 12, offset))
            path.line(to: point(20.5, 12, offset))

            path.lineWidth = 2.2 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}
