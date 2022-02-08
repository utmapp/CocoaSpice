// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "CocoaSpice",
    platforms: [
        .iOS(.v11), .macOS(.v11)
    ],
    products: [
        .library(
            name: "CocoaSpice",
            targets: ["CocoaSpice"]),
    ],
    targets: [
        .target(
            name: "CocoaSpiceRenderer",
            dependencies: []),
        .target(
            name: "CocoaSpice",
            dependencies: ["CocoaSpiceRenderer"],
            exclude: ["ExternalHeaders"],
            cSettings: [
                .define("WITH_USB_SUPPORT"),
                .headerSearchPath("ExternalHeaders"),
                .headerSearchPath("ExternalHeaders/glib-2.0"),
                .headerSearchPath("ExternalHeaders/gstreamer-1.0"),
                .headerSearchPath("ExternalHeaders/libusb-1.0"),
                .headerSearchPath("ExternalHeaders/spice-1"),
                .headerSearchPath("ExternalHeaders/spice-client-glib-2.0")]),
        .target(
            name: "CocoaSpiceNoUsb",
            dependencies: ["CocoaSpiceRenderer"],
            exclude: [
                "ExternalHeaders",
                "CSUSBDevice.m",
                "CSUSBManager.m"],
            cSettings: [
                .headerSearchPath("ExternalHeaders"),
                .headerSearchPath("ExternalHeaders/glib-2.0"),
                .headerSearchPath("ExternalHeaders/gstreamer-1.0"),
                .headerSearchPath("ExternalHeaders/spice-1"),
                .headerSearchPath("ExternalHeaders/spice-client-glib-2.0")]),
        .testTarget(
            name: "CocoaSpiceTests",
            dependencies: ["CocoaSpice"],
            linkerSettings: [
                .linkedLibrary("glib-2.0"),
                .linkedLibrary("gstreamer-1.0"),
                .linkedLibrary("usb-1.0"),
                .linkedLibrary("spice-client-glib-2.0")]),
    ]
)
