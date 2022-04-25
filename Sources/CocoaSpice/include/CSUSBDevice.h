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

NS_ASSUME_NONNULL_BEGIN

/// Represents a single USB device
///
/// This is instantiated and used by `CSUSBManager`.
@interface CSUSBDevice : NSObject

/// A user-readable description of the device
@property (nonatomic, nullable, readonly) NSString *name;

/// USB manufacturer if available
@property (nonatomic, nullable, readonly) NSString *usbManufacturerName;

/// USB product if available
@property (nonatomic, nullable, readonly) NSString *usbProductName;

/// USB vendor ID
@property (nonatomic, readonly) NSInteger usbVendorId;

/// USB product ID
@property (nonatomic, readonly) NSInteger usbProductId;

/// USB bus number
@property (nonatomic, readonly) NSInteger usbBusNumber;

/// USB port number
@property (nonatomic, readonly) NSInteger usbPortNumber;

- (instancetype)init NS_UNAVAILABLE;

/// Compare two USB devices
///
/// The following are checked to be considered the same device
///
/// 1. USB manufacturer
/// 2. USB product
/// 3. USB vendor id and product id
/// 4. USB bus number
/// 5. USB address
///
/// @param usbDevice Other device
/// @returns true if `usbDevice` is equal to this one
- (BOOL)isEqualToUSBDevice:(CSUSBDevice *)usbDevice;

@end

NS_ASSUME_NONNULL_END
