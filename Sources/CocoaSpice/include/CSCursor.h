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

#import "CSChannel.h"
@import CocoaSpiceRenderer;

@class CSDisplay;

NS_ASSUME_NONNULL_BEGIN

/// Handles cursor rendering
///
/// This implements the `CSRenderSource` protocol which can be used to render to a Metal device.
@interface CSCursor : CSChannel <CSRenderSource>

/// The current size of a client side cursor if supported. (0, 0) is returned otherwise.
/// You can add an observer on this property to detect when the cursor size changes.
@property (nonatomic, readonly) CGSize cursorSize;

/// Set this to true to not render the cursor only if client side cusor rendering is supported.
/// If it is not supported, this will do nothing.
@property (nonatomic, assign) BOOL isInhibited;

/// Cursor is visible if it is not inhibited (by the host) and is not hidden (by the guest) and is drawn (by the guest)
@property (nonatomic, readonly) BOOL isVisible;

- (instancetype)init NS_UNAVAILABLE;

/// Set the cursor to a new location (only appliable if client side cursor rendering is in use)
/// @param point Point relative to the display
- (void)moveTo:(CGPoint)point NS_SWIFT_NAME(move(to:));

@end

NS_ASSUME_NONNULL_END
