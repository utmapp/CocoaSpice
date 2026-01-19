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

/// Shared context between renderer and CocoaSpice.
@protocol CSRenderSource <NSObject>

/// If true, this source should be rendered
@property (nonatomic, readonly) BOOL isVisible;

/// Set by the caller to the offset in the render surface where the display will be drawn to
@property (nonatomic, readonly) CGPoint offset;

/// Contains the texture where the source is rendered to
/// This property should be queried each time a frame is drawn
/// All access MUST be through the `rendererQueue`!
@property (nonatomic, nullable, readonly) id<MTLTexture> texture;

/// Contains the number of verticies to render `texture` to a rectangle
/// All access MUST be through the `rendererQueue`!
@property (nonatomic, readonly) NSUInteger numVertices;

/// Contains the verticies data for the rectangle
/// All access MUST be through the `rendererQueue`!
@property (nonatomic, nullable, readonly) id<MTLBuffer> vertices;

/// If true, then alpha channel will be blended
@property (nonatomic, readonly) BOOL hasAlpha;

/// If true, then the texture should be flipped and reflected
@property (nonatomic, readonly) BOOL isInverted;

/// Render a cursor overlaid onto this source
@property (nonatomic, readonly, weak) id<CSRenderSource> cursorSource;

@end

NS_ASSUME_NONNULL_END
