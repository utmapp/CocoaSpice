//
// Copyright © 2022 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "CSUSBDevice.h"

typedef struct _SpiceUsbDevice SpiceUsbDevice;

NS_ASSUME_NONNULL_BEGIN

@interface CSUSBDevice ()

/// SPICE GTK usb device
@property (nonatomic, readonly) SpiceUsbDevice *device;

/// Create a new USB device from a SPICE USB device
/// @param device SPICE USB device
+ (instancetype)usbDeviceWithDevice:(SpiceUsbDevice *)device;

- (instancetype)init NS_UNAVAILABLE;

/// Create a new USB device from a SPICE USB device
/// @param device SPICE USB device
- (instancetype)initWithDevice:(SpiceUsbDevice *)device;

@end

NS_ASSUME_NONNULL_END
