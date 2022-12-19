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
#import "CSShaderTypes.h"
#import <glib.h>
#import <poll.h>
#import <spice-client.h>
#import <spice/protocol.h>
#import <IOSurface/IOSurfaceRef.h>

@interface CSDisplay ()

@property (nonatomic, assign) BOOL ready;
@property (nonatomic, readwrite) NSInteger monitorID;
@property (nonatomic, nullable) SpiceDisplayChannel *channel;
@property (nonatomic, readwrite) BOOL isGLEnabled;
@property (nonatomic, readwrite) BOOL hasDrawOutstanding;
@property (nonatomic, nullable, weak, readwrite) CSCursor *cursor;
@property (nonatomic) BOOL hasInitialConfig;

// Non-GL Canvas
@property (nonatomic) dispatch_semaphore_t canvasLock;
@property (nonatomic) gint canvasFormat;
@property (nonatomic) gint canvasStride;
@property (nonatomic, nullable) const void *canvasData;
@property (nonatomic) CGRect canvasArea;

// Other Drawing
@property (nonatomic) CGRect visibleArea;
@property (nonatomic, readwrite) CGSize displaySize;

// CSRenderSource properties
@property (nonatomic, nullable, readwrite) id<MTLTexture> canvasTexture;
@property (nonatomic, nullable, readwrite) id<MTLTexture> glTexture;
@property (nonatomic, readwrite) NSUInteger numVertices;
@property (nonatomic, nullable, readwrite) id<MTLBuffer> vertices;

@end

@implementation CSDisplay

#pragma mark - Display events

static void cs_primary_create(SpiceChannel *channel, gint format,
                           gint width, gint height, gint stride,
                           gint shmid, gpointer imgdata, gpointer data) {
    CSDisplay *self = (__bridge CSDisplay *)data;
    
    g_assert(format == SPICE_SURFACE_FMT_32_xRGB || format == SPICE_SURFACE_FMT_16_555);
    dispatch_semaphore_wait(self.canvasLock, DISPATCH_TIME_FOREVER);
    self.canvasArea = CGRectMake(0, 0, width, height);
    self.canvasFormat = format;
    self.canvasStride = stride;
    self.canvasData = imgdata;
    dispatch_semaphore_signal(self.canvasLock);
    
    cs_update_monitor_area(channel, NULL, data);
}

static void cs_primary_destroy(SpiceDisplayChannel *channel, gpointer data) {
    CSDisplay *self = (__bridge CSDisplay *)data;
    self.ready = NO;
    
    dispatch_semaphore_wait(self.canvasLock, DISPATCH_TIME_FOREVER);
    self.canvasArea = CGRectZero;
    self.canvasFormat = 0;
    self.canvasStride = 0;
    self.canvasData = NULL;
    dispatch_semaphore_signal(self.canvasLock);
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
    self.ready = YES;
    g_clear_pointer(&monitors, g_array_unref);
    return;
    
whole:
    g_clear_pointer(&monitors, g_array_unref);
    /* by display whole surface */
    [self updateVisibleAreaWithRect:self.canvasArea];
    self.ready = YES;
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
    [CSMain.sharedInstance asyncWith:^{
        // done inside block to avoid race with frame completed handler
        self.hasDrawOutstanding = YES;
    }];
}

#pragma mark - Properties

@synthesize device = _device;

- (void)setDevice:(id<MTLDevice>)device {
    _device = device;
    [self rebuildDisplayVertices];
    if (self.isGLEnabled) {
        if (self.glTexture) {
            // reuse surface from existing texture (
            [self rebuildScanoutTextureWithSurface:self.glTexture.iosurface width:self.glTexture.width height:self.glTexture.height];
        } else {
            // get scanout information from SPICE
            cs_gl_scanout(self.channel, NULL, (__bridge void *)self);
        }
    } else {
        [self rebuildCanvasTexture];
    }
    self.cursor.device = device;
}

- (SpiceChannel *)spiceChannel {
    return SPICE_CHANNEL(self.channel);
}

- (CSScreenshot *)screenshot {
    CGImageRef img = NULL;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    
    dispatch_semaphore_wait(self.canvasLock, DISPATCH_TIME_FOREVER);
    if (!self.isGLEnabled && self.canvasData) { // may be destroyed at this point
        CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(NULL, self.canvasData, self.canvasStride * self.canvasArea.size.height, nil);
        img = CGImageCreate(self.canvasArea.size.width, self.canvasArea.size.height, 8, 32, self.canvasStride, colorSpaceRef, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, dataProviderRef, NULL, NO, kCGRenderingIntentDefault);
        CGDataProviderRelease(dataProviderRef);
    } else if (self.isGLEnabled && self.glTexture) {
#if 0 // FIXME: this code seems to cause crashes
        CIImage *ciimage = [[CIImage alloc] initWithMTLTexture:self.glTexture options:nil];
        CIImage *flipped = [ciimage imageByApplyingOrientation:kCGImagePropertyOrientationDownMirrored];
        CIContext *cictx = [CIContext context];
        img = [cictx createCGImage:flipped fromRect:flipped.extent];
#endif
    }
    dispatch_semaphore_signal(self.canvasLock);
    
    CGColorSpaceRelease(colorSpaceRef);
    
    if (img) {
#if TARGET_OS_IPHONE
        UIImage *uiimg = [UIImage imageWithCGImage:img];
#else
        NSImage *uiimg = [[NSImage alloc] initWithCGImage:img size:NSZeroSize];
#endif
        CGImageRelease(img);
        return [[CSScreenshot alloc] initWithImage:uiimg];
    } else {
        return nil;
    }
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
    return self.ready;
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
        cursor.device = self.device;
    }
}

#pragma mark - Methods

- (instancetype)initWithChannel:(SpiceDisplayChannel *)channel {
    if (self = [self init]) {
        SpiceDisplayPrimary primary;
        self.canvasLock = dispatch_semaphore_create(1);
        self.viewportScale = 1.0f;
        self.viewportOrigin = CGPointMake(0, 0);
        self.channel = g_object_ref(channel);
        self.monitorID = self.channelID;
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
    }];
    g_object_unref(channel);
}

- (void)updateVisibleAreaWithRect:(CGRect)rect {
    CGRect primary;
    if (self.isGLEnabled) {
        primary = CGRectMake(0, 0, self.glTexture.width, self.glTexture.height);
    } else {
        primary = self.canvasArea;
    }
    CGRect visible = CGRectIntersection(primary, rect);
    if (CGRectIsNull(visible)) {
        SPICE_DEBUG("[CocoaSpice] The monitor area is not intersecting primary surface");
        self.ready = NO;
        self.visibleArea = CGRectZero;
    } else {
        self.visibleArea = visible;
    }
    self.displaySize = self.visibleArea.size;
    [self rebuildDisplayVertices];
    if (!self.isGLEnabled) {
        [self rebuildCanvasTexture];
    }
}

- (void)rebuildScanoutTextureWithScanout:(SpiceGlScanout)scanout {
    if (!self.device) {
        return; // not ready
    }
    IOSurfaceID iosurfaceid = 0;
    IOSurfaceRef iosurface = NULL;
    if (read(scanout.fd, &iosurfaceid, sizeof(iosurfaceid)) != sizeof(iosurfaceid)) {
        SPICE_DEBUG("[CocoaSpice] Failed to read scanout fd: %d", scanout.fd);
        perror("read");
        return;
    }
    // check for POLLHUP which indicates the surface ID is stale as the sender has deallocated the surface
    struct pollfd ufd = {0};
    ufd.fd = scanout.fd;
    ufd.events = POLLIN;
    if (poll(&ufd, 1, 0) < 0) {
        SPICE_DEBUG("[CocoaSpice] Failed to poll fd: %d", scanout.fd);
        perror("poll");
        return;
    }
    if ((ufd.revents & POLLHUP) != 0) {
        SPICE_DEBUG("[CocoaSpice] Stale surface id %x read from fd %d, ignoring", iosurfaceid, scanout.fd);
        return;
    }
    
    if ((iosurface = IOSurfaceLookup(iosurfaceid)) == NULL) {
        SPICE_DEBUG("[CocoaSpice] Failed to lookup surface: %d", iosurfaceid);
        return;
    }
    [self rebuildScanoutTextureWithSurface:iosurface width:scanout.width height:scanout.height];
    CFRelease(iosurface);
}

- (void)rebuildScanoutTextureWithSurface:(IOSurfaceRef)surface width:(NSUInteger)width height:(NSUInteger)height {
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDescriptor.width = width;
    textureDescriptor.height = height;
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    self.glTexture = [self.device newTextureWithDescriptor:textureDescriptor iosurface:surface plane:0];
}

- (void)rebuildCanvasTexture {
    if (CGRectIsEmpty(self.canvasArea) || !self.device) {
        return;
    }
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    // don't worry that that components are reversed, we fix it in shaders
    textureDescriptor.pixelFormat = (self.canvasFormat == SPICE_SURFACE_FMT_32_xRGB) ? MTLPixelFormatBGRA8Unorm : (MTLPixelFormat)43;// FIXME: MTLPixelFormatBGR5A1Unorm is supposed to be available.
    textureDescriptor.width = self.visibleArea.size.width;
    textureDescriptor.height = self.visibleArea.size.height;
    self.canvasTexture = [self.device newTextureWithDescriptor:textureDescriptor];
    [self drawRegion:self.visibleArea];
}

- (void)rebuildDisplayVertices {
    // We flip the y-coordinates because pixman renders flipped
    CSRenderVertex quadVertices[] =
    {
        // Pixel positions, Texture coordinates
        { {  self.visibleArea.size.width/2,   self.visibleArea.size.height/2 },  { 1.f, 0.f } },
        { { -self.visibleArea.size.width/2,   self.visibleArea.size.height/2 },  { 0.f, 0.f } },
        { { -self.visibleArea.size.width/2,  -self.visibleArea.size.height/2 },  { 0.f, 1.f } },
        
        { {  self.visibleArea.size.width/2,   self.visibleArea.size.height/2 },  { 1.f, 0.f } },
        { { -self.visibleArea.size.width/2,  -self.visibleArea.size.height/2 },  { 0.f, 1.f } },
        { {  self.visibleArea.size.width/2,  -self.visibleArea.size.height/2 },  { 1.f, 1.f } },
    };
    
    // Create our vertex buffer, and initialize it with our quadVertices array
    self.vertices = [self.device newBufferWithBytes:quadVertices
                                             length:sizeof(quadVertices)
                                            options:MTLResourceStorageModeShared];

    // Calculate the number of vertices by dividing the byte length by the size of each vertex
    self.numVertices = sizeof(quadVertices) / sizeof(CSRenderVertex);
}

- (void)drawRegion:(CGRect)rect {
    NSInteger pixelSize = (self.canvasFormat == SPICE_SURFACE_FMT_32_xRGB) ? 4 : 2;
    // create draw region
    MTLRegion region = {
        { rect.origin.x-self.visibleArea.origin.x, rect.origin.y-self.visibleArea.origin.y, 0 }, // MTLOrigin
        { rect.size.width, rect.size.height, 1} // MTLSize
    };
    dispatch_semaphore_wait(self.canvasLock, DISPATCH_TIME_FOREVER);
    if (self.canvasData) {
        [self.canvasTexture  replaceRegion:region
                               mipmapLevel:0
                                 withBytes:(const char *)self.canvasData + (NSUInteger)(rect.origin.y*self.canvasStride + rect.origin.x*pixelSize)
                               bytesPerRow:self.canvasStride];
    }
    dispatch_semaphore_signal(self.canvasLock);
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

- (void)rendererFrameHasRendered {
    SpiceDisplayChannel *display = self.channel;
    if (display && self.isGLEnabled && self.hasDrawOutstanding) {
        [CSMain.sharedInstance asyncWith:^{
            // recheck to avoid race condition, outer if is just an optimization
            if (self.hasDrawOutstanding) {
                spice_display_channel_gl_draw_done(display);
                // done inside the block to avoid race with a new gl_draw event
                self.hasDrawOutstanding = NO;
            }
        }];
    }
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
