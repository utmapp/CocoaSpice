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
#import "CSChannel.h"
@import CoreGraphics;
@import CocoaSpiceRenderer;

@class CSCursor;
@class CSScreenshot;

NS_ASSUME_NONNULL_BEGIN

/// Handles display rendering and resolution
///
/// This implements the `CSRenderSource` protocol which can be used to render to a Metal device.
/// Note: multiple monitors on a single display channel is not supported.
@interface CSDisplay : CSChannel <CSRenderSource>

/// The current size of the display.
/// You can add an observer on this property to detect when the display resolution changes.
@property (nonatomic, readonly) CGSize displaySize;

/// This converts the current display state to an image for saving.
/// Do NOT use this to render the display as it is slow and inefficient.
@property (nonatomic, readonly) CSScreenshot *screenshot;

/// Only true for one display in the system.
/// If the caller supports only rendering a single display, it should be this one.
@property (nonatomic, readonly) BOOL isPrimaryDisplay;

/// If a cursor channel is available, this represents the render source for the cursor
@property (nonatomic, nullable, weak, readonly) CSCursor *cursor;

- (instancetype)init NS_UNAVAILABLE;

/// Request a new screen resolution from SPICE guest agent
///
/// Does nothing is the guest agent is not installed. If successful, `displaySize` will be updated.
/// @param bounds The requested display bounds
- (void)requestResolution:(CGRect)bounds;

@end

NS_ASSUME_NONNULL_END
