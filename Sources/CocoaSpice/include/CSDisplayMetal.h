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
#import "CSRenderSource.h"
@import CoreGraphics;

@class CSScreenshot;

NS_ASSUME_NONNULL_BEGIN

/// Handles display rendering and resolution
///
/// This implements the `CSRenderSource` protocol which can be used to render to a Metal device.
@interface CSDisplayMetal : NSObject <CSRenderSource>

/// The current size of the display.
/// You can add an observer on this property to detect when the display resolution changes.
/// FIXME: this should be readonly
@property (nonatomic, assign) CGSize displaySize;

/// This converts the current display state to an image for saving.
/// Do NOT use this to render the display as it is slow and inefficient.
@property (nonatomic, readonly) CSScreenshot *screenshot;

/// Set this to true to not render the cursor only if client side cusor rendering is supported.
/// If it is not supported, this will do nothing.
@property (nonatomic, assign) BOOL inhibitCursor;

/// The current size of a client side cursor if supported. (0, 0) is returned otherwise.
/// You can add an observer on this property to detect when the cursor size changes.
@property (nonatomic, readonly) CGSize cursorSize;

/// Only true for one display in the system.
/// If the caller supports only rendering a single display, it should be this one.
@property (nonatomic, readonly) BOOL isPrimaryDisplay;

- (instancetype)init NS_UNAVAILABLE;

/// Request a new screen resolution from SPICE guest agent
///
/// Does nothing is the guest agent is not installed. If successful, `displaySize` will be updated.
/// @param bounds The requested display bounds
- (void)requestResolution:(CGRect)bounds;

/// HACK to update the cursor on the client side without sending the coordinates to the server.
///
/// FIXME: this should be removed?
/// @param pos The new position
- (void)forceCursorPosition:(CGPoint)pos;

@end

NS_ASSUME_NONNULL_END
