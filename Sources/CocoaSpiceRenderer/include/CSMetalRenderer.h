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
@protocol CSRenderer;

NS_ASSUME_NONNULL_BEGIN

/// Simple platform independent renderer for CocoaSpice
@interface CSMetalRenderer : NSObject<MTKViewDelegate, CSRenderer>

/// If true, then for canvas based operations, the blit will be done from the GPU. Otherwise, it will be done from the CPU.
@property (nonatomic) BOOL isBlitOnGpu;

/// Create a new renderer for a MTKView
/// @param mtkView The MetalKit View
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView;

/// Modify upscaler and downscaler settings
/// @param upscaler Upscaler to use
/// @param downscaler Downscaler to use
- (void)changeUpscaler:(MTLSamplerMinMagFilter)upscaler downscaler:(MTLSamplerMinMagFilter)downscaler;

@end

NS_ASSUME_NONNULL_END
