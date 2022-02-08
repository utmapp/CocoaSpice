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
@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

/// Shared context between renderer and CocoaSpice
@protocol CSRenderSource <NSObject>

/// If true, the `cursorTexture` is valid and should be used. Otherwise, `cursorTexture` should be disregarded
@property (nonatomic, readonly) BOOL cursorVisible;

/// Location of the cursor relative to `viewportOrigin`
@property (nonatomic, readonly) CGPoint cursorOrigin;

/// Set by the caller to the offset in the render surface where the display will be drawn to
@property (nonatomic) CGPoint viewportOrigin;

/// Set by the caller to a scale factor of the display that is drawn
@property (nonatomic) CGFloat viewportScale;

/// Set by the caller to the Metal device used for rendering
@property (nonatomic, nullable) id<MTLDevice> device;

/// Contains the texture where the display is rendered to
/// This property should be queried each time a frame is drawn
@property (nonatomic, nullable, readonly) id<MTLTexture> displayTexture;

/// Contains the texture where the cursor is rendered to (valid when `cursorVisible` is true
/// This property should be queried each time a frame is drawn
@property (nonatomic, nullable, readonly) id<MTLTexture> cursorTexture;

/// Contains the number of verticies to render `displayTexture` to a rectangle
@property (nonatomic, readonly) NSUInteger displayNumVertices;

/// Contains the number of verticies to render `cursorTexture` to a rectangle
@property (nonatomic, readonly) NSUInteger cursorNumVertices;

/// Contains the verticies data for the display rectangle
@property (nonatomic, nullable, readonly) id<MTLBuffer> displayVertices;

/// Contains the verticies data for the cursor rectangle
@property (nonatomic, nullable, readonly) id<MTLBuffer> cursorVertices;

/// If true, then the `cursorTexture` should be flipped and reflected relative to `displayTexture`
@property (nonatomic, readonly) BOOL cursorInverted;

/// Callback made by the renderer to indicate that a single frame has been rendered
- (void)rendererFrameHasRendered;

@end

NS_ASSUME_NONNULL_END
