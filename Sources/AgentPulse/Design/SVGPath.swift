import SwiftUI

/// SVG `d` 속성을 SwiftUI `Path` 로 바꾸는 최소 파서.
///
/// 브랜드 로고 두 개(Claude, OpenAI)에 필요한 명령어만 지원합니다:
/// `M m L l H h V v A a Z z`
///
/// 곡선(C/S/Q/T)은 이 로고들이 안 쓰므로 넣지 않았습니다.
/// 나중에 다른 로고를 추가하다 무시되는 명령이 생기면 여기에 더하세요.
struct SVGPathParser {
    private let scalars: [Character]
    private var i = 0

    init(_ d: String) {
        scalars = Array(d)
    }

    mutating func parse() -> Path {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character = "M"

        while true {
            skipSeparators()
            guard i < scalars.count else { break }

            // 명령 글자면 갱신하고, 숫자면 직전 명령을 반복합니다.
            // (SVG 는 "L 1 2 3 4" 처럼 인자를 이어 붙일 수 있습니다.)
            if scalars[i].isLetter {
                command = scalars[i]
                i += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    continue
                }
            }

            let relative = command.isLowercase

            switch Character(command.lowercased()) {
            case "m":
                guard let x = number(), let y = number() else { return path }
                let p = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: p)
                current = p
                subpathStart = p
                // moveto 뒤에 좌표가 더 오면 lineto 로 해석하는 게 SVG 규칙입니다.
                command = relative ? "l" : "L"

            case "l":
                guard let x = number(), let y = number() else { return path }
                let p = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: p)
                current = p

            case "h":
                guard let x = number() else { return path }
                let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: p)
                current = p

            case "v":
                guard let y = number() else { return path }
                let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: p)
                current = p

            case "a":
                guard let rx = number(), let ry = number(), let rot = number(),
                      let largeArc = flag(), let sweep = flag(),
                      let x = number(), let y = number() else { return path }
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                Self.appendArc(to: &path, from: current, to: end,
                               rx: rx, ry: ry, rotationDegrees: rot,
                               largeArc: largeArc, sweep: sweep)
                current = end

            default:
                // 모르는 명령 — 무한 루프를 피하려고 한 글자 넘깁니다.
                i += 1
            }
        }

        return path
    }

    // MARK: - 토크나이저

    private mutating func skipSeparators() {
        while i < scalars.count, scalars[i] == " " || scalars[i] == "," || scalars[i] == "\n" || scalars[i] == "\t" {
            i += 1
        }
    }

    /// 부호 없는 한 자리 플래그. SVG 원호의 large-arc / sweep 는
    /// 다음 숫자에 붙어 나올 수 있어서(`0 0 0-.5157`) 한 글자만 읽습니다.
    private mutating func flag() -> Bool? {
        skipSeparators()
        guard i < scalars.count else { return nil }
        let c = scalars[i]
        guard c == "0" || c == "1" else { return nil }
        i += 1
        return c == "1"
    }

    private mutating func number() -> Double? {
        skipSeparators()
        guard i < scalars.count else { return nil }

        let start = i
        if scalars[i] == "-" || scalars[i] == "+" { i += 1 }

        var sawDigit = false
        var sawDot = false
        while i < scalars.count {
            let c = scalars[i]
            if c.isNumber {
                sawDigit = true
                i += 1
            } else if c == "." && !sawDot {
                sawDot = true
                i += 1
            } else if (c == "e" || c == "E"), sawDigit {
                i += 1
                if i < scalars.count, scalars[i] == "-" || scalars[i] == "+" { i += 1 }
            } else {
                break
            }
        }

        guard sawDigit else { i = start; return nil }
        return Double(String(scalars[start..<i]))
    }

    // MARK: - 원호 → 베지어

    /// SVG 의 원호는 끝점 기준이고 CoreGraphics 는 중심 기준이라
    /// W3C 명세(F.6.5)의 변환을 그대로 구현합니다.
    private static func appendArc(to path: inout Path,
                                  from start: CGPoint, to end: CGPoint,
                                  rx rxIn: Double, ry ryIn: Double,
                                  rotationDegrees: Double,
                                  largeArc: Bool, sweep: Bool) {
        // 반지름이 0이면 직선입니다.
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: end)
            return
        }
        if start == end { return }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2, dy2 = (start.y - end.y) / 2
        let x1p =  cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // 반지름이 너무 작으면 키웁니다 (명세 F.6.6).
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }

        let sign: Double = (largeArc != sweep) ? 1 : -1
        let num = rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p
        let den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
        let coef = sign * sqrt(max(0, num / den))

        let cxp =  coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux*ux + uy*uy) * sqrt(vx*vx + vy*vy)
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta  = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                           (-x1p - cxp) / rx, (-y1p - cyp) / ry)

        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // 90도 이하 조각으로 쪼개서 3차 베지어로 근사합니다.
        let segments = Int(ceil(abs(delta) / (.pi / 2)))
        let step = delta / Double(segments)
        let k = 4.0 / 3.0 * tan(step / 4)

        var theta = theta1
        for _ in 0..<segments {
            let cosT1 = cos(theta), sinT1 = sin(theta)
            let t2 = theta + step
            let cosT2 = cos(t2), sinT2 = sin(t2)

            func point(_ ct: Double, _ st: Double) -> CGPoint {
                CGPoint(x: cx + rx * ct * cosPhi - ry * st * sinPhi,
                        y: cy + rx * ct * sinPhi + ry * st * cosPhi)
            }
            func derivative(_ ct: Double, _ st: Double) -> CGPoint {
                CGPoint(x: -rx * st * cosPhi - ry * ct * sinPhi,
                        y: -rx * st * sinPhi + ry * ct * cosPhi)
            }

            let p1 = point(cosT1, sinT1), p2 = point(cosT2, sinT2)
            let d1 = derivative(cosT1, sinT1), d2 = derivative(cosT2, sinT2)

            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + k * d1.x, y: p1.y + k * d1.y),
                control2: CGPoint(x: p2.x - k * d2.x, y: p2.y - k * d2.y)
            )
            theta = t2
        }
    }
}
