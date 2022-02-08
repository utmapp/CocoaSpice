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

#import <Foundation/Foundation.h>

@class CSUSBDevice;
@class CSUSBManager;

NS_ASSUME_NONNULL_BEGIN

/// Implement this protocol to handle `CSUSBManager` events
@protocol CSUSBManagerDelegate <NSObject>

/// Called when a connected device has errored
/// @param usbManager USB manager for this session
/// @param error Details of the error (in English)
/// @param device Device that errored
- (void)spiceUsbManager:(CSUSBManager *)usbManager deviceError:(NSString *)error forDevice:(CSUSBDevice *)device;

/// Called when a local USB device is attached
/// @param usbManager USB manager for this session
/// @param device Device that is attached
- (void)spiceUsbManager:(CSUSBManager *)usbManager deviceAttached:(CSUSBDevice *)device;

/// Called when a local USB device is removed
///
/// Note that the USB manager has already disconnected this device and the caller does not need to do it.
/// @param usbManager USB manager for this session
/// @param device Device that is removed
- (void)spiceUsbManager:(CSUSBManager *)usbManager deviceRemoved:(CSUSBDevice *)device;

@end

NS_ASSUME_NONNULL_END
