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

@import MetalKit;
@import CoreGraphics;

@protocol CSRenderSource;
@protocol CSRenderSourceDelegate;

NS_ASSUME_NONNULL_BEGIN

/// Simple platform independent renderer for CocoaSpice
@interface CSRenderer : NSObject<MTKViewDelegate, CSRenderSourceDelegate>

/// Render source (comes from `CSDisplay`)
@property (nonatomic, weak, nullable) id<CSRenderSource> source;

/// Attempt to draw at the FPS
/// If in manual draw mode, a 0 indicates no frame pacing and any other number will attempt to align rendering to it
/// If in automatic draw mode, a 0 is ignored and any other number will set the timer for draw intervals
@property (nonatomic) NSInteger preferredFramesPerSecond API_AVAILABLE(macos(10.15.4), ios(10.3), macCatalyst(13.4));

/// Create a new renderer for a MTKView
/// @param mtkView The MetalKit View
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;

/// Modify upscaler and downscaler settings
/// @param upscaler Upscaler to use
/// @param downscaler Downscaler to use
- (void)changeUpscaler:(MTLSamplerMinMagFilter)upscaler downscaler:(MTLSamplerMinMagFilter)downscaler;

@end

NS_ASSUME_NONNULL_END
