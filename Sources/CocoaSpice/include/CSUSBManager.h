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
#import "CSUSBManagerDelegate.h"

/// Completion handler for connect and disconnect calls
typedef void (^CSUSBManagerConnectionCallback)(BOOL, NSString * _Nullable);

NS_ASSUME_NONNULL_BEGIN

/// Handles USB forwarding
@interface CSUSBManager : NSObject

/// Set by caller to handle USB events
/// @related CSUSBManagerDelegate
@property (nonatomic, weak, nullable) id<CSUSBManagerDelegate> delegate;

/// Set to true to enable auto connect of detected USB devices to this session
/// Note that `autoConnectFilter` determines what devices are auto-connected and
/// `isRedirectOnConnect` determines if the device should be attached to the host.
@property (nonatomic) BOOL isAutoConnect;

/// Filter string for auto-connect
///
/// Set a string specifying a filter to use to determine which USB devices
/// to autoconnect when plugged in, a filter consists of one or more rules.
/// Where each rule has the form of:
///
/// \@class,@vendor,@product,@version,@allow
///
/// Use -1 for @class/@vendor/@product/@version to accept any value.
///
/// And the rules themselves are concatenated like this:
///
/// @rule1|@rule2|@rule3
///
/// The default setting filters out HID (class 0x03) USB devices from auto
/// connect and auto connects anything else. Note the explicit allow rule at
/// the end, this is necessary since by default all devices without a
/// matching filter rule will not auto-connect.
///
/// Filter strings in this format can be easily created with the RHEV-M
/// USB filter editor tool.
@property (nonatomic) NSString *autoConnectFilter;

/// Automatically attach connected device to host
@property (nonatomic) BOOL isRedirectOnConnect;

/// Number of free SPICE channels for USB redirection
@property (nonatomic, readonly) NSInteger numberFreeChannels;

/// List of USB devices currently connected locally
@property (nonatomic, readonly) NSArray<CSUSBDevice *> *usbDevices;

/// If true, SPICE is currently processing a device
@property (nonatomic, readonly) BOOL isBusy;

- (instancetype)init NS_UNAVAILABLE;

/// Check if redirection is supported on a USB device
/// @param usbDevice USB device
/// @param errorMessage An optional detailed reason (in English) for why redirection is unsupported
/// @returns true if redirection is supported, false otherwise and `errorMessage` may or may not be populated
- (BOOL)canRedirectUsbDevice:(CSUSBDevice *)usbDevice errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

/// Check if this device is already being redirected
///
/// It can be connected to this session or another session.
/// @param usbDevice USB device
/// @returns true if this device is connected to any SPICE session
- (BOOL)isUsbDeviceConnected:(CSUSBDevice *)usbDevice;

/// Forward USB device to host
/// @param usbDevice USB device
/// @param completion Handler to run on completion (success or failure)
- (void)connectUsbDevice:(CSUSBDevice *)usbDevice withCompletion:(CSUSBManagerConnectionCallback)completion;

/// Stop USB forwarding
/// @param usbDevice USB device
/// @param completion Handler to run on completion (success or failure)
- (void)disconnectUsbDevice:(CSUSBDevice *)usbDevice withCompletion:(CSUSBManagerConnectionCallback)completion;

@end

NS_ASSUME_NONNULL_END
