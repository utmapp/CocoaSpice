# CocoaSpice

CocoaSpice brings native Cocoa bindings to [SPICE GTK][1] and is used to build SPICE clients for macOS and iOS.

## Features

* Renders displays and cursor into Metal textures
* Support copy/paste through custom pasteboard binding
* TCP socket connections and Unix socket file
* Cursor and scroll-wheel channel
* Take screenshot of current display
* USB sharing and enumeration

## Usage

1. Add this repository to your project through Xcode: File -> Add Packages...
2. Link your target with: `libglib-2.0`, `libgstreamer-1.0`, `libusb-1.0` (optional), `libspice-client-glib-2.0`.
3. Either add target `CocoaSpiceNoUsb` or `CocoaSpice` to your dependencies. 

### Start SPICE GTK

You must do this before using any other API. This starts a worker thread for SPICE GTK.

```swift
import CocoaSwift

guard CSMain.shared.spiceStart() else {
    // handle worker failed to start
    ...
}

defer {
    // use this to stop and clean up worker 
    CSMain.shared.spiceStop()
}
```

### Open a connection

`CSConnection` is the main interface to CocoaSpice. You can create a connection from TCP (shown below) or with a Unix socket file.

```swift
import CocoaSwift

let connection = CSConnection(host: "127.0.0.1", port: "4444")
connection.delegate = yourConnectionDelegate;
guard connection.connect() else {
    // handle connection failed to be created
    ...
}
```

CocoaSpice follows the delegate model so connection events are handled through delegate methods. Implement the `CSConnectionDelegate` to be informed to SPICE client events.

## Testing

TODO: Implement testing

[1]: https://gitlab.freedesktop.org/spice/spice-gtk
