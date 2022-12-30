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

#import "CocoaSpice.h"
#import "CSChannel+Protected.h"
#import "CSDisplay+Protected.h"
#import <glib.h>
#import <spice-client.h>

@interface CSCursor ()

@property (nonatomic, weak) CSDisplay *display;
@property (nonatomic, readwrite) SpiceCursorChannel *channel;
@property (nonatomic, readwrite) CGSize cursorSize;
@property (nonatomic, readwrite) CGPoint cursorHotspot;
@property (nonatomic, readwrite) BOOL hasCursor;
@property (nonatomic, readwrite) BOOL cursorHidden;
@property (nonatomic) CGPoint mouseGuest;

@property (nonatomic, nullable, readwrite) id<MTLTexture> texture;
@property (nonatomic, readwrite) NSUInteger numVertices;
@property (nonatomic, nullable, readwrite) id<MTLBuffer> vertices;
@property (nonatomic) dispatch_queue_t cursorQueue;

@end

@implementation CSCursor

#pragma mark - Cursor events

static void cs_cursor_invalidate(CSCursor *self)
{
    CSDisplay *display = self.display;
    if (!display) {
        return;
    }
    // we need to synchronize with both the cursor draw queue and the display draw queue
    dispatch_async(self.cursorQueue, ^{
        dispatch_sync(display.displayQueue, ^{
            [self.rendererDelegate drawRenderSource:display];
        });
    });
}

static void cs_cursor_set(SpiceCursorChannel *channel,
                          G_GNUC_UNUSED GParamSpec *pspec,
                          gpointer data)
{
    CSCursor *self = (__bridge CSCursor *)data;
    SpiceCursorShape *cursor_shape;
    
    g_object_get(G_OBJECT(channel), "cursor", &cursor_shape, NULL);
    if (G_UNLIKELY(cursor_shape == NULL || cursor_shape->data == NULL)) {
        if (cursor_shape != NULL) {
            g_boxed_free(SPICE_TYPE_CURSOR_SHAPE, cursor_shape);
        }
        return;
    }
    
    CGPoint hotspot = CGPointMake(cursor_shape->hot_spot_x, cursor_shape->hot_spot_y);
    CGSize newSize = CGSizeMake(cursor_shape->width, cursor_shape->height);
    if (!CGSizeEqualToSize(newSize, self.cursorSize) || !CGPointEqualToPoint(hotspot, self.cursorHotspot)) {
        [self rebuildCursorWithSize:newSize center:hotspot];
    }
    [self drawCursor:cursor_shape->data];
    dispatch_async(self.cursorQueue, ^{
        // this has to be after drawCursor: which runs in the same serial queue
        g_boxed_free(SPICE_TYPE_CURSOR_SHAPE, cursor_shape);
    });
    self.cursorHidden = NO;
    cs_cursor_invalidate(self);
}

static void cs_cursor_move(SpiceCursorChannel *channel, gint x, gint y, gpointer data)
{
    CSCursor *self = (__bridge CSCursor *)data;
    
    self.mouseGuest = CGPointMake(x, y);
    
    /* apparently we have to restore cursor when "cursor_move" */
    if (self.hasCursor) {
        self.cursorHidden = NO;
    }
    
    cs_cursor_invalidate(self);
}

static void cs_cursor_hide(SpiceCursorChannel *channel, gpointer data)
{
    CSCursor *self = (__bridge CSCursor *)data;
    
    self.cursorHidden = YES;
    cs_cursor_invalidate(self);
}

static void cs_cursor_reset(SpiceCursorChannel *channel, gpointer data)
{
    CSCursor *self = (__bridge CSCursor *)data;
    
    SPICE_DEBUG("[CocoaSpice] %s",  __FUNCTION__);
    [self destroyCursor];
    cs_cursor_invalidate(self);
}

#pragma mark - Main events

static void cs_update_mouse_mode(SpiceChannel *channel, gpointer data)
{
    CSCursor *self = (__bridge CSCursor *)data;
    enum SpiceMouseMode mouse_mode;
    
    g_object_get(channel, "mouse-mode", &mouse_mode, NULL);
    SPICE_DEBUG("[CocoaSpice] mouse mode %u", mouse_mode);
    
    if (mouse_mode == SPICE_MOUSE_MODE_SERVER) {
        self.mouseGuest = CGPointMake(-1, -1);
    }
}

#pragma mark - Properties

- (SpiceChannel *)spiceChannel {
    return SPICE_CHANNEL(self.channel);
}

- (void)setSpiceMain:(SpiceMainChannel *)spiceMain {
    if (self.spiceMain) {
        g_signal_handlers_disconnect_by_func(SPICE_CHANNEL(self.spiceMain), G_CALLBACK(cs_update_mouse_mode), (__bridge void *)self);
    }
    [super setSpiceMain:spiceMain];
    if (spiceMain) {
        g_signal_connect(spiceMain, "main-mouse-update",
                         G_CALLBACK(cs_update_mouse_mode), (__bridge void *)self);
        cs_update_mouse_mode(SPICE_CHANNEL(spiceMain), (__bridge void *)self);
    }
}

- (void)setDisplay:(CSDisplay *)display {
    _display = display;
    cs_cursor_set(self.channel, NULL, (__bridge void *)self);
}

- (void)setDevice:(id<MTLDevice>)device {
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"setDevice: is unavailable on an CSCursor instance. Please set the device and cursor property on CSDisplay." userInfo:nil];
}

- (id<MTLDevice>)device {
    return self.display.device;
}

- (id<CSRenderSourceDelegate>)rendererDelegate {
    return self.display.rendererDelegate;
}

- (void)setRendererDelegate:(id<CSRenderSourceDelegate>)rendererDelegate {
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"setRendererDelegate: is unavailable on an CSCursor instance. Please set the rendererDelegate and cursor property on CSDisplay." userInfo:nil];
}

- (BOOL)isVisible {
    return !self.isInhibited && self.hasCursor && !self.cursorHidden;
}

- (BOOL)isInverted {
    return !self.display.isGLEnabled;
}

- (BOOL)hasAlpha {
    return YES; // blend alpha
}

- (id<CSRenderSource>)cursorSource {
    return nil; // no such thing as a cursor for a cursor
}

- (CGPoint)viewportOrigin {
    CSDisplay *display = self.display;
    if (!display) {
        return CGPointZero;
    }
    CGPoint point = self.mouseGuest;
    point.x -= display.displaySize.width/2;
    point.y -= display.displaySize.height/2;
    point.x *= display.viewportScale;
    point.y *= display.viewportScale;
    return point;
}

- (CGFloat)viewportScale {
    return self.display.viewportScale; // matching scale
}

- (BOOL)hasBlitCommands {
    return NO;
}

#pragma mark - Initializers

- (instancetype)initWithChannel:(SpiceCursorChannel *)channel {
    if (self = [self init]) {
        gpointer cursor_shape;
        self.channel = g_object_ref(channel);
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        self.cursorQueue = dispatch_queue_create("CocoaSpice Cursor Queue", attr);
        g_signal_connect(channel, "notify::cursor",
                         G_CALLBACK(cs_cursor_set), (__bridge void *)self);
        g_signal_connect(channel, "cursor-move",
                         G_CALLBACK(cs_cursor_move), (__bridge void *)self);
        g_signal_connect(channel, "cursor-hide",
                         G_CALLBACK(cs_cursor_hide), (__bridge void *)self);
        g_signal_connect(channel, "cursor-reset",
                         G_CALLBACK(cs_cursor_reset), (__bridge void *)self);
        g_object_get(G_OBJECT(channel), "cursor", &cursor_shape, NULL);
        if (cursor_shape != NULL) {
            g_boxed_free(SPICE_TYPE_CURSOR_SHAPE, cursor_shape);
            cs_cursor_set(self.channel, NULL, (__bridge void *)self);
        }
    }
    return self;
}

- (void)dealloc {
    SpiceCursorChannel *channel = self.channel;
    gpointer data = (__bridge void *)self;
    [CSMain.sharedInstance syncWith:^{
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_cursor_set), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_cursor_move), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_cursor_hide), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_cursor_reset), data);
    }];
    g_object_unref(channel);
}

#pragma mark - Cursor drawing

- (void)rebuildCursorWithSize:(CGSize)size center:(CGPoint)hotspot {
    // hotspot is the offset in buffer for the center of the pointer
    if (!self.device) {
        SPICE_DEBUG("[CocoaSpice] MTL device not ready for cursor draw");
        return;
    }
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    // don't worry that that components are reversed, we fix it in shaders
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDescriptor.width = size.width;
    textureDescriptor.height = size.height;
    textureDescriptor.usage = MTLTextureUsageShaderRead;
    dispatch_async(self.cursorQueue, ^{
        self.texture = [self.device newTextureWithDescriptor:textureDescriptor];
        
        // We flip the y-coordinates because pixman renders flipped
        CSRenderVertex quadVertices[] =
        {
            // Pixel positions, Texture coordinates
            { { -hotspot.x + size.width, hotspot.y               },  { 1.f, 0.f } },
            { { -hotspot.x             , hotspot.y               },  { 0.f, 0.f } },
            { { -hotspot.x             , hotspot.y - size.height },  { 0.f, 1.f } },
            
            { { -hotspot.x + size.width, hotspot.y               },  { 1.f, 0.f } },
            { { -hotspot.x             , hotspot.y - size.height },  { 0.f, 1.f } },
            { { -hotspot.x + size.width, hotspot.y - size.height },  { 1.f, 1.f } },
        };
        
        // Create our vertex buffer, and initialize it with our quadVertices array
        self.vertices = [self.device newBufferWithBytes:quadVertices
                                                 length:sizeof(quadVertices)
                                                options:MTLResourceStorageModeShared];
        
        // Calculate the number of vertices by dividing the byte length by the size of each vertex
        self.numVertices = sizeof(quadVertices) / sizeof(CSRenderVertex);
        self.cursorSize = size;
        self.cursorHotspot = hotspot;
        self.hasCursor = YES;
    });
}

- (void)destroyCursor {
    dispatch_async(self.cursorQueue, ^{
        self.numVertices = 0;
        self.vertices = nil;
        self.texture = nil;
        self.cursorSize = CGSizeZero;
        self.cursorHotspot = CGPointZero;
        self.hasCursor = NO;
    });
}

- (void)drawCursor:(const void *)buffer {
    dispatch_async(self.cursorQueue, ^{
        CGSize cursorSize = self.cursorSize;
        if (CGSizeEqualToSize(cursorSize, CGSizeZero)) {
            return;
        }
        const NSInteger pixelSize = 4;
        MTLRegion region = {
            { 0, 0 }, // MTLOrigin
            { cursorSize.width, cursorSize.height, 1} // MTLSize
        };
        [self.texture replaceRegion:region
                        mipmapLevel:0
                          withBytes:buffer
                        bytesPerRow:cursorSize.width*pixelSize];
    });
}

- (void)rendererUpdateTextureWithBlitCommandEncoder:(id<MTLBlitCommandEncoder>)blitCommandEncoder {
    // do nothing
}

- (void)rendererFrameHasRendered {
    // do nothing
}

- (void)moveTo:(CGPoint)point {
    self.mouseGuest = point;
    cs_cursor_invalidate(self);
}

@end
