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

@import simd;
@import MetalKit;

#import "CSMetalRenderer.h"
#import "CSRenderSource.h"
#import "CSRenderer.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
#import "CSShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

/// Helper class to retain fields from a renderer source
@interface _CSRendererSourceData : NSObject<CSRenderSource>

@property (nonatomic, readonly) CGPoint viewportOrigin;
@property (nonatomic, readonly) CGFloat viewportScale;
@property (nonatomic, readonly) id<MTLBuffer> vertices;
@property (nonatomic, readonly) NSUInteger numVertices;
@property (nonatomic, readonly) id<MTLTexture> texture;
@property (nonatomic, readonly) BOOL hasAlpha;
@property (nonatomic, readonly) BOOL isInverted;
@property (nonatomic, readonly) BOOL isVisible;
@property (nonatomic, strong, readonly) _CSRendererSourceData *cursorSource;
@property (nonatomic, nullable, readonly) completionCallback_t completion;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource device:(id<MTLDevice>)device completion:(nullable completionCallback_t)completion;
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource atOffset:(CGPoint)offset device:(id<MTLDevice>)device completion:(nullable completionCallback_t)completion NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END

@implementation _CSRendererSourceData

/// Retain a copy of the render source data
/// - Parameter renderSource: Render source to read from
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource completion:(nullable completionCallback_t)completion {
    return [self initWithRenderSource:renderSource atOffset:CGPointZero completion:completion];
}

/// Retain a copy of the render source data
/// - Parameters:
///   - renderSource: Render source to read from
///   - offset: Offset to add to `viewportOrigin`, can be zero
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource atOffset:(CGPoint)offset completion:(nullable completionCallback_t)completion {
    id<CSRenderSource> cursorSource = renderSource.cursorSource;
    if (self = [super init]) {
        _viewportOrigin = CGPointMake(renderSource.viewportOrigin.x +
                                      offset.x,
                                      renderSource.viewportOrigin.y +
                                      offset.y);
        _viewportScale = renderSource.viewportScale;
        _vertices = renderSource.vertices;
        _numVertices = renderSource.numVertices;
        _texture = renderSource.texture;
        _hasAlpha = renderSource.hasAlpha;
        _isInverted = renderSource.isInverted;
        _isVisible = renderSource.isVisible;
        _completion = completion;
        if (!_vertices || !_texture) {
            return nil;
        }
        if (cursorSource) {
            _cursorSource = [[_CSRendererSourceData alloc] initWithRenderSource:cursorSource
                                                                       atOffset:renderSource.viewportOrigin
                                                                     completion:nil];
        }
    }
    return self;
}

@end

@interface CSMetalRenderer ()

@property (nonatomic, nullable) const _CSRendererSourceData *renderSourceData;
@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic) id<MTLSamplerState> sampler;

@end

// Main class performing the rendering
@implementation CSMetalRenderer
{
    // The device (aka GPU) we're using to render
    id<MTLDevice> _device;

    // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
    id<MTLRenderPipelineState> _pipelineState;

    // The command Queue from which we'll obtain command buffers
    id<MTLCommandQueue> _commandQueue;
}

@synthesize device = _device;

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error = NULL;
        
        _device = mtkView.device;
        [self setViewportCGSize:mtkView.drawableSize];

        /// Create our render pipeline
        
        // Load all the shader files with a .metal file extension in the project
        // FIXME: on Swift we have `Bundle.module` generated by SPM but it doesn't appear to be the case for Obj-C
        NSURL *modulePath = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"CocoaSpice_CocoaSpiceRenderer.bundle"];
        NSBundle *bundle = [NSBundle bundleWithURL:modulePath];
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibraryWithBundle:bundle error:&error];
        NSAssert(defaultLibrary, @"Failed to get library from bundle: %@", error);

        // Load the vertex function from the library
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

        // Load the fragment function from the library
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];

        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Renderer Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat;
        pipelineStateDescriptor.vertexBuffers[CSRenderVertexInputIndexVertices].mutability = MTLMutabilityImmutable;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
        NSAssert(_pipelineState, @"Failed to create pipeline state to render to texture: %@", error);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];

        // Sampler
        [self _initializeUpscaler:MTLSamplerMinMagFilterLinear downscaler:MTLSamplerMinMagFilterLinear];
    }

    return self;
}

- (void)_initializeUpscaler:(MTLSamplerMinMagFilter)upscaler downscaler:(MTLSamplerMinMagFilter)downscaler {
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    samplerDescriptor.minFilter = downscaler;
    samplerDescriptor.magFilter = upscaler;

    _sampler = [_device newSamplerStateWithDescriptor:samplerDescriptor];
}

/// Scalers from VM settings
- (void)changeUpscaler:(MTLSamplerMinMagFilter)upscaler downscaler:(MTLSamplerMinMagFilter)downscaler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _initializeUpscaler:upscaler downscaler:downscaler];
    });
}

- (void)setViewportCGSize:(CGSize)size {
    vector_uint2 viewportSize;

    viewportSize.x = size.width;
    viewportSize.y = size.height;
    self.viewportSize = viewportSize;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    [self setViewportCGSize:size];
}

/// Create a translation+scale matrix
static matrix_float4x4 matrix_scale_translate(CGFloat scale, CGPoint translate)
{
    matrix_float4x4 m = {
        .columns[0] = {
            scale,
            0,
            0,
            0
        },
        .columns[1] = {
            0,
            scale,
            0,
            0
        },
        .columns[2] = {
            0,
            0,
            1,
            0
        },
        .columns[3] = {
            translate.x,
            -translate.y, // y flipped
            0,
            1
        }
        
    };
    return m;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> currentDrawable = view.currentDrawable;

    if (renderPassDescriptor == nil || currentDrawable == nil) {
        return;
    }

    const _CSRendererSourceData *sourceData = self.renderSourceData;
    vector_uint2 viewportSize = self.viewportSize;
    id<MTLSamplerState> sampler = self.sampler;

    // clear buffer
    self.renderSourceData = nil;

    if (!sourceData.isVisible) {
        if (sourceData.completion) {
            sourceData.completion();
        }
        return;
    }

    // synchronize with rendererQueue in order to access currentCommandBuffer
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Draw Frame";

    [self _renderCommand:commandBuffer
              drawSource:sourceData
            viewportSize:viewportSize
                 sampler:sampler
    renderPassDescriptor:renderPassDescriptor];

    [commandBuffer presentDrawable:currentDrawable];

    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
        if (sourceData.completion) {
            sourceData.completion();
        }
    }];

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

- (id<CSRenderSource>)renderSouce:(id<CSRenderSource>)renderSource
                       copyBuffer:(id<MTLBuffer>)sourceBuffer
                           region:(MTLRegion)region
                     sourceOffset:(NSUInteger)sourceOffset
                sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
                       completion:(nullable completionCallback_t)completion {

    _CSRendererSourceData *sourceData = [[_CSRendererSourceData alloc] initWithRenderSource:renderSource
                                                                                 completion:completion];

    if (!sourceData) {
        if (completion) {
            completion();
        }
        return nil;
    }

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Blit Command Buffer";
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    blitEncoder.label = @"Renderer Canvas Updates";

    [blitEncoder copyFromBuffer:sourceBuffer
                   sourceOffset:sourceOffset
              sourceBytesPerRow:sourceBytesPerRow
            sourceBytesPerImage:0
                     sourceSize:region.size
                      toTexture:sourceData.texture
               destinationSlice:0
               destinationLevel:0
              destinationOrigin:region.origin];

    [blitEncoder endEncoding];

    [commandBuffer commit];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.renderSourceData.completion) {
            self.renderSourceData.completion();
        }
        self.renderSourceData = sourceData;
    });

    return sourceData;
}

- (id<CSRenderSource>)invalidateRenderSource:(id<CSRenderSource>)renderSource {
    return [self invalidateRenderSource:renderSource withCompletion:^{}];
}

- (id<CSRenderSource>)invalidateRenderSource:(id<CSRenderSource>)renderSource
                              withCompletion:(nullable completionCallback_t)completion {
    _CSRendererSourceData *sourceData = [[_CSRendererSourceData alloc] initWithRenderSource:renderSource
                                                                                 completion:completion];
    if (!sourceData || !sourceData.isVisible) {
        if (completion) {
            completion();
        }
        return nil;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.renderSourceData.completion) {
            self.renderSourceData.completion();
        }
        self.renderSourceData = sourceData;
    });

    return sourceData;
}

- (BOOL)_renderCommand:(id<MTLCommandBuffer>)commandBuffer
            drawSource:(id<CSRenderSource>)source
          viewportSize:(vector_uint2)viewportSize
               sampler:(id<MTLSamplerState>)sampler
  renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"View Presentation";

    [renderEncoder setRenderPipelineState:_pipelineState];

    NSAssert(source.isVisible, @"Screen should be visible at this point!");

    [self _renderEncoder:renderEncoder
            drawAtOrigin:source.viewportOrigin
                   scale:source.viewportScale
                vertices:source.vertices
            numVerticies:source.numVertices
                hasAlpha:source.hasAlpha
              isInverted:source.isInverted
                 texture:source.texture
            viewportSize:viewportSize
                 sampler:sampler];

    // Draw cursor
    if (source.cursorSource.isVisible) {
        // Next render the cursor
        [self _renderEncoder:renderEncoder
                drawAtOrigin:source.cursorSource.viewportOrigin
                       scale:source.cursorSource.viewportScale
                    vertices:source.cursorSource.vertices
                numVerticies:source.cursorSource.numVertices
                    hasAlpha:source.cursorSource.hasAlpha
                  isInverted:source.cursorSource.isInverted
                     texture:source.cursorSource.texture
                viewportSize:viewportSize
                     sampler:sampler];
    }

    [renderEncoder endEncoding];
}

- (void)_renderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
          drawAtOrigin:(CGPoint)origin
                 scale:(CGFloat)scale
              vertices:(id<MTLBuffer>)vertices
          numVerticies:(NSUInteger)numVerticies
              hasAlpha:(BOOL)hasAlpha
            isInverted:(BOOL)isInverted
               texture:(id<MTLTexture>)texture
          viewportSize:(vector_uint2)viewportSize
               sampler:(id<MTLSamplerState>)sampler {
    matrix_float4x4 transform = matrix_scale_translate(scale,
                                                       origin);

    [renderEncoder setVertexBuffer:vertices
                            offset:0
                          atIndex:CSRenderVertexInputIndexVertices];

    [renderEncoder setVertexBytes:&viewportSize
                           length:sizeof(viewportSize)
                          atIndex:CSRenderVertexInputIndexViewportSize];

    [renderEncoder setVertexBytes:&transform
                           length:sizeof(transform)
                          atIndex:CSRenderVertexInputIndexTransform];

    [renderEncoder setVertexBytes:&hasAlpha
                           length:sizeof(hasAlpha)
                          atIndex:CSRenderVertexInputIndexHasAlpha];
    
    // Set the texture object.  The CSRenderTextureIndexBaseColor enum value corresponds
    ///  to the 'colorMap' argument in our 'samplingShader' function because its
    //   texture attribute qualifier also uses CSRenderTextureIndexBaseColor for its index
    [renderEncoder setFragmentTexture:texture
                              atIndex:CSRenderTextureIndexBaseColor];
    
    [renderEncoder setFragmentSamplerState:sampler
                                   atIndex:CSRenderSamplerIndexTexture];
    
    [renderEncoder setFragmentBytes:&isInverted
                             length:sizeof(isInverted)
                            atIndex:CSRenderFragmentBufferIndexIsInverted];

    // Draw the vertices of our triangles
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:numVerticies];
}

@end
