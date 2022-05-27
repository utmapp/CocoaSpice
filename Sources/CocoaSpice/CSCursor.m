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

@end

@implementation CSCursor

#pragma mark - Cursor events

static void cs_cursor_invalidate(CSCursor *self)
{
    // We implement two different textures so invalidate is not needed
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
    
    cs_cursor_invalidate(self);
    
    CGPoint hotspot = CGPointMake(cursor_shape->hot_spot_x, cursor_shape->hot_spot_y);
    CGSize newSize = CGSizeMake(cursor_shape->width, cursor_shape->height);
    if (!CGSizeEqualToSize(newSize, self.cursorSize) || !CGPointEqualToPoint(hotspot, self.cursorHotspot)) {
        [self rebuildCursorWithSize:newSize center:hotspot];
    }
    [self drawCursor:cursor_shape->data];
    self.cursorHidden = NO;
    cs_cursor_invalidate(self);
    g_boxed_free(SPICE_TYPE_CURSOR_SHAPE, cursor_shape);
}

static void cs_cursor_move(SpiceCursorChannel *channel, gint x, gint y, gpointer data)
{
    CSCursor *self = (__bridge CSCursor *)data;
    
    cs_cursor_invalidate(self); // old pointer buffer
    
    self.mouseGuest = CGPointMake(x, y);
    
    cs_cursor_invalidate(self); // new pointer buffer
    
    /* apparently we have to restore cursor when "cursor_move" */
    if (self.hasCursor) {
        self.cursorHidden = NO;
    }
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

@synthesize device = _device;

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

- (void)setDevice:(id<MTLDevice>)device {
    _device = device;
    cs_cursor_set(self.channel, NULL, (__bridge void *)self);
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

#pragma mark - Initializers

- (instancetype)initWithChannel:(SpiceCursorChannel *)channel {
    if (self = [self init]) {
        gpointer cursor_shape;
        self.channel = g_object_ref(channel);
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
    g_signal_handlers_disconnect_by_func(self.channel, G_CALLBACK(cs_cursor_set), (__bridge void *)self);
    g_signal_handlers_disconnect_by_func(self.channel, G_CALLBACK(cs_cursor_move), (__bridge void *)self);
    g_signal_handlers_disconnect_by_func(self.channel, G_CALLBACK(cs_cursor_hide), (__bridge void *)self);
    g_signal_handlers_disconnect_by_func(self.channel, G_CALLBACK(cs_cursor_reset), (__bridge void *)self);
    g_object_unref(self.channel);
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
}

- (void)destroyCursor {
    self.numVertices = 0;
    self.vertices = nil;
    self.texture = nil;
    self.cursorSize = CGSizeZero;
    self.cursorHotspot = CGPointZero;
    self.hasCursor = NO;
}

- (void)drawCursor:(const void *)buffer {
    const NSInteger pixelSize = 4;
    MTLRegion region = {
        { 0, 0 }, // MTLOrigin
        { self.cursorSize.width, self.cursorSize.height, 1} // MTLSize
    };
    [self.texture replaceRegion:region
                    mipmapLevel:0
                      withBytes:buffer
                    bytesPerRow:self.cursorSize.width*pixelSize];
}

- (void)rendererFrameHasRendered {
    // do nothing
}

@end
