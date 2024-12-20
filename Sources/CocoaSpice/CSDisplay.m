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

@import CoreImage;
#import "TargetConditionals.h"
#import "CocoaSpice.h"
#import "CSCursor+Protected.h"
#import "CSChannel+Protected.h"
#import "CSDisplay+Renderer_Protected.h"
#import "CSShaderTypes.h"
#import <glib.h>
#import <poll.h>
#import <spice-client.h>
#import <spice/protocol.h>
#import <IOSurface/IOSurfaceRef.h>
#import <mach/vm_page_size.h>

typedef void (^blitCommandCallback_t)(id<MTLBlitCommandEncoder>);

@interface CSDisplay ()

@property (nonatomic, assign) BOOL ready;
@property (nonatomic, readwrite) NSInteger monitorID;
@property (nonatomic, nullable) SpiceDisplayChannel *channel;
@property (nonatomic, readwrite) BOOL isGLEnabled;
@property (nonatomic, readonly) BOOL hasDrawOutstanding;
@property (nonatomic, nullable, weak, readwrite) CSCursor *cursor;
@property (nonatomic) BOOL hasInitialConfig;
@property (nonatomic, nullable) IOSurfaceRef delayedScanoutSurface;
@property (nonatomic, assign) SpiceGlScanout delayedScanoutInfo;

// Non-GL Canvas
@property (nonatomic) gint canvasFormat;
@property (nonatomic) gint canvasStride;
@property (nonatomic, nullable) const void *canvasData;
@property (nonatomic) CGRect canvasArea;
@property (nonatomic) id<MTLBuffer> canvasBuffer;
@property (nonatomic) NSUInteger canvasBufferOffset;
@property (nonatomic) dispatch_queue_t canvasDrawQueue;

// Other Drawing
@property (nonatomic) CGRect visibleArea;
@property (nonatomic, readwrite) CGSize displaySize;
@property (nonatomic) dispatch_queue_t displayQueue;

// CSRenderSource properties
@property (nonatomic, nullable, readwrite) id<MTLTexture> canvasTexture;
@property (nonatomic, nullable, readwrite) id<MTLTexture> glTexture;
@property (nonatomic, readwrite) NSUInteger numVertices;
@property (nonatomic, nullable, readwrite) id<MTLBuffer> vertices;

@property (nonatomic) id<MTLDevice> device;
@property (nonatomic) NSMutableArray<id<CSRenderer>> *renderers;

@end

@implementation CSDisplay

#pragma mark - Display events

static void cs_primary_create(SpiceChannel *channel, gint format,
                           gint width, gint height, gint stride,
                           gint shmid, gpointer imgdata, gpointer data) {
    CSDisplay *self = (__bridge CSDisplay *)data;
    
    g_assert(format == SPICE_SURFACE_FMT_32_xRGB || format == SPICE_SURFACE_FMT_16_555);
    dispatch_barrier_sync(self.canvasDrawQueue, ^{
        dispatch_sync(self.displayQueue, ^{
            self.canvasArea = CGRectMake(0, 0, width, height);
            self.canvasFormat = format;
            self.canvasStride = stride;
            self.canvasData = imgdata;
        });
    });
    
    cs_update_monitor_area(channel, NULL, data);
}

static void cs_primary_destroy(SpiceDisplayChannel *channel, gpointer data) {
    CSDisplay *self = (__bridge CSDisplay *)data;
    self.ready = NO;
    
    dispatch_barrier_sync(self.canvasDrawQueue, ^{
        dispatch_sync(self.displayQueue, ^{
            self.canvasArea = CGRectZero;
            self.canvasFormat = 0;
            self.canvasStride = 0;
            self.canvasData = NULL;
        });
    });
}

static void cs_invalidate(SpiceChannel *channel,
                       gint x, gint y, gint w, gint h, gpointer data) {
    CSDisplay *self = (__bridge CSDisplay *)data;
    CGRect rect = CGRectIntersection(CGRectMake(x, y, w, h), self.visibleArea);
    self.isGLEnabled = NO;
    if (!CGRectIsEmpty(rect)) {
        [self drawRegion:rect];
    }
}

static void cs_mark(SpiceChannel *channel, gint mark, gpointer data) {
    //CSDisplay *self = (__bridge CSDisplay *)data;
    //@synchronized (self) {
    //    self->_mark = mark; // currently this does nothing for us
    //}
}

static gboolean cs_set_overlay(SpiceChannel *channel, void* pipeline_ptr, gpointer data) {
    //FIXME: implement overlay
    //CSDisplay *self = (__bridge CSDisplay *)data;
    return false;
}

static void cs_update_monitor_area(SpiceChannel *channel, GParamSpec *pspec, gpointer data) {
    CSDisplay *self = (__bridge CSDisplay *)data;
    SpiceDisplayMonitorConfig *cfg, *c = NULL;
    GArray *monitors = NULL;
    int i;
    
    SPICE_DEBUG("[CocoaSpice] update monitor area");
    if (self.monitorID < 0)
        goto whole;
    
    g_object_get(self.channel, "monitors", &monitors, NULL);
    //for (i = 0; monitors != NULL && i < monitors->len; i++) {
    //    cfg = &g_array_index(monitors, SpiceDisplayMonitorConfig, i);
    //    if (cfg->id == self.monitorID) {
    //        c = cfg;
    //        break;
    //    }
    //}
    g_assert(monitors->len <= 1);
    if (monitors->len == 0) {
        SPICE_DEBUG("[CocoaSpice] update monitor: no monitor %d", (int)self.monitorID);
        self.ready = NO;
        if (spice_channel_test_capability(SPICE_CHANNEL(self.channel),
                                          SPICE_DISPLAY_CAP_MONITORS_CONFIG)) {
            SPICE_DEBUG("[CocoaSpice] waiting until MonitorsConfig is received");
            g_clear_pointer(&monitors, g_array_unref);
            return;
        }
        goto whole;
    }
    c = &g_array_index(monitors, SpiceDisplayMonitorConfig, 0);
    
    if (c->surface_id != 0) {
        g_warning("FIXME: only support monitor config with primary surface 0, "
                  "but given config surface %u", c->surface_id);
        goto whole;
    }
    
    /* If only one head on this monitor, update the whole area */
    if (monitors->len == 1 && !self.isGLEnabled) {
        [self updateVisibleAreaWithRect:CGRectMake(0, 0, c->width, c->height)];
    } else {
        [self updateVisibleAreaWithRect:CGRectMake(c->x, c->y, c->width, c->height)];
    }
    g_clear_pointer(&monitors, g_array_unref);
    return;
    
whole:
    g_clear_pointer(&monitors, g_array_unref);
    /* by display whole surface */
    [self updateVisibleAreaWithRect:self.canvasArea];
}

#pragma mark - GL

static void cs_gl_scanout(SpiceDisplayChannel *channel, GParamSpec *pspec, gpointer data)
{
    CSDisplay *self = (__bridge CSDisplay *)data;

    SPICE_DEBUG("[CocoaSpice] %s: got scanout",  __FUNCTION__);

    const SpiceGlScanout *scanout;

    scanout = spice_display_channel_get_gl_scanout(self.channel);
    /* should only be called when the display has a scanout */
    g_return_if_fail(scanout != NULL);
    
    self.isGLEnabled = YES;

    [self rebuildScanoutTextureWithScanout:*scanout];
}

static void cs_gl_draw(SpiceDisplayChannel *channel,
                       guint32 x, guint32 y, guint32 w, guint32 h,
                       gpointer data)
{
    CSDisplay *self = (__bridge CSDisplay *)data;

    SPICE_DEBUG("[CocoaSpice] %s",  __FUNCTION__);

    self.isGLEnabled = YES;
    [self invalidate];
    // unblock the caller immedately
    spice_display_channel_gl_draw_done(channel);
}

#pragma mark - Properties

- (void)setDevice:(id<MTLDevice>)device {
    if (_device == device) {
        return;
    }
    _device = device;
    [self rebuildDisplayVertices];
    if (self.isGLEnabled) {
        if (self.delayedScanoutSurface) {
            [self rebuildScanoutTextureWithSurface:self.delayedScanoutSurface width:self.delayedScanoutInfo.width height:self.delayedScanoutInfo.height];
            self.delayedScanoutSurface = nil;
        } else {
            if (self.glTexture) {
                // reuse surface from existing texture (
                [self rebuildScanoutTextureWithSurface:self.glTexture.iosurface width:self.glTexture.width height:self.glTexture.height];
            }
        }
    } else {
        [self rebuildCanvasTexture];
    }
    // possibly retrigger cursor rebuild
    self.cursor.display = self;
}

- (SpiceChannel *)spiceChannel {
    return SPICE_CHANNEL(self.channel);
}

- (void)screenshotWithCompletion:(screenshotCallback_t)completion {
    dispatch_async(self.canvasDrawQueue, ^{
        CGImageRef img = NULL;
        __block const void *canvasData = NULL;
        __block CGRect canvasArea;
        __block gint canvasStride;
        __block id<MTLTexture> glTexture = nil;
        
        dispatch_sync(self.displayQueue, ^{
            canvasData = self.canvasData;
            canvasArea = self.canvasArea;
            canvasStride = self.canvasStride;
            glTexture = self.glTexture;
            
            if (self.isGLEnabled) {
                canvasData = NULL;
            } else {
                glTexture = nil;
            }
        });
        
        if (canvasData) {
            CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
            CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(NULL,
                                                                             canvasData,
                                                                             canvasStride * canvasArea.size.height,
                                                                             nil);
            img = CGImageCreate(canvasArea.size.width,
                                canvasArea.size.height,
                                8,
                                32,
                                canvasStride,
                                colorSpaceRef,
                                kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
                                dataProviderRef,
                                NULL,
                                NO,
                                kCGRenderingIntentDefault);
            CGDataProviderRelease(dataProviderRef);
            CGColorSpaceRelease(colorSpaceRef);
        } else if (glTexture) {
            CIImage *ciimage = [[CIImage alloc] initWithMTLTexture:glTexture options:nil];
            CIImage *flipped = [ciimage imageByApplyingOrientation:kCGImagePropertyOrientationDownMirrored];
            CIContext *cictx = [CIContext context];
            img = [cictx createCGImage:flipped fromRect:flipped.extent];
        }
        
        if (img) {
#if TARGET_OS_IPHONE
            UIImage *uiimg = [UIImage imageWithCGImage:img];
#else
            NSImage *uiimg = [[NSImage alloc] initWithCGImage:img size:NSZeroSize];
#endif
            CGImageRelease(img);
            completion([[CSScreenshot alloc] initWithImage:uiimg]);
        } else {
            completion(nil);
        }
    });
}

- (id<MTLTexture>)texture {
    if (self.isGLEnabled) {
        return self.glTexture;
    } else {
        return self.canvasTexture;
    }
}

- (BOOL)isPrimaryDisplay {
    return self.monitorID == 0;
}

- (BOOL)isVisible {
    return self.ready && self.texture && self.vertices;
}

- (BOOL)isInverted {
    return NO; // never inverted
}

- (BOOL)hasAlpha {
    return NO; // do not blend alpha
}

- (id<CSRenderSource>)cursorSource {
    return self.cursor;
}

- (void)setCursor:(CSCursor *)cursor {
    if (_cursor) {
        _cursor.display = nil;
    }
    _cursor = cursor;
    if (cursor) {
        cursor.display = self;
    }
}

- (BOOL)hasDrawOutstanding {
    gboolean value;
    if (self.channel) {
        g_object_get(self.channel, "draw-done-pending", &value, NULL);
    } else {
        value = FALSE;
    }
    return value;
}

- (void)setViewportOrigin:(CGPoint)viewportOrigin {
    if (!CGPointEqualToPoint(_viewportOrigin, viewportOrigin)) {
        _viewportOrigin = viewportOrigin;
        [self invalidate];
    }
}

- (void)setViewportScale:(CGFloat)viewportScale {
    if (_viewportScale != viewportScale) {
        _viewportScale = viewportScale;
        [self invalidate];
    }
}

#pragma mark - Methods

- (instancetype)initWithChannel:(SpiceDisplayChannel *)channel {
    if (self = [self init]) {
        SpiceDisplayPrimary primary;
        _viewportScale = 1.0f;
        _viewportOrigin = CGPointMake(0, 0);
        self.channel = g_object_ref(channel);
        self.monitorID = self.channelID;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        self.displayQueue = dispatch_queue_create("CocoaSpice Display Queue", attr);
        attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INTERACTIVE, 0);
        self.canvasDrawQueue = dispatch_queue_create("CocoaSpice Canvas Draw Queue", attr);
        self.renderers = [NSMutableArray array];
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_connect(channel, "display-primary-create",
                         G_CALLBACK(cs_primary_create), (__bridge void *)self);
        g_signal_connect(channel, "display-primary-destroy",
                         G_CALLBACK(cs_primary_destroy), (__bridge void *)self);
        g_signal_connect(channel, "display-invalidate",
                         G_CALLBACK(cs_invalidate), (__bridge void *)self);
        g_signal_connect(channel, "display-mark",
                         G_CALLBACK(cs_mark), (__bridge void *)self);
        g_signal_connect(channel, "notify::monitors",
                         G_CALLBACK(cs_update_monitor_area), (__bridge void *)self);
        g_signal_connect(channel, "gst-video-overlay",
                         G_CALLBACK(cs_set_overlay), (__bridge void *)self);
        g_signal_connect(channel, "notify::gl-scanout",
                         G_CALLBACK(cs_gl_scanout), (__bridge void *)self);
        g_signal_connect(channel, "gl-draw",
                         G_CALLBACK(cs_gl_draw), (__bridge void *)self);
        if (spice_display_channel_get_primary(self.spiceChannel, 0, &primary)) {
            cs_primary_create(self.spiceChannel, primary.format, primary.width, primary.height,
                              primary.stride, primary.shmid, primary.data, (__bridge void *)self);
            cs_mark(self.spiceChannel, primary.marked, (__bridge void *)self);
        }
    }
    return self;
}

- (void)dealloc {
    SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
    SpiceDisplayChannel *channel = self.channel;
    gpointer data = (__bridge void *)self;
    [CSMain.sharedInstance syncWith:^{
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_primary_create), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_primary_destroy), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_invalidate), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_mark), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_update_monitor_area), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_set_overlay), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_gl_scanout), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_gl_draw), data);
        g_object_unref(channel);
    }];
}

- (void)updateVisibleAreaWithRect:(CGRect)rect {
    dispatch_sync(self.displayQueue, ^{
        CGRect primary = self.canvasArea;
        CGRect visible = CGRectIntersection(primary, rect);
        if (CGRectIsNull(visible)) {
            SPICE_DEBUG("[CocoaSpice] The monitor area is not intersecting primary surface");
            self.ready = NO;
            self.visibleArea = CGRectZero;
        } else {
            self.visibleArea = visible;
        }
        self.displaySize = self.visibleArea.size;
    });
    [self rebuildDisplayVertices];
    if (!self.isGLEnabled) {
        [self rebuildCanvasTexture];
    }
    self.ready = YES;
}

- (void)rebuildScanoutTextureWithScanout:(SpiceGlScanout)scanout {
    IOSurfaceID iosurfaceid = 0;
    IOSurfaceRef iosurface = NULL;

    // check for POLLHUP which indicates the surface ID is stale as the sender has deallocated the surface
    struct pollfd ufd = {0};
    ufd.fd = scanout.fd;
    ufd.events = POLLIN;
    if (poll(&ufd, 1, 0) < 0) {
        SPICE_DEBUG("[CocoaSpice] Failed to poll fd: %d", scanout.fd);
        perror("poll");
        return;
    }
    if ((ufd.revents & (POLLHUP | POLLIN)) != POLLIN) {
        SPICE_DEBUG("[CocoaSpice] Ignoring scanout from stale fd %d", scanout.fd);
        return;
    }

    if (read(scanout.fd, &iosurfaceid, sizeof(iosurfaceid)) != sizeof(iosurfaceid)) {
        SPICE_DEBUG("[CocoaSpice] Failed to read scanout fd: %d", scanout.fd);
        perror("read");
        return;
    }
    if ((iosurface = IOSurfaceLookup(iosurfaceid)) == NULL) {
        SPICE_DEBUG("[CocoaSpice] Failed to lookup surface: %d", iosurfaceid);
        return;
    }
    if (self.device) {
        [self rebuildScanoutTextureWithSurface:iosurface width:scanout.width height:scanout.height];
    } else {
        // delay until we have a device
        self.delayedScanoutSurface = iosurface;
        self.delayedScanoutInfo = scanout;
    }
}

- (void)rebuildScanoutTextureWithSurface:(IOSurfaceRef)surface width:(NSUInteger)width height:(NSUInteger)height {
    dispatch_sync(self.displayQueue, ^{
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
        textureDescriptor.width = width;
        textureDescriptor.height = height;
        textureDescriptor.usage = MTLTextureUsageShaderRead;
        self.canvasArea = CGRectMake(0, 0, width, height);
        self.glTexture = [self.device newTextureWithDescriptor:textureDescriptor iosurface:surface plane:0];
        CFRelease(surface);
    });
}

- (void)rebuildCanvasTexture {
    dispatch_sync(self.displayQueue, ^{
        CGRect visibleArea = self.visibleArea;
        if (CGRectIsEmpty(visibleArea) || !self.device) {
            return;
        }
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        // don't worry that that components are reversed, we fix it in shaders
        textureDescriptor.pixelFormat = (self.canvasFormat == SPICE_SURFACE_FMT_32_xRGB) ? MTLPixelFormatBGRA8Unorm : (MTLPixelFormat)43;// FIXME: MTLPixelFormatBGR5A1Unorm is supposed to be available.
        textureDescriptor.width = visibleArea.size.width;
        textureDescriptor.height = visibleArea.size.height;
        textureDescriptor.usage = MTLTextureUsageShaderRead;
        self.canvasTexture = [self.device newTextureWithDescriptor:textureDescriptor];
        uintptr_t canvasDataAligned = trunc_page_kernel((uintptr_t)self.canvasData);
        NSUInteger canvasSize = self.canvasStride * self.canvasArea.size.height;
        if (!canvasDataAligned || !canvasSize) {
            return; // it will be freed
        }
#if TARGET_OS_SIMULATOR
        self.canvasBuffer = [self.device newBufferWithBytes:(void *)self.canvasData
                                                     length:canvasSize
                                                    options:0];
#else /* !TARGET_OS_SIMULATOR */
        // round size up to multiple of page size
        self.canvasBufferOffset = ((uintptr_t)self.canvasData - canvasDataAligned);
        canvasSize += self.canvasBufferOffset;
        canvasSize = round_page_kernel(canvasSize);
        self.canvasBuffer = [self.device newBufferWithBytesNoCopy:(void *)canvasDataAligned
                                                           length:canvasSize
#if TARGET_OS_OSX
                                                          options:MTLResourceStorageModeManaged
#else
                                                          options:MTLResourceCPUCacheModeWriteCombined
#endif
                                                      deallocator:nil];
#endif /* TARGET_OS_SIMULATOR */
        [self drawRegion:visibleArea];
    });
}

- (void)rebuildDisplayVertices {
    dispatch_sync(self.displayQueue, ^{
        CGRect visibleArea = self.visibleArea;
        if (CGRectIsEmpty(visibleArea) || !self.device) {
            return;
        }
        dispatch_async(self.displayQueue, ^{
            // We flip the y-coordinates because pixman renders flipped
            CSRenderVertex quadVertices[] =
            {
                // Pixel positions, Texture coordinates
                { {  visibleArea.size.width/2,   visibleArea.size.height/2 },  { 1.f, 0.f } },
                { { -visibleArea.size.width/2,   visibleArea.size.height/2 },  { 0.f, 0.f } },
                { { -visibleArea.size.width/2,  -visibleArea.size.height/2 },  { 0.f, 1.f } },
                
                { {  visibleArea.size.width/2,   visibleArea.size.height/2 },  { 1.f, 0.f } },
                { { -visibleArea.size.width/2,  -visibleArea.size.height/2 },  { 0.f, 1.f } },
                { {  visibleArea.size.width/2,  -visibleArea.size.height/2 },  { 1.f, 1.f } },
            };
            
            // Create our vertex buffer, and initialize it with our quadVertices array
            self.vertices = [self.device newBufferWithBytes:quadVertices
                                                     length:sizeof(quadVertices)
                                                    options:MTLResourceCPUCacheModeWriteCombined];
            
            // Calculate the number of vertices by dividing the byte length by the size of each vertex
            self.numVertices = sizeof(quadVertices) / sizeof(CSRenderVertex);
        });
    });
}

- (void)drawRegion:(CGRect)rect {
    dispatch_async(self.canvasDrawQueue, ^{
        dispatch_semaphore_t drawCompletedEvent = dispatch_semaphore_create(0);
        dispatch_async(self.displayQueue, ^{
            if (!self.canvasData || !self.canvasBuffer) {
                dispatch_semaphore_signal(drawCompletedEvent);
                return; // not ready to draw yet
            }
            NSInteger pixelSize = (self.canvasFormat == SPICE_SURFACE_FMT_32_xRGB) ? 4 : 2;
            // create draw region
            MTLRegion region = {
                { rect.origin.x-self.visibleArea.origin.x, rect.origin.y-self.visibleArea.origin.y, 0 }, // MTLOrigin
                { rect.size.width, rect.size.height, 1} // MTLSize
            };
            NSUInteger offset = (NSUInteger)(rect.origin.y*self.canvasStride + rect.origin.x*pixelSize);
            NSUInteger totalBytes = rect.size.width*rect.size.height*pixelSize;
#if TARGET_OS_OSX || TARGET_OS_SIMULATOR
            for (NSUInteger i = 0; i < rect.size.height; i++) {
#if TARGET_OS_SIMULATOR
                memcpy(self.canvasBuffer.contents + offset + i*self.canvasStride,
                       self.canvasData + offset + i*self.canvasStride,
                       rect.size.width*pixelSize);
#else /* !TARGET_OS_SIMULATOR */
                [self.canvasBuffer didModifyRange:NSMakeRange(offset+i*self.canvasStride,
                                                              rect.size.width*pixelSize)];
#endif /* TARGET_OS_SIMULATOR */
            }
#endif
            // hold a read lock on the concurrent draw queue
            [self copyBuffer:self.canvasBuffer
                      region:region
                sourceOffset:self.canvasBufferOffset + offset
           sourceBytesPerRow:self.canvasStride
                  completion:^ {
                dispatch_semaphore_signal(drawCompletedEvent);
            }];
        });
        dispatch_semaphore_wait(drawCompletedEvent, DISPATCH_TIME_FOREVER);
    });
}

- (void)requestResolution:(CGRect)bounds {
    SpiceMainChannel *main = self.spiceMain;
    if (!main) {
        SPICE_DEBUG("[CocoaSpice] ignoring change resolution because main channel not found");
        return;
    }
    [CSMain.sharedInstance asyncWith:^{
        spice_main_channel_update_display_enabled(main, (int)self.monitorID, TRUE, FALSE);
        spice_main_channel_update_display(main,
                                          (int)self.monitorID,
                                          bounds.origin.x,
                                          bounds.origin.y,
                                          bounds.size.width,
                                          bounds.size.height,
                                          TRUE);
        spice_main_channel_send_monitor_config(main);
    }];
}

- (void)setIsEnabled:(BOOL)isEnabled {
    if (_isEnabled != isEnabled) {
        SpiceMainChannel *main = self.spiceMain;
        if (!main) {
            SPICE_DEBUG("[CocoaSpice] ignoring display enable change because main channel not found");
            return;
        }
        [CSMain.sharedInstance asyncWith:^{
            spice_main_channel_update_display_enabled(main, (int)self.monitorID, isEnabled, TRUE);
            self->_isEnabled = isEnabled;
        }];
    }
}

@end
