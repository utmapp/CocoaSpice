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

@interface CSRenderer ()

@property (nonatomic, weak) MTKView *mtkView;
@property (nonatomic) BOOL isManualDrawing;
@property (nonatomic) BOOL isViewInvalidated;

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

- (void)setMtkView:(MTKView *)mtkView {
    if (_mtkView != mtkView) {
        _mtkView = mtkView;
        [self _updateMTKViewDrawMode];
    }
}

- (void)setIsManualDrawing:(BOOL)isManualDrawing {
    if (_isManualDrawing != isManualDrawing) {
        _isManualDrawing = isManualDrawing;
        [self _updateMTKViewDrawMode];
    }
}

- (void)setPreferredFramesPerSecond:(NSInteger)preferredFramesPerSecond {
    if (_preferredFramesPerSecond != preferredFramesPerSecond) {
        _preferredFramesPerSecond = preferredFramesPerSecond;
        [self _updateMTKViewDrawMode];
    }
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;

        /// Create our render pipeline

        // Load all the shader files with a .metal file extension in the project
        // FIXME: on Swift we have `Bundle.module` generated by SPM but it doesn't appear to be the case for Obj-C
        NSURL *modulePath = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"CocoaSpice_CocoaSpiceRenderer.bundle"];
        NSBundle *bundle = [NSBundle bundleWithURL:modulePath];
        NSError *err = nil;
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibraryWithBundle:bundle error:&err];
        if (!defaultLibrary || err) {
            NSLog(@"Failed to get library from bundle: %@", err.localizedDescription);
        }

        // Load the vertex function from the library
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

        // Load the fragment function from the library
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];

        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Texturing Pipeline";
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

        NSError *error = NULL;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
        if (!_pipelineState)
        {
            // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
            //  If the Metal API validation is enabled, we can find out more information about what
            //  went wrong.  (Metal API validation is enabled by default when a debug build is run
            //  from Xcode)
            NSLog(@"Failed to created pipeline state, error %@", error);
        }

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
        
        // Sampler
        [self changeUpscaler:MTLSamplerMinMagFilterLinear downscaler:MTLSamplerMinMagFilterLinear];
        
        // save weak reference to view
        _mtkView = mtkView;
    }

    return self;
}

/// Scalers from VM settings
- (void)changeUpscaler:(MTLSamplerMinMagFilter)upscaler downscaler:(MTLSamplerMinMagFilter)downscaler {
    MTLSamplerDescriptor *samplerDescriptor = [MTLSamplerDescriptor new];
    samplerDescriptor.minFilter = downscaler;
    samplerDescriptor.magFilter = upscaler;
     
    _sampler = [_device newSamplerStateWithDescriptor:samplerDescriptor];
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
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

- (void)renderSource:(id<CSRenderSource>)source withEncoder:(id<MTLRenderCommandEncoder>)renderEncoder atOffset:(CGPoint)offset {
    
    bool hasAlpha = source.hasAlpha;
    bool isInverted = source.isInverted;
    CGPoint viewportOrigin = CGPointMake(source.viewportOrigin.x +
                                         offset.x,
                                         source.viewportOrigin.y +
                                         offset.y);
    matrix_float4x4 transform = matrix_scale_translate(source.viewportScale,
                                                       viewportOrigin);

    [renderEncoder setVertexBuffer:source.vertices
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
    [renderEncoder setFragmentTexture:source.texture
                              atIndex:CSRenderTextureIndexBaseColor];
    
    [renderEncoder setFragmentSamplerState:_sampler
                                   atIndex:CSRenderSamplerIndexTexture];
    
    [renderEncoder setFragmentBytes:&isInverted
                             length:sizeof(isInverted)
                            atIndex:CSRenderFragmentBufferIndexIsInverted];

    // Draw the vertices of our triangles
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:source.numVertices];
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    id<CSRenderSource> source = self.source;
    if (view.hidden || !source) {
        _isViewInvalidated = NO;
        return;
    }
    
    dispatch_async(source.rendererQueue, ^{
        @autoreleasepool {
            [self drawInMTKView:view serializedWithSource:source];
        }
    });
}

- (void)drawInMTKView:(nonnull MTKView *)view serializedWithSource:(id<CSRenderSource>)source {
    id<CSRenderSource> cursorSource = source.cursorSource;
    
    // Create a new command buffer for each render pass to the current drawable
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    id<MTLDrawable> currentDrawable = view.currentDrawable;

    if (renderPassDescriptor == nil || currentDrawable == nil)
    {
        _isViewInvalidated = NO;
        return;
    }
    
    if (source.hasBlitCommands || cursorSource.hasBlitCommands) {
        // Create a bilt command encoder for any texture copying
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        blitEncoder.label = @"Source Texture Updates";
        
        if (source.isVisible) {
            [self.source rendererUpdateTextureWithBlitCommandEncoder:blitEncoder];
        }
        
        if (cursorSource && cursorSource.isVisible) {
            [cursorSource rendererUpdateTextureWithBlitCommandEncoder:blitEncoder];
        }
        
        [blitEncoder endEncoding];
    }
    
    // Create a render command encoder so we can render into something
    id<MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"MyRenderEncoder";
    
    [renderEncoder setRenderPipelineState:_pipelineState];
    
    // Render the screen first
    if (source.isVisible) {
        [self renderSource:source withEncoder:renderEncoder atOffset:CGPointZero];
    }
    
    // Draw cursor
    if (cursorSource && cursorSource.isVisible) {
        // Next render the cursor
        [self renderSource:cursorSource withEncoder:renderEncoder atOffset:source.viewportOrigin];
    }

    [renderEncoder endEncoding];
    
    // Schedule a present once the framebuffer is complete using the current drawable
    if (@available(macOS 10.15.4, *)) {
        if (self.preferredFramesPerSecond > 0) {
            [commandBuffer presentDrawable:currentDrawable afterMinimumDuration:1.0f/self.preferredFramesPerSecond];
        } else {
            [commandBuffer presentDrawable:currentDrawable];
        }
    } else {
        [commandBuffer presentDrawable:currentDrawable];
    }
    
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
        // GPU work is complete
        [cursorSource rendererFrameHasRendered];
        [source rendererFrameHasRendered];
        _isViewInvalidated = NO;
    }];

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
    
    // block renderering queue until scheduled
    [commandBuffer waitUntilScheduled];
    
}

- (void)renderSourceDidInvalidate:(id<CSRenderSource>)renderSource {
    if (!self.isViewInvalidated && self.isManualDrawing) {
        // this combines many invalidate calls
        self.isViewInvalidated = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTKView *view = self.mtkView;
            if (view) {
                [self.mtkView draw];
            } else {
                // do not block next draw
                self.isViewInvalidated = NO;
            }
        });
    }
}

- (void)renderSource:(id<CSRenderSource>)renderSource didChangeModeToManualDrawing:(BOOL)manualDrawing {
    self.isManualDrawing = manualDrawing;
    self.isViewInvalidated = NO;
}

- (void)_updateMTKViewDrawMode {
    MTKView *view = self.mtkView;
    if (!view) {
        return;
    }
    if (self.isManualDrawing) {
        view.paused = YES;
        view.enableSetNeedsDisplay = NO;
    } else {
        view.paused = NO;
        view.enableSetNeedsDisplay = NO;
        if (@available(macOS 10.15.4, *)) {
            if (self.preferredFramesPerSecond > 0) {
                view.preferredFramesPerSecond = self.preferredFramesPerSecond;
            }
        }
    }
}

@end
