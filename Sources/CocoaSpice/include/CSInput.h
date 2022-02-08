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
@import CoreGraphics;

/// Sends a key press or release
typedef NS_ENUM(NSInteger, CSInputKey) {
    /// Sends a key press
    kCSInputKeyPress,
    
    /// Sends a key release
    kCSInputKeyRelease
};

/// Sends one or more mouse button press
typedef NS_OPTIONS(NSUInteger, CSInputButton) {
    /// No mouse button
    kCSInputButtonNone = 0,
    
    /// Left mouse button
    kCSInputButtonLeft = (1 << 0),
    
    /// Middle mouse button
    kCSInputButtonMiddle = (1 << 1),
    
    /// Right mouse button
    kCSInputButtonRight = (1 << 2)
};

/// Sends a mouse scroll
typedef NS_ENUM(NSInteger, CSInputScroll) {
    /// Scroll up one unit
    kCSInputScrollUp,
    
    /// Scroll down one unit
    kCSInputScrollDown,
    
    /// Scroll an arbitary amount of positive or negative units
    kCSInputScrollSmooth
};

NS_ASSUME_NONNULL_BEGIN

/// Handles keyboard and mouse input
@interface CSInput : NSObject

/// If true, mouse events are handled as relative. Otherwise, they are handled as absolute positions.
/// Observers are not supported on this property.
@property (nonatomic, readonly, assign) BOOL serverModeCursor;

/// If true, all input handling are ignored
@property (nonatomic, assign) BOOL disableInputs;

/// Sends a single keyboard event
///
/// If an extended scancode is required (masked with 0xE000), it needs to be masked with 0x100 instead
/// @code if ((scancode & 0xFF00) == 0xE000) {
///     scancode = 0x100 | (scancode & 0xFF);
/// } @endcode
/// @param type Event type
/// @param scancode PC XT (set 1) scancode
- (void)sendKey:(CSInputKey)type code:(int)scancode;

/// Sends a single pause key event
///
/// This key event is special and requires a special handler.
/// @param type Event type
- (void)sendPause:(CSInputKey)type;

/// Reset key state by making sure all keys in pressed state are released
- (void)releaseKeys;

/// Sends a mouse movement event
///
/// This sends either a relative movement or absolute movement depending on `serverModeCursor`.
/// If `serverModeCursor` is true, then `point` is relative to the current position.
/// If `serverModeCursor` is false, then `point` is an absolute position in the primary display.
/// @param button Mask of mouse buttons pressed
/// @param point Either a relative position or an absolute position (see above)
- (void)sendMouseMotion:(CSInputButton)button point:(CGPoint)point;

/// Sends a mouse movement event
///
/// This sends either a relative movement or absolute movement depending on `serverModeCursor`.
/// If `serverModeCursor` is true, then `point` is relative to the current position.
/// If `serverModeCursor` is false, then `point` is an absolute position in the specified monitor.
/// @param button Mask of mouse buttons pressed
/// @param point Either a relative position or an absolute position (see above)
/// @param monitorID Monitor where the mouse event is sent to
- (void)sendMouseMotion:(CSInputButton)button point:(CGPoint)point forMonitorID:(NSInteger)monitorID;

/// Sends a mouse scroll event
/// @param type Scroll event type
/// @param button Mask of mouse buttons pressed
/// @param dy If `type` is `kCSInputScrollSmooth` then this is a positive or negative amount to scroll. Otherwise it is ignored.
- (void)sendMouseScroll:(CSInputScroll)type button:(CSInputButton)button dy:(CGFloat)dy;

/// Sends a mouse button without moving the mouse
/// @param button Mask of mouse buttons
/// @param pressed Pressed or released
- (void)sendMouseButton:(CSInputButton)button pressed:(BOOL)pressed;

/// Request change to absolute or relative positioning for mouse events
///
/// This is a request to the SPICE server. If the request is accepted, then `serverModeCursor` will change.
/// @param server If true, then request relative positioning. If false, then request absolute positioning.
- (void)requestMouseMode:(BOOL)server;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
