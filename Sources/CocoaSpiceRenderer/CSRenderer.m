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

#import "CSRenderer.h"
#import "CSRenderSource.h"
#import "CSRenderSourceDelegate.h"

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
@property (nonatomic, readonly) id<CSRenderSource> cursorSource;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource;
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource atOffset:(CGPoint)offset NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END

@implementation _CSRendererSourceData

// unused properties
@synthesize device;
@synthesize rendererDelegate;

/// Retain a copy of the render source data
/// - Parameter renderSource: Render source to read from
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource {
    return [self initWithRenderSource:renderSource atOffset:CGPointZero];
}

/// Retain a copy of the render source data
/// - Parameters:
///   - renderSource: Render source to read from
///   - offset: Offset to add to `viewportOrigin`, can be zero
- (nullable instancetype)initWithRenderSource:(id<CSRenderSource>)renderSource atOffset:(CGPoint)offset {
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
        if (!_vertices || !_texture) {
            return nil;
        }
        if (renderSource.cursorSource) {
            _cursorSource = [[_CSRendererSourceData alloc] initWithRenderSource:renderSource.cursorSource
                                                                       atOffset:renderSource.viewportOrigin];
        }
    }
    return self;
}

@end

@interface CSRenderer ()

@property (nonatomic) dispatch_queue_t rendererQueue;
@property (nonatomic, nullable) _CSRendererSourceData *sourceData;
@property (nonatomic) id<MTLCommandBuffer> currentCommandBuffer;

@end

// Main class performing the rendering
@implementation CSRenderer
{
    // The device (aka GPU) we're using to render
    id<MTLDevice> _device;

    // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
    id<MTLRenderPipelineState> _pipelineState;

    // The command Queue from which we'll obtain command buffers
    id<MTLCommandQueue> _commandQueue;

    // The current size of our view so we can use this in our render pipeline
    vector_uint2 _viewportSize;
    
    // Sampler object
    id<MTLSamplerState> _sampler;
}

- (void)setSource:(id<CSRenderSource>)source {
    source.device = _device;
    source.rendererDelegate = self;
    _source = source;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error = NULL;
        
        _device = mtkView.device;
        _viewportSize.x = mtkView.drawableSize.width;
        _viewportSize.y = mtkView.drawableSize.height;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        self.rendererQueue = dispatch_queue_create("CocoaSpice Renderer Queue", attr);

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
        self.currentCommandBuffer = [_commandQueue commandBuffer];
        self.currentCommandBuffer.label = @"Renderer Command Buffer";
        
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
    dispatch_async(self.rendererQueue, ^{
        [self _initializeUpscaler:upscaler downscaler:downscaler];
    });
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    dispatch_async(self.rendererQueue, ^{
        // Save the size of the drawable as we'll pass these
        //   values to our vertex shader when we draw
        _viewportSize.x = size.width;
        _viewportSize.y = size.height;
    });
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
    
    // synchronize with rendererQueue in order to access currentCommandBuffer
    dispatch_sync(self.rendererQueue, ^{
        id<MTLCommandBuffer> currentCommandBuffer = self.currentCommandBuffer;
        
        // create a new command buffer for future commands
        self.currentCommandBuffer = [_commandQueue commandBuffer];
        self.currentCommandBuffer.label = @"Renderer Command Buffer";
        
        if (self.sourceData.isVisible) {
            [self _renderCommand:currentCommandBuffer
                          source:self.sourceData
            renderPassDescriptor:renderPassDescriptor];
            
            [currentCommandBuffer presentDrawable:currentDrawable];
        }

        // Finalize rendering here & push the command buffer to the GPU
        [currentCommandBuffer commit];
    });
}

- (void)renderSouce:(id<CSRenderSource>)renderSource
         copyBuffer:(id<MTLBuffer>)sourceBuffer
             region:(MTLRegion)region
       sourceOffset:(NSUInteger)sourceOffset
  sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
         completion:(drawCompletionCallback_t)completion {
    
    _CSRendererSourceData *sourceData = [[_CSRendererSourceData alloc] initWithRenderSource:renderSource];
    
    dispatch_async(self.rendererQueue, ^{
        id<MTLCommandBuffer> commandBuffer = self.currentCommandBuffer;
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
        
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
            completion(YES);
        }];
        
        self.sourceData = sourceData;
    });
}

- (void)renderSource:(id<CSRenderSource>)renderSource drawWithCompletion:(drawCompletionCallback_t)completion {
    _CSRendererSourceData *sourceData = [[_CSRendererSourceData alloc] initWithRenderSource:renderSource];
    
    NSAssert(sourceData.isVisible, @"Should not be called if we are not visible!");
    dispatch_async(self.rendererQueue, ^{
        id<MTLCommandBuffer> commandBuffer = self.currentCommandBuffer;
        
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
            completion(YES);
        }];
        
        self.sourceData = sourceData;
    });
}

- (void)invalidateRenderSource:(id<CSRenderSource>)renderSource {
    _CSRendererSourceData *sourceData = [[_CSRendererSourceData alloc] initWithRenderSource:renderSource];
    if (!sourceData.isVisible) {
        return;
    }
    
    dispatch_async(self.rendererQueue, ^{
        self.sourceData = sourceData;
    });
}

- (void)_renderCommand:(id<MTLCommandBuffer>)commandBuffer
                source:(id<CSRenderSource>)source
  renderPassDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
    
    id<MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"View Presentation";
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    // Render the screen first
    NSAssert(source.isVisible, @"Screen should be visible at this point!");
    [self _renderEncoder:renderEncoder
            drawAtOrigin:source.viewportOrigin
                   scale:source.viewportScale
                vertices:source.vertices
            numVerticies:source.numVertices
                hasAlpha:source.hasAlpha
              isInverted:source.isInverted
                 texture:source.texture];
    
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
                     texture:source.cursorSource.texture];
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
               texture:(id<MTLTexture>)texture {
    
    matrix_float4x4 transform = matrix_scale_translate(scale,
                                                       origin);

    [renderEncoder setVertexBuffer:vertices
                            offset:0
                          atIndex:CSRenderVertexInputIndexVertices];

    [renderEncoder setVertexBytes:&_viewportSize
                           length:sizeof(_viewportSize)
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
    
    [renderEncoder setFragmentSamplerState:_sampler
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
