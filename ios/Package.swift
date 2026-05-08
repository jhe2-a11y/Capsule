// swift-tools-version: 5.9
// Capsule iOS — SwiftPM manifest used for dependency resolution. The actual
// app target is built via Capsule.xcodeproj; this file declares the third-
// party packages the project consumes.

import PackageDescription

let package = Package(
    name: "Capsule",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CapsuleCore", targets: ["CapsuleCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase-community/supabase-swift.git",
                 from: "2.13.0"),
    ],
    targets: [
        .target(
            name: "CapsuleCore",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Capsule",
            exclude: ["App", "Features", "Resources", "Shaders"],
            sources: ["Core"]
        ),
    ]
)
