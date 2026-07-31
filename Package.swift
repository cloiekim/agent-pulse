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
                .process("Resources/Assets.xcassets"),

                // ⚠️ 폰트는 `.copy` 여야 합니다.
                //    `.process` 는 파일을 가공하려 들어서 폰트가 깨질 수 있습니다.
                //    앱이 자기 폰트를 들고 다녀야 하는 이유는 FontLoader 주석 참고.
                .copy("Resources/Figtree-Regular.ttf"),
                .copy("Resources/Figtree-Medium.ttf"),
                .copy("Resources/Figtree-SemiBold.ttf")
            ]
        )
    ]
)
