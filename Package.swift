// swift-tools-version:5.10
import PackageDescription

// CEF (Chromium Embedded Framework) lives in vendor/cef, fetched by
// scripts/fetch-cef.sh, with its C++ wrapper built by CMake into
// vendor/cef/build/libcef_dll_wrapper. A build for the other CPU (scripts/build.sh with
// CRA_ARCH) points CRA_CEF_DIR at that CPU's copy, vendor/cef-<arch>.
let cefRoot = Context.environment["CRA_CEF_DIR"] ?? "\(Context.packageDirectory)/vendor/cef"

// Same flags CEF uses for its own wrapper (vendor/cef/cmake/cef_variables.cmake),
// so the ABI of the wrapper classes matches.
let cefCXXFlags: [String] = [
    "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics",
    "-fobjc-call-cxx-cdtors", "-fno-strict-aliasing",
    "-Wno-unused-parameter", "-Wno-deprecated-declarations",
    "-I", cefRoot,
]

let cefLinkerFlags: [String] = [
    "-L\(cefRoot)/build/libcef_dll_wrapper",
]

// CRA_ENGINE=chromium builds Cra on Chrome's own framework instead of CEF (docs/chromium-engine.md): CraCEF is
// then only its header, implemented inside the framework, which CRA_ENGINE_FRAMEWORKS holds (the
// Chromium.app/Contents/Frameworks of a scripts/build-chromium.sh build). No CraHelper: Chrome's own helpers
// come with the framework.
let chromiumEngine = Context.environment["CRA_ENGINE"] == "chromium"
let engineFrameworks = Context.environment["CRA_ENGINE_FRAMEWORKS"] ?? ""

// Sparkle, the updater framework Arc ships, lives in vendor/sparkle (scripts/fetch-sparkle.sh);
// scripts/build.sh copies Sparkle.framework into Cra.app/Contents/Frameworks.
let sparkleRoot = "\(Context.packageDirectory)/vendor/sparkle"

let package = Package(
    name: "Cra",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cra", targets: ["Cra"]),
    ] + (chromiumEngine ? [] : [.executable(name: "CraHelper", targets: ["CraHelper"])]) + [
        .executable(name: "CraPluginHost", targets: ["CraPluginHost"]),
        // Loaded by the Dock, not by Cra; scripts/build.sh wraps it in
        // Cra.app/Contents/PlugIns/CraDockTile.docktileplugin.
        .library(name: "CraDockTile", type: .dynamic, targets: ["CraDockTile"]),
    ],
    // Models and decisions that need no AppKit or CEF, with tests that run without vendor/cef.
    dependencies: [.package(path: "Packages/CraCore")],
    targets: [
        .executableTarget(name: "CraPluginHost", path: "Sources/CraPluginHost",
                          linkerSettings: [.linkedFramework("JavaScriptCore")]),
    ] + (chromiumEngine ? [
        // The bridge lives in Chrome's framework (engine/chromium/cra/bridge.mm); this target is its header.
        .target(
            name: "CraCEF",
            path: "Sources/CraCEF",
            exclude: ["CraCEF.mm", "CraContentBlocker.h"],
            sources: ["ChromiumEngine.m"],
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-F", engineFrameworks, "-Xlinker", "-needed_framework", "-Xlinker", "Chromium Framework"]),
                .linkedFramework("AppKit"),
            ]
        ),
    ] : [
        // Objective-C++ bridge between Swift and CEF.
        .target(
            name: "CraCEF",
            path: "Sources/CraCEF",
            exclude: ["ChromiumEngine.m"],
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(cefCXXFlags + ["-fobjc-arc"])],
            linkerSettings: [
                // Cra links the framework at launch, like the helpers (Sources/CraHelper/main.cc).
                .unsafeFlags(cefLinkerFlags + ["-F", "\(cefRoot)/Release", "-Xlinker", "-needed_framework",
                                               "-Xlinker", "Chromium Embedded Framework"]),
                .linkedLibrary("cef_dll_wrapper"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
            ]
        ),
        // Subprocess executable (renderer, GPU, utility...). Bundled five
        // times as "Cra Helper*.app" inside Cra.app/Contents/Frameworks.
        .executableTarget(
            name: "CraHelper",
            path: "Sources/CraHelper",
            exclude: ["ChromiumEmbeddedFramework.tbd"],
            cxxSettings: [.unsafeFlags(cefCXXFlags)],
            linkerSettings: [
                // The framework is a launch-time dependency, not a dlopen (main.cc says why).
                .unsafeFlags(cefLinkerFlags + ["-Xlinker", "-needed_library", "-Xlinker",
                    "\(Context.packageDirectory)/Sources/CraHelper/ChromiumEmbeddedFramework.tbd"]),
                .linkedLibrary("cef_dll_wrapper"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
            ]
        ),
    ]) + [
        // Dock tile plug-in: keeps the icon picked in Settings after Cra quits.
        .target(
            name: "CraDockTile",
            path: "Sources/CraDockTile",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        // The browser itself: AppKit window, SwiftUI sidebar and command bar.
        .executableTarget(
            name: "Cra",
            dependencies: ["CraCEF", .product(name: "CraCore", package: "CraCore")],
            path: "Sources/Cra",
            swiftSettings: [.unsafeFlags(["-F", sparkleRoot]), .unsafeFlags(["-Onone"], .when(configuration: .debug))],
            linkerSettings: [.unsafeFlags(["-F", sparkleRoot, "-framework", "Sparkle",
                                           "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx20
)
