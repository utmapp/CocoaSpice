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

@protocol CSRenderSource;

NS_ASSUME_NONNULL_BEGIN

typedef void (^drawCompletionCallback_t)(BOOL success);

@protocol CSRenderSourceDelegate <NSObject>

/// Update the existing texture with pixel data and then render it to the back buffer
/// - Parameters:
///   - renderSource: Source to render
///   - sourceBuffer: Buffer to draw to the source texture
///   - region: Region in the source texture to draw to
///   - sourceOffset: Offset in the source buffer to copy from
///   - sourceBytesPerRow: Stride of the source buffer
///   - completion: Block to run after the texture is rendered to the back buffer
- (void)renderSouce:(id<CSRenderSource>)renderSource copyAndDrawWithBuffer:(id<MTLBuffer>)sourceBuffer
             region:(MTLRegion)region
       sourceOffset:(NSUInteger)sourceOffset
  sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
         completion:(drawCompletionCallback_t)completion;

/// Render an existing texture to the back buffer
///
/// Source must be visible!
/// - Parameters:
///   - renderSource: Source to render
///   - completion: Block to run after the texture is rendered to the back buffer
- (void)renderSource:(id<CSRenderSource>)renderSource drawWithCompletion:(drawCompletionCallback_t)completion;

/// Render an existing texture to the back buffer without callback
/// - Parameters:
///   - renderSource: Source to render
- (void)drawRenderSource:(id<CSRenderSource>)renderSource;

@end

NS_ASSUME_NONNULL_END
