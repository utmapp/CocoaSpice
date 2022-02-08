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
            name: "CocoaSpice",
            dependencies: [],
            cSettings: [
                .define("WITH_USB_SUPPORT"),
                .headerSearchPath("../../Includes"),
                .headerSearchPath("../../Includes/glib-2.0"),
                .headerSearchPath("../../Includes/gstreamer-1.0"),
                .headerSearchPath("../../Includes/libusb-1.0"),
                .headerSearchPath("../../Includes/spice-1"),
                .headerSearchPath("../../Includes/spice-client-glib-2.0")]),
        .target(
            name: "CocoaSpiceNoUsb",
            dependencies: [],
            exclude: [
                "CSUSBDevice.m",
                "CSUSBManager.m"],
            cSettings: [
                .headerSearchPath("../../Includes"),
                .headerSearchPath("../../Includes/glib-2.0"),
                .headerSearchPath("../../Includes/gstreamer-1.0"),
                .headerSearchPath("../../Includes/spice-1"),
                .headerSearchPath("../../Includes/spice-client-glib-2.0")]),
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
