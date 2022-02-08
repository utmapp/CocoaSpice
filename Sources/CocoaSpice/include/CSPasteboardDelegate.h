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

/// Supported pasteboard types
typedef NS_ENUM(NSInteger, CSPasteboardType) {
    kCSPasteboardTypeURL = 0,
    kCSPasteboardTypeBmp = 1,
    kCSPasteboardTypeFileURL = 2,
    kCSPasteboardTypeFont = 3,
    kCSPasteboardTypeHtml = 4,
    kCSPasteboardTypeJpg = 5,
    kCSPasteboardTypePdf = 6,
    kCSPasteboardTypePng = 7,
    kCSPasteboardTypeRtf = 8,
    kCSPasteboardTypeRtfd = 9,
    kCSPasteboardTypeSound = 10,
    kCSPasteboardTypeString = 11,
    kCSPasteboardTypeTabularText = 12,
    kCSPasteboardTypeTiff = 13,
};

/// Notification posted when pasteboard changes
extern const NSNotificationName _Nonnull CSPasteboardChangedNotification;

/// Notification posted when an item is removed from the pasteboard
extern const NSNotificationName _Nonnull CSPasteboardRemovedNotification;

NS_ASSUME_NONNULL_BEGIN

/// Platform agnostic way to handle pasteboard events
/// @related CSSession
@protocol CSPasteboardDelegate <NSObject>

/// Check if system supports reading pasteboard type
/// @param type Pasteboard type
/// @return true if type is supported
- (BOOL)canReadItemForType:(CSPasteboardType)type;

/// Get pasteboard data from system
/// @param type Pasteboard type
- (NSData *)dataForType:(CSPasteboardType)type;

/// Sets pasteboard data in system
/// @param data Pasteboard data
/// @param type Pasteboard type
- (void)setData:(NSData *)data forType:(CSPasteboardType)type;

/// Gets a string type pasteboard item from system
- (NSString *)string;

/// Sets a string type pasteboard item to system
/// @param string Pasteboard data
- (void)setString:(NSString *)string;

/// Clears the pasteboard
- (void)clearContents;

@end

NS_ASSUME_NONNULL_END
