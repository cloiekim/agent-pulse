// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentPulse",
    platforms: [
        // MenuBarExtra(.window) + Observation 을 쓰기 위해 macOS 14 이상.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AgentPulse",
            path: "Sources/AgentPulse",
            resources: [
                // 브랜드 로고(벡터 SVG). Xcode 12+ 는 에셋 카탈로그에서
                // SVG 를 벡터 그대로 보존합니다.
                .process("Resources/Assets.xcassets")
            ]
        )
    ]
)
