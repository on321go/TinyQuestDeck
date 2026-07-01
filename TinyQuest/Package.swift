// swift-tools-version: 6.0
import PackageDescription

// One local package, multiple library targets — the clean-architecture SPM shape that
// matches the 4-module roadmap (TinyQuestData / TinyQuestUI slot in here later).
// Module name == target name, independent of filenames. `import TinyQuestKit` resolves
// to the target below, so Core.swift's name is irrelevant.

let package = Package(
    name: "TinyQuest",
    // This is the package's MINIMUM supported OS, not the app's. Kit/Content are pure
    // Foundation, so the floor is low and portable; the app stays at iOS 26 and pulls
    // the package up to its own deployment target.
    platforms: [
        .iOS(.v17),
        .macOS(.v13),   // lets `swift test` run the pure Kit/Content tests on the Mac host
    ],
    products: [
        .library(name: "TinyQuestKit", targets: ["TinyQuestKit"]),
        .library(name: "TinyQuestContent", targets: ["TinyQuestContent"]),
    ],
    targets: [
        .target(name: "TinyQuestKit"),                                   // pure domain, no deps
        .target(name: "TinyQuestContent", dependencies: ["TinyQuestKit"]),

        // M2 wires these in (decode-and-validate test loads content.json as a resource):
        // .testTarget(name: "TinyQuestKitTests", dependencies: ["TinyQuestKit"]),
        // .testTarget(
        //     name: "TinyQuestContentTests",
        //     dependencies: ["TinyQuestContent"],
        //     resources: [.copy("Resources/content.json")]
        // ),
    ]
)
