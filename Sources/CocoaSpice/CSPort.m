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

#import "CSPort.h"
#import "CocoaSpice.h"
#import <glib.h>
#import <spice-client.h>

static const NSInteger kMaxCacheBufferSize = 4096;

@interface CSPort ()

@property (nonatomic, readwrite) SpicePortChannel *channel;
@property (nonatomic, readwrite, weak) CSConnection *connection;
@property (nonatomic) NSMutableData *cacheBuffer;
@property (nonatomic) dispatch_queue_t portDataQueue;

@end

@implementation CSPort

#pragma mark - Channel event handlers

static void cs_port_opened(SpiceChannel *channel, GParamSpec *pspec,
                           gpointer user)
{
    CSPort *self = (__bridge CSPort *)user;

    if (!self.isOpen) {
        [self.delegate portDidDisconect:self];
    }
}

static void cs_port_data(SpicePortChannel *port,
                         gpointer data, int size, gpointer user)
{
    CSPort *self = (__bridge CSPort *)user;
    NSData *nsdata = [NSData dataWithBytes:data length:size];

	dispatch_async(self.portDataQueue, ^{
		id<CSPortDelegate> delegate = self.delegate;
		if (delegate) {
			[delegate port:self didRecieveData:nsdata];
		} else {
			[self.cacheBuffer appendData:nsdata];
			if (self.cacheBuffer.length > kMaxCacheBufferSize) {
				[self.cacheBuffer replaceBytesInRange:NSMakeRange(0, self.cacheBuffer.length-kMaxCacheBufferSize)
											withBytes:NULL
											   length:0];
			}
		}
	});
}

static void cs_port_event(SpicePortChannel *port, gint event)
{
    SPICE_DEBUG("[CocoaSpice] port event:%d", event);
}

static void cs_port_write_cb(GObject *source_object,
                             GAsyncResult *res,
                             gpointer user_data)
{
    CSPort *self = (__bridge_transfer CSPort *)user_data;
    SpicePortChannel *port = SPICE_PORT_CHANNEL(source_object);
    GError *error = NULL;

    spice_port_channel_write_finish(port, res, &error);
    if (error != NULL) {
        g_warning("[CocoaSpice] %s", error->message);
        [self.delegate port:self didError:[NSString stringWithCString:error->message encoding:NSASCIIStringEncoding]];
    }
    g_clear_error(&error);
}

#pragma mark - Initializers

- (instancetype)initWithChannel:(SpicePortChannel *)channel {
    if (self = [self init]) {
        self.cacheBuffer = [NSMutableData data];
        self.portDataQueue = dispatch_queue_create("CocoaSpice Port Data Queue", NULL);
        self.channel = g_object_ref(channel);
        g_signal_connect(channel, "notify::port-opened",
                         G_CALLBACK(cs_port_opened), (__bridge void *)self);
        g_signal_connect(channel, "port-data",
                         G_CALLBACK(cs_port_data), (__bridge void *)self);
        g_signal_connect(channel, "port-event",
                         G_CALLBACK(cs_port_event), (__bridge void *)self);
    }
    return self;
}

- (void)dealloc {
    SpicePortChannel *channel = self.channel;
    gpointer data = (__bridge void *)self;
    [CSMain.sharedInstance syncWith:^{
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_port_opened), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_port_data), data);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_port_event), data);
        g_object_unref(channel);
    }];
}

#pragma mark - Implementation

- (SpiceChannel *)spiceChannel {
    return SPICE_CHANNEL(self.channel);
}

- (NSString *)name {
    NSString *nsname = nil;
    gchar *name = NULL;
    g_object_get(self.channel,
                 "port-name", &name,
                 NULL);
    if (!name) {
        return nil;
    }
    nsname = [NSString stringWithCString:name encoding:NSASCIIStringEncoding];
    g_free(name);
    return nsname;
}

- (BOOL)isOpen {
    gboolean opened = FALSE;

    g_object_get(self.channel,
                 "port-opened", &opened,
                 NULL);
    
    return opened;
}

- (void)setDelegate:(id<CSPortDelegate>)delegate {
	dispatch_async(self.portDataQueue, ^{
		if (_delegate == NULL) {
			if (self.cacheBuffer.length > 0) {
				[delegate port:self didRecieveData:self.cacheBuffer];
			}
			self.cacheBuffer.length = 0;
		}
		_delegate = delegate;
	});
}

- (void)writeData:(NSData *)data {
    [CSMain.sharedInstance asyncWith:^{
        spice_port_channel_write_async(self.channel, data.bytes, data.length, NULL, cs_port_write_cb, (__bridge_retained void *)self);
    }];
}

@end
