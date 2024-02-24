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
#import "CSCursor+Protected.h"
#import "CSDisplay+Protected.h"
#import "CSInput+Protected.h"
#import "CSSession+Protected.h"
#import "CSPort+Protected.h"
#if defined(WITH_USB_SUPPORT)
#import "CSUSBDevice+Protected.h"
#import "CSUSBManager+Protected.h"
#endif
#import <glib.h>
#import <spice-client.h>
#import <spice/vd_agent.h>

@interface CSConnection ()

@property (nonatomic, readwrite) BOOL isTLSOnly;
@property (nonatomic, readwrite) CSSession *session;
@property (nonatomic, readwrite) CSUSBManager *usbManager;
@property (nonatomic, readwrite) NSMutableArray<CSChannel *> *mutableChannels;
@property (nonatomic, readwrite) SpiceSession *spiceSession;
@property (nonatomic, readwrite) SpiceMainChannel *spiceMain;
@property (nonatomic, readwrite) SpiceAudio *spiceAudio;

@end

@implementation CSConnection

static void cs_main_channel_event(SpiceChannel *channel, SpiceChannelEvent event,
                               gpointer data)
{
    CSConnection *self = (__bridge CSConnection *)data;
    const GError *error = NULL;
    NSString *genericMsg = NSLocalizedString(@"An error occurred trying to connect to SPICE.", @"CSConnection");
    NSInteger code = kCSConnectionErrorNone;
    
    switch (event) {
        case SPICE_CHANNEL_OPENED:
            g_message("main channel: opened");
            [self.delegate spiceConnected:self];
            break;
        case SPICE_CHANNEL_SWITCHING:
            g_message("main channel: switching host");
            break;
        case SPICE_CHANNEL_CLOSED:
            /* this event is only sent if the channel was succesfully opened before */
            g_message("main channel: closed");
            spice_session_disconnect(self.spiceSession);
            break;
        case SPICE_CHANNEL_ERROR_IO:
        case SPICE_CHANNEL_ERROR_TLS:
        case SPICE_CHANNEL_ERROR_LINK:
        case SPICE_CHANNEL_ERROR_CONNECT:
        case SPICE_CHANNEL_ERROR_AUTH:
            error = spice_channel_get_error(channel);
            if (error && event != SPICE_CHANNEL_ERROR_CONNECT) {
                g_message("channel error: %s", error->message);
            }
            switch (event) {
                case SPICE_CHANNEL_ERROR_IO: code = kCSConnectionErrorIO; break;
                case SPICE_CHANNEL_ERROR_TLS:
                case SPICE_CHANNEL_ERROR_LINK:
                case SPICE_CHANNEL_ERROR_AUTH: code = kCSConnectionErrorAuthentication; break;
                case SPICE_CHANNEL_ERROR_CONNECT: code = kCSConnectionErrorConnect; break;
                default: code = kCSConnectionErrorUnknown; break;
            }
            [self.delegate spiceError:self code:code message:(error ? [NSString stringWithUTF8String:error->message] : genericMsg)];
            break;
        default:
            /* TODO: more sophisticated error handling */
            g_warning("unknown main channel event: %u", event);
            /* connection_disconnect(conn); */
            break;
    }
}

static void cs_display_monitors(SpiceChannel *channel, GParamSpec *pspec,
                             gpointer data)
{
    CSConnection *self = (__bridge CSConnection *)data;
    GArray *cfgs = NULL;
    CSDisplay *display = nil;
    
    g_object_get(channel,
                 "monitors", &cfgs,
                 NULL);
    g_return_if_fail(cfgs != NULL);
    
    for (CSChannel *candidate in self.channels) {
        if (candidate.spiceChannel == channel) {
            assert([candidate isKindOfClass:CSDisplay.class]);
            display = (CSDisplay *)candidate;
            break;
        }
    }
    
    assert(display);
    
    SPICE_DEBUG("[CocoaSpice] display %ld now has %d monitors", display.channelID, cfgs->len);
    if (cfgs->len > 0) {
        g_assert(cfgs->len == 1);
        if (display.hasInitialConfig) {
            [self.delegate spiceDisplayUpdated:self display:display];
        } else {
            [self.delegate spiceDisplayCreated:self display:display];
            display.hasInitialConfig = YES;
        }
    } else {
        [self.delegate spiceDisplayDestroyed:self display:display];
    }
    
    g_clear_pointer(&cfgs, g_array_unref);
}

static void cs_main_agent_update(SpiceChannel *main, gpointer data)
{
    CSConnection *self = (__bridge CSConnection *)data;
    gboolean agent_connected = false;
    CSConnectionAgentFeature features = kCSConnectionAgentFeatureNone;
    
    g_object_get(main, "agent-connected", &agent_connected, NULL);
    SPICE_DEBUG("[CocoaSpice] SPICE agent connected: %d", agent_connected);
    if (agent_connected) {
        if (spice_main_channel_agent_test_capability(SPICE_MAIN_CHANNEL(main), VD_AGENT_CAP_MONITORS_CONFIG)) {
            features |= kCSConnectionAgentFeatureMonitorsConfig;
        }
        [self.delegate spiceAgentConnected:self supportingFeatures:features];
    } else {
        [self.delegate spiceAgentDisconnected:self];
    }
}

static void cs_port_opened(SpiceChannel *channel, GParamSpec *pspec,
                           gpointer user)
{
    CSConnection *self = (__bridge CSConnection *)user;
    CSPort *port = nil;
    
    for (CSPort *candidate in self.channels) {
        if (candidate.spiceChannel == channel) {
            assert([candidate isKindOfClass:CSPort.class]);
            port = (CSPort *)candidate;
            break;
        }
    }
    
    assert(port);
    SPICE_DEBUG("[CocoaSpice] port %s opened:%d", [port.name cStringUsingEncoding:NSASCIIStringEncoding], port.isOpen);

    if (port.isOpen) {
        [self.delegate spiceForwardedPortOpened:self port:port];
    } else {
        [self.delegate spiceForwardedPortClosed:self port:port];
    }
}

static void cs_channel_new(SpiceSession *s, SpiceChannel *channel, gpointer data)
{
    CSConnection *self = (__bridge CSConnection *)data;
    int chid;
    
    g_object_get(channel, "channel-id", &chid, NULL);
    SPICE_DEBUG("new channel (#%d)", chid);
    
    if (SPICE_IS_MAIN_CHANNEL(channel)) {
        SPICE_DEBUG("new main channel");
        g_assert(!self.spiceMain); // should only be 1 main channel
        self.spiceMain = SPICE_MAIN_CHANNEL(channel);
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_connect(channel, "channel-event",
                         G_CALLBACK(cs_main_channel_event), (__bridge void *)self);
        g_signal_connect(channel, "main_agent_update",
                         G_CALLBACK(cs_main_agent_update), (__bridge void *)self);
    }
    
    if (SPICE_IS_DISPLAY_CHANNEL(channel)) {
        SPICE_DEBUG("new display channel (#%d)", chid);
        CSDisplay *display = [[CSDisplay alloc] initWithChannel:SPICE_DISPLAY_CHANNEL(channel)];
        display.spiceMain = self.spiceMain;
        [self.mutableChannels addObject:display];
        g_signal_connect_after(channel, "notify::monitors",
                               G_CALLBACK(cs_display_monitors), (__bridge void *)self);
        display.isEnabled = YES;
        // find and connect to any existing cursor channel
        for (CSChannel *candidate in self.channels) {
            if ([candidate isKindOfClass:CSCursor.class] && candidate.channelID == chid) {
                CSCursor *cursor = (CSCursor *)candidate;
                display.cursor = cursor;
                break;
            }
        }
        spice_channel_connect(channel);
    }
    
    if (SPICE_IS_CURSOR_CHANNEL(channel)) {
        SPICE_DEBUG("new cursor channel (#%d)", chid);
        CSCursor *cursor = [[CSCursor alloc] initWithChannel:SPICE_CURSOR_CHANNEL(channel)];
        cursor.spiceMain = self.spiceMain;
        [self.mutableChannels addObject:cursor];
        // find and connect to any existing display channel
        for (CSChannel *candidate in self.channels) {
            if ([candidate isKindOfClass:CSDisplay.class] && candidate.channelID == chid) {
                CSDisplay *display = (CSDisplay *)candidate;
                display.cursor = cursor;
                break;
            }
        }
        spice_channel_connect(channel);
    }
    
    if (SPICE_IS_INPUTS_CHANNEL(channel)) {
        SPICE_DEBUG("new inputs channel");
        CSInput *input = [[CSInput alloc] initWithChannel:SPICE_INPUTS_CHANNEL(channel)];
        input.spiceMain = self.spiceMain;
        [self.mutableChannels addObject:input];
        [self.delegate spiceInputAvailable:self input:input];
        spice_channel_connect(channel);
    }
    
    if (SPICE_IS_PLAYBACK_CHANNEL(channel)) {
        SPICE_DEBUG("new audio channel");
        if (self.audioEnabled) {
            self.spiceAudio = spice_audio_get(s, [CSMain sharedInstance].glibMainContext);
            spice_channel_connect(channel);
        } else {
            SPICE_DEBUG("audio disabled");
        }
    }

    if (SPICE_IS_PORT_CHANNEL(channel)) {
        SPICE_DEBUG("new port channel");
        CSPort *port = [[CSPort alloc] initWithChannel:SPICE_PORT_CHANNEL(channel)];
        port.spiceMain = self.spiceMain;
        port.connection = self;
        [self.mutableChannels addObject:port];
        g_signal_connect_after(channel, "notify::port-opened",
                               G_CALLBACK(cs_port_opened), (__bridge void *)self);
        spice_channel_connect(channel);
    }
}

static void cs_channel_destroy(SpiceSession *s, SpiceChannel *channel, gpointer data)
{
    CSConnection *self = (__bridge CSConnection *)data;
    int chid;
    
    g_object_get(channel, "channel-id", &chid, NULL);
    if (SPICE_IS_MAIN_CHANNEL(channel)) {
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        SPICE_DEBUG("zap main channel");
        self.spiceMain = NULL;
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_main_channel_event), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_main_agent_update), (__bridge void *)self);
    }
    
    if (SPICE_IS_DISPLAY_CHANNEL(channel)) {
        SPICE_DEBUG("zap display channel (#%d)", chid);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_display_monitors), (__bridge void *)self);
    }
    
    if (SPICE_IS_INPUTS_CHANNEL(channel)) {
        SPICE_DEBUG("zap inputs channel");
    }
    
    if (SPICE_IS_PLAYBACK_CHANNEL(channel)) {
        SPICE_DEBUG("zap audio channel");
        self.spiceAudio = NULL;
    }
    
    if (SPICE_IS_PORT_CHANNEL(channel)) {
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_port_opened), (__bridge void *)self);
    }
    
    for (NSInteger i = self.mutableChannels.count-1; i >= 0; i--) {
        CSChannel* wrap = self.mutableChannels[i];
        if (wrap.spiceChannel == channel) {
            [self.mutableChannels removeObjectAtIndex:i];
            if (SPICE_IS_DISPLAY_CHANNEL(channel)) {
                [self.delegate spiceDisplayDestroyed:self display:(CSDisplay *)wrap];
            } else if (SPICE_IS_PORT_CHANNEL(channel)) {
                [self.delegate spiceForwardedPortClosed:self port:(CSPort *)wrap];
            } else if (SPICE_IS_INPUTS_CHANNEL(channel)) {
                [self.delegate spiceInputUnavailable:self input:(CSInput *)wrap];
            }
        }
    }

    // ideally we do this in cs_connection_destroy() but because that happens so late, it opens us up
    // to retain cycles if the caller waits for `spiceDisconnect:` to cleanup.
    if (self.channels.count == 0) {
        [self.delegate spiceDisconnected:self];
    }
}

static void cs_connection_destroy(SpiceSession *session,
                               gpointer data)
{
    CSConnection *self = (__bridge CSConnection *)data;
    SPICE_DEBUG("spice connection destroyed");
    // this happens pretty late--after every SpiceChannel has been deallocated
}

- (void)setHost:(NSString *)host {
    g_object_set(self.spiceSession, "host", [host UTF8String], NULL);
}

- (NSString *)host {
    gchar *strhost;
    g_object_get(self.spiceSession, "host", &strhost, NULL);
    NSString *nshost = [NSString stringWithUTF8String:strhost];
    g_free(strhost);
    return nshost;
}

- (void)setPort:(NSString *)port {
    g_object_set(self.spiceSession, self.isTLSOnly ? "tls-port" : "port", [port UTF8String], NULL);
}

- (NSString *)port {
    gchar *strhost;
    g_object_get(self.spiceSession, self.isTLSOnly ? "tls-port" : "port", &strhost, NULL);
    NSString *nshost = [NSString stringWithUTF8String:strhost];
    g_free(strhost);
    return nshost;
}

- (void)setUnixSocketURL:(NSURL *)unixSocketURL {
    g_object_set(self.spiceSession, "unix-path", unixSocketURL.relativePath.UTF8String, NULL);
    _unixSocketURL = unixSocketURL;
}

- (void)setTlsServerPublicKey:(NSData *)tlsServerPublicKey {
    GByteArray *array = NULL;

    if (!tlsServerPublicKey) {
        goto end;
    }
    array = g_byte_array_new();
    [tlsServerPublicKey enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        g_byte_array_append(array, bytes, (guint)byteRange.length);
    }];
    _tlsServerPublicKey = tlsServerPublicKey;
end:
    g_object_set(self.spiceSession, "pubkey", array, NULL);
    if (array) {
        g_byte_array_unref(array);
    }
}

- (NSString *)password {
    gchar *value;
    g_object_get(self.spiceSession, "password", &value, NULL);
    if (!value) {
        return nil;
    }
    NSString *nsvalue = [NSString stringWithUTF8String:value];
    g_free(value);
    return nsvalue;
}

- (void)setPassword:(NSString *)password {
    g_object_set(self.spiceSession, "password", [password UTF8String], NULL);
}

- (NSArray<CSChannel *> *)channels {
    return self.mutableChannels;
}

- (void)setSpiceMain:(SpiceMainChannel *)spiceMain {
    if (_spiceMain) {
        g_object_unref(_spiceMain);
    }
    _spiceMain = spiceMain ? g_object_ref(spiceMain) : NULL;
    for (CSChannel *channel in self.channels) {
        channel.spiceMain = spiceMain;
    }
}

- (void)dealloc {
    SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
    SpiceSession *spiceSession = self.spiceSession;
    gpointer data = (__bridge void *)self;

    [CSMain.sharedInstance syncWith:^{
        g_signal_handlers_disconnect_by_func(spiceSession, G_CALLBACK(cs_channel_new), data);
        g_signal_handlers_disconnect_by_func(spiceSession, G_CALLBACK(cs_channel_destroy), data);
        g_signal_handlers_disconnect_by_func(spiceSession, G_CALLBACK(cs_connection_destroy), data);
    }];
    for (NSInteger i = self.channels.count-1; i >= 0; i--) {
        CSChannel* wrap = self.channels[i];
        cs_channel_destroy(spiceSession, wrap.spiceChannel, data);
    }
    if (self.spiceMain) {
        cs_channel_destroy(spiceSession, SPICE_CHANNEL(self.spiceMain), data);
    }
    g_object_unref(spiceSession);
}

- (void)finishInit {
    SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
    g_signal_connect(self.spiceSession, "channel-new",
                     G_CALLBACK(cs_channel_new), (__bridge void *)self);
    g_signal_connect(self.spiceSession, "channel-destroy",
                     G_CALLBACK(cs_channel_destroy), (__bridge void *)self);
    g_signal_connect(self.spiceSession, "disconnected",
                     G_CALLBACK(cs_connection_destroy), (__bridge void *)self);
    
#if defined(WITH_USB_SUPPORT)
    SpiceUsbDeviceManager *manager = spice_usb_device_manager_get(self.spiceSession, NULL);
    g_assert(manager != NULL);
    self.usbManager = [[CSUSBManager alloc] initWithUsbDeviceManager:manager];
#endif
    self.session = [[CSSession alloc] initWithSession:self.spiceSession];
    self.mutableChannels = [NSMutableArray<CSChannel *> array];
}

- (instancetype)initWithHost:(NSString *)host port:(NSString *)port {
    if (self = [super init]) {
        self.spiceSession = spice_session_new();
        self.host = host;
        self.port = port;
        [self finishInit];
    }
    return self;
}

- (instancetype)initWithHost:(NSString *)host tlsPort:(NSString *)tlsPort serverPublicKey:(NSData *)serverPublicKey {
    gchar *channels[] = { "all", NULL };

    if (self = [super init]) {
        self.spiceSession = spice_session_new();
        self.isTLSOnly = YES;
        self.host = host;
        self.port = tlsPort;
        self.tlsServerPublicKey = serverPublicKey;
        g_object_set(self.spiceSession, "secure-channels", channels, NULL);
        [self finishInit];
    }
    return self;
}

- (instancetype)initWithUnixSocketFile:(NSURL *)socketFile {
    if (self = [super init]) {
        self.spiceSession = spice_session_new();
        self.unixSocketURL = socketFile;
        [self finishInit];
    }
    return self;
}

- (BOOL)connect {
    return spice_session_connect(self.spiceSession);
}

- (void)disconnect {
    spice_session_disconnect(self.spiceSession);
}

@end
