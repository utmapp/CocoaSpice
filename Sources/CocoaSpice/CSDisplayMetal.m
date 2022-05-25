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
#import "CSShaderTypes.h"
#import <glib.h>
#import <poll.h>
#import <spice-client.h>
#import <spice/protocol.h>
#import <IOSurface/IOSurfaceRef.h>

#ifdef DISPLAY_DEBUG
#undef DISPLAY_DEBUG
#endif
#define DISPLAY_DEBUG(display, fmt, ...) \
    SPICE_DEBUG("%d:%d " fmt, \
                (int)display.channelID, \
                (int)display.monitorID, \
                ## __VA_ARGS__)

@interface CSDisplayMetal ()

@property (nonatomic, assign) BOOL ready;
@property (nonatomic, readwrite, nullable) SpiceSession *session;
@property (nonatomic, readwrite, assign) NSInteger channelID;
@property (nonatomic, readwrite, assign) NSInteger monitorID;
@property (nonatomic, nullable) SpiceDisplayChannel *display;
@property (nonatomic, nullable) SpiceMainChannel *main;
@property (nonatomic, readwrite) BOOL isGLEnabled;
@property (nonatomic, readwrite) BOOL hasGLDrawAck;
@property (nonatomic, nullable, weak, readwrite) CSCursor *cursor;

// Non-GL Canvas
@property (nonatomic) dispatch_semaphore_t canvasLock;
@property (nonatomic) gint canvasFormat;
@property (nonatomic) gint canvasStride;
@property (nonatomic, nullable) const void *canvasData;
@property (nonatomic) CGRect canvasArea;

// Other Drawing
@property (nonatomic) CGRect visibleArea;

// CSRenderSource properties
@property (nonatomic, nullable, readwrite) id<MTLTexture> canvasTexture;
@property (nonatomic, nullable, readwrite) id<MTLTexture> glTexture;
@property (nonatomic, readwrite) NSUInteger displayNumVertices;
@property (nonatomic, nullable, readwrite) id<MTLBuffer> displayVertices;
@property (nonatomic, readwrite) CGPoint viewportOrigin;
@property (nonatomic, readwrite) CGFloat viewportScale;

@end

@implementation CSDisplayMetal {
    id<MTLDevice> _device;
}

#pragma mark - Display events

static void cs_primary_create(SpiceChannel *channel, gint format,
                           gint width, gint height, gint stride,
                           gint shmid, gpointer imgdata, gpointer data) {
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    
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
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
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
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    CGRect rect = CGRectIntersection(CGRectMake(x, y, w, h), self.visibleArea);
    self.isGLEnabled = NO;
    if (!CGRectIsEmpty(rect)) {
        [self drawRegion:rect];
    }
}

static void cs_mark(SpiceChannel *channel, gint mark, gpointer data) {
    //CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    //@synchronized (self) {
    //    self->_mark = mark; // currently this does nothing for us
    //}
}

static gboolean cs_set_overlay(SpiceChannel *channel, void* pipeline_ptr, gpointer data) {
    //FIXME: implement overlay
    //CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    return false;
}

static void cs_update_monitor_area(SpiceChannel *channel, GParamSpec *pspec, gpointer data) {
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    SpiceDisplayMonitorConfig *cfg, *c = NULL;
    GArray *monitors = NULL;
    int i;
    
    DISPLAY_DEBUG(self, "update monitor area");
    if (self.monitorID < 0)
        goto whole;
    
    g_object_get(self.display, "monitors", &monitors, NULL);
    for (i = 0; monitors != NULL && i < monitors->len; i++) {
        cfg = &g_array_index(monitors, SpiceDisplayMonitorConfig, i);
        if (cfg->id == self.monitorID) {
            c = cfg;
            break;
        }
    }
    if (c == NULL) {
        DISPLAY_DEBUG(self, "update monitor: no monitor %d", (int)self.monitorID);
        self.ready = NO;
        if (spice_channel_test_capability(SPICE_CHANNEL(self.display),
                                          SPICE_DISPLAY_CAP_MONITORS_CONFIG)) {
            DISPLAY_DEBUG(self, "waiting until MonitorsConfig is received");
            g_clear_pointer(&monitors, g_array_unref);
            return;
        }
        goto whole;
    }
    
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
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;

    DISPLAY_DEBUG(self, "%s: got scanout",  __FUNCTION__);

    const SpiceGlScanout *scanout;

    scanout = spice_display_channel_get_gl_scanout(self.display);
    /* should only be called when the display has a scanout */
    g_return_if_fail(scanout != NULL);
    
    self.isGLEnabled = YES;
    self.hasGLDrawAck = YES;

    [self rebuildScanoutTextureWithScanout:*scanout];
}

static void cs_gl_draw(SpiceDisplayChannel *channel,
                       guint32 x, guint32 y, guint32 w, guint32 h,
                       gpointer data)
{
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;

    DISPLAY_DEBUG(self, "%s",  __FUNCTION__);

    self.isGLEnabled = YES;
    self.hasGLDrawAck = NO;
}

#pragma mark - Channel events

static void cs_channel_new(SpiceSession *s, SpiceChannel *channel, gpointer data) {
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    gint channel_id;
    
    g_object_get(channel, "channel-id", &channel_id, NULL);
    
    if (SPICE_IS_DISPLAY_CHANNEL(channel)) {
        SpiceDisplayPrimary primary;
        if (channel_id != self.channelID) {
            return;
        }
        self.display = SPICE_DISPLAY_CHANNEL(channel);
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_connect(channel, "display-primary-create",
                         G_CALLBACK(cs_primary_create), GLIB_OBJC_RETAIN(self));
        g_signal_connect(channel, "display-primary-destroy",
                         G_CALLBACK(cs_primary_destroy), GLIB_OBJC_RETAIN(self));
        g_signal_connect(channel, "display-invalidate",
                         G_CALLBACK(cs_invalidate), GLIB_OBJC_RETAIN(self));
        g_signal_connect_after(channel, "display-mark",
                               G_CALLBACK(cs_mark), GLIB_OBJC_RETAIN(self));
        g_signal_connect_after(channel, "notify::monitors",
                               G_CALLBACK(cs_update_monitor_area), GLIB_OBJC_RETAIN(self));
        g_signal_connect_after(channel, "gst-video-overlay",
                               G_CALLBACK(cs_set_overlay), GLIB_OBJC_RETAIN(self));
        g_signal_connect(channel, "notify::gl-scanout",
                         G_CALLBACK(cs_gl_scanout), GLIB_OBJC_RETAIN(self));
        g_signal_connect(channel, "gl-draw",
                         G_CALLBACK(cs_gl_draw), GLIB_OBJC_RETAIN(self));
        if (spice_display_channel_get_primary(channel, 0, &primary)) {
            cs_primary_create(channel, primary.format, primary.width, primary.height,
                              primary.stride, primary.shmid, primary.data, (__bridge void *)self);
            cs_mark(channel, primary.marked, (__bridge void *)self);
        }
        
        spice_channel_connect(channel);
        return;
    }
}

static void cs_channel_destroy(SpiceSession *s, SpiceChannel *channel, gpointer data) {
    CSDisplayMetal *self = (__bridge CSDisplayMetal *)data;
    gint channel_id;
    
    g_object_get(channel, "channel-id", &channel_id, NULL);
    DISPLAY_DEBUG(self, "channel_destroy %d", channel_id);
    
    if (SPICE_IS_DISPLAY_CHANNEL(channel)) {
        if (channel_id != self.channelID) {
            return;
        }
        cs_primary_destroy(self.display, (__bridge void *)self);
        self.display = NULL;
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_primary_create), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_primary_destroy), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_invalidate), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_mark), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_update_monitor_area), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_set_overlay), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_gl_scanout), GLIB_OBJC_RELEASE(self));
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_gl_draw), GLIB_OBJC_RELEASE(self));
        return;
    }
    
    return;
}

- (id<MTLDevice>)device {
    return _device;
}

- (void)setDevice:(id<MTLDevice>)device {
    _device = device;
    [self rebuildDisplayVertices];
    if (self.isGLEnabled) {
        if (self.glTexture) {
            // reuse surface from existing texture (
            [self rebuildScanoutTextureWithSurface:self.glTexture.iosurface width:self.glTexture.width height:self.glTexture.height];
        } else {
            // get scanout information from SPICE
            cs_gl_scanout(self.display, NULL, (__bridge void *)self);
        }
    } else {
        [self rebuildCanvasTexture];
    }
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

- (id<MTLTexture>)displayTexture {
    if (self.isGLEnabled) {
        return self.glTexture;
    } else {
        return self.canvasTexture;
    }
}

- (BOOL)isPrimaryDisplay {
    return self.channelID == 0 && self.monitorID == 0;
}

- (BOOL)isVisible {
    return YES; // always visible
}

- (BOOL)isInverted {
    return NO; // never inverted
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

#pragma mark - Methods

- (instancetype)initWithSession:(nonnull SpiceSession *)session channelID:(NSInteger)channelID monitorID:(NSInteger)monitorID {
    if (self = [super init]) {
        GList *list;
        GList *it;
        
        self.canvasLock = dispatch_semaphore_create(1);
        self.viewportScale = 1.0f;
        self.viewportOrigin = CGPointMake(0, 0);
        self.channelID = channelID;
        self.monitorID = monitorID;
        self.session = session;
        g_object_ref(session);
        
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_connect(session, "channel-new",
                         G_CALLBACK(cs_channel_new), GLIB_OBJC_RETAIN(self));
        g_signal_connect(session, "channel-destroy",
                         G_CALLBACK(cs_channel_destroy), GLIB_OBJC_RETAIN(self));
        list = spice_session_get_channels(session);
        for (it = g_list_first(list); it != NULL; it = g_list_next(it)) {
            if (SPICE_IS_MAIN_CHANNEL(it->data)) {
                cs_channel_new(session, it->data, (__bridge void *)self);
                break;
            }
        }
        for (it = g_list_first(list); it != NULL; it = g_list_next(it)) {
            if (!SPICE_IS_MAIN_CHANNEL(it->data))
                cs_channel_new(session, it->data, (__bridge void *)self);
        }
        g_list_free(list);
    }
    return self;
}

- (void)dealloc {
    if (self.display) {
        cs_channel_destroy(self.session, SPICE_CHANNEL(self.display), (__bridge void *)self);
    }
    if (self.main) {
        cs_channel_destroy(self.session, SPICE_CHANNEL(self.main), (__bridge void *)self);
    }
    SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
    g_signal_handlers_disconnect_by_func(self.session, G_CALLBACK(cs_channel_new), GLIB_OBJC_RELEASE(self));
    g_signal_handlers_disconnect_by_func(self.session, G_CALLBACK(cs_channel_destroy), GLIB_OBJC_RELEASE(self));
    g_object_unref(self.session);
    self.session = NULL;
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
        DISPLAY_DEBUG(self, "The monitor area is not intersecting primary surface");
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
    self.displayVertices = [self.device newBufferWithBytes:quadVertices
                                                    length:sizeof(quadVertices)
                                                   options:MTLResourceStorageModeShared];

    // Calculate the number of vertices by dividing the byte length by the size of each vertex
    self.displayNumVertices = sizeof(quadVertices) / sizeof(CSRenderVertex);
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

- (BOOL)visible {
    return self.ready;
}

- (void)requestResolution:(CGRect)bounds {
    SpiceMainChannel *main = self.main;
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
    SpiceDisplayChannel *display = self.display;
    if (display && self.isGLEnabled && !self.hasGLDrawAck) {
        [CSMain.sharedInstance asyncWith:^{
            spice_display_channel_gl_draw_done(display);
        }];
        self.hasGLDrawAck = YES;
    }
}

@end
