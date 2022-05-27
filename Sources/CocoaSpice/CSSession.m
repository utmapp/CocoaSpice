//
// Copyright © 2020 osy. All rights reserved.
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
#import <glib.h>
#import <spice-client.h>
#import <spice/vd_agent.h>

const NSNotificationName kCSPasteboardChangedNotification = @"CSPasteboardChangedNotification";
const NSNotificationName kCSPasteboardRemovedNotification = @"CSPasteboardRemovedNotification";

@interface CSSession ()

@property (nonatomic, readwrite, nullable) SpiceSession *session;
@property (nonatomic, readonly) BOOL sessionReadOnly;
@property (nonatomic, nullable) SpiceMainChannel *main;

@end

@interface CSSession (Sharing)

- (void)createDefaultShareReadme;

@end

@implementation CSSession

static CSPasteboardType cspbTypeForClipboardType(guint type)
{
    switch (type) {
        case VD_AGENT_CLIPBOARD_UTF8_TEXT: {
            return kCSPasteboardTypeString;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_PNG: {
            return kCSPasteboardTypePng;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_BMP: {
            return kCSPasteboardTypeBmp;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_TIFF: {
            return kCSPasteboardTypeTiff;
        }
        case VD_AGENT_CLIPBOARD_IMAGE_JPG: {
            return kCSPasteboardTypeJpg;
        }
        default: {
            break;
        }
    }
    return kCSPasteboardTypeString;
}

// helper from spice-util.c

typedef enum {
    NEWLINE_TYPE_LF,
    NEWLINE_TYPE_CR_LF
} NewlineType;

static gssize get_line(const gchar *str, gsize len,
                       NewlineType type, gsize *nl_len)
{
    const gchar *p, *endl;
    gsize nl = 0;

    endl = (type == NEWLINE_TYPE_CR_LF) ? "\r\n" : "\n";
    p = g_strstr_len(str, len, endl);
    if (p) {
        len = p - str;
        nl = strlen(endl);
    }

    *nl_len = nl;
    return len;
}

static gchar* spice_convert_newlines(const gchar *str, gssize len,
                                     NewlineType from,
                                     NewlineType to)
{
    gssize length;
    gsize nl;
    GString *output;
    gint i;

    g_return_val_if_fail(str != NULL, NULL);
    g_return_val_if_fail(len >= -1, NULL);
    /* only 2 supported combinations */
    g_return_val_if_fail((from == NEWLINE_TYPE_LF &&
                          to == NEWLINE_TYPE_CR_LF) ||
                         (from == NEWLINE_TYPE_CR_LF &&
                          to == NEWLINE_TYPE_LF), NULL);

    if (len == -1)
        len = strlen(str);
    /* sometime we get \0 terminated strings, skip that, or it fails
       to utf8 validate line with \0 end */
    else if (len > 0 && str[len-1] == 0)
        len -= 1;

    /* allocate worst case, if it's small enough, we don't care much,
     * if it's big, malloc will put us in mmap'd region, and we can
     * over allocate.
     */
    output = g_string_sized_new(len * 2 + 1);

    for (i = 0; i < len; i += length + nl) {
        length = get_line(str + i, len - i, from, &nl);
        if (length < 0)
            break;

        g_string_append_len(output, str + i, length);

        if (nl) {
            /* let's not double \r if it's already in the line */
            if (to == NEWLINE_TYPE_CR_LF &&
                (output->len == 0 || output->str[output->len - 1] != '\r'))
                g_string_append_c(output, '\r');

            g_string_append_c(output, '\n');
        }
    }

    return g_string_free(output, FALSE);
}

G_GNUC_INTERNAL
gchar* spice_dos2unix(const gchar *str, gssize len)
{
    return spice_convert_newlines(str, len,
                                  NEWLINE_TYPE_CR_LF,
                                  NEWLINE_TYPE_LF);
}

G_GNUC_INTERNAL
gchar* spice_unix2dos(const gchar *str, gssize len)
{
    return spice_convert_newlines(str, len,
                                  NEWLINE_TYPE_LF,
                                  NEWLINE_TYPE_CR_LF);
}

static void cs_clipboard_got_from_guest(SpiceMainChannel *main, guint selection,
                                        guint type, const guchar *data, guint size,
                                        gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;

    SPICE_DEBUG("clipboard got data");
    
    if (type == VD_AGENT_CLIPBOARD_UTF8_TEXT) {
        gchar *conv = NULL;
        /* on windows, gtk+ would already convert to LF endings, but
           not on unix */
        if (spice_main_channel_agent_test_capability(self.main, VD_AGENT_CAP_GUEST_LINEEND_CRLF)) {
            conv = spice_dos2unix((gchar*)data, size);
            size = (guint)strlen(conv);
        }
        NSString *string = [NSString stringWithUTF8String:(conv ? conv : (const char *)data)];
        [self.pasteboardDelegate setString:string];
        g_free(conv);
    } else {
        CSPasteboardType cspbType = cspbTypeForClipboardType(type);
        NSData *pasteData = [NSData dataWithBytes:data length:size];
        [self.pasteboardDelegate setData:pasteData forType:cspbType];
    }
}

static gboolean cs_clipboard_grab(SpiceMainChannel *main, guint selection,
                                  guint32* types, guint32 ntypes,
                                  gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    
    if (selection != VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD) {
        SPICE_DEBUG("skipping grab unimplemented selection: %d", selection);
        return FALSE;
    }

    if (self.sessionReadOnly || !self.shareClipboard) {
        SPICE_DEBUG("ignoring clipboard_grab");
        return TRUE;
    }

    [CSMain.sharedInstance asyncWith:^{
        for (int n = 0; n < ntypes; ++n) {
            spice_main_channel_clipboard_selection_request(main, selection,
                                                           types[n]);
        }
    }];

    return TRUE;
}

static gboolean cs_clipboard_request(SpiceMainChannel *main, guint selection,
                                     guint type, gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    
    if (selection != VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD) {
        SPICE_DEBUG("skipping request unimplemented selection: %d", selection);
        return FALSE;
    }

    if (self.sessionReadOnly || !self.shareClipboard) {
        SPICE_DEBUG("ignoring clipboard_request");
        return FALSE;
    }

    CSPasteboardType cspbType = cspbTypeForClipboardType(type);
    NSData *data = [self.pasteboardDelegate dataForType:cspbType];
    if (data) {
        [CSMain.sharedInstance asyncWith:^{
            spice_main_channel_clipboard_selection_notify(main, selection, type, data.bytes, data.length);
        }];
    }

    return TRUE;
}

static void cs_clipboard_release(SpiceMainChannel *main, guint selection,
                                 gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;
    [self.pasteboardDelegate clearContents];
}

static void cs_channel_new(SpiceSession *session, SpiceChannel *channel,
                           gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;

    if (SPICE_IS_MAIN_CHANNEL(channel)) {
        SPICE_DEBUG("Changing main channel from %p to %p", self.main, channel);
        self.main = g_object_ref(SPICE_MAIN_CHANNEL(channel));
        g_signal_connect(channel, "main-clipboard-selection-grab",
                         G_CALLBACK(cs_clipboard_grab), (__bridge void *)self);
        g_signal_connect(channel, "main-clipboard-selection-request",
                         G_CALLBACK(cs_clipboard_request), (__bridge void *)self);
        g_signal_connect(channel, "main-clipboard-selection-release",
                         G_CALLBACK(cs_clipboard_release), (__bridge void *)self);
        g_signal_connect(channel, "main-clipboard-selection",
                         G_CALLBACK(cs_clipboard_got_from_guest), (__bridge void *)self);
    }
}

static void cs_channel_destroy(SpiceSession *session, SpiceChannel *channel,
                               gpointer user_data)
{
    CSSession *self = (__bridge CSSession *)user_data;

    if (SPICE_IS_MAIN_CHANNEL(channel)) {
        g_assert(SPICE_MAIN_CHANNEL(channel) == self.main);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_grab), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_request), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_release), (__bridge void *)self);
        g_signal_handlers_disconnect_by_func(channel, G_CALLBACK(cs_clipboard_got_from_guest), (__bridge void *)self);
        g_object_unref(self.main);
        self.main = NULL;
    }
}

#pragma mark - Initializers

- (id)init {
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardDidChange:)
                                                     name:kCSPasteboardChangedNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardDidRemove:)
                                                     name:kCSPasteboardRemovedNotification
                                                   object:nil];
        self.shareClipboard = YES;
    }
    return self;
}

- (id)initWithSession:(nonnull SpiceSession *)session {
    self = [self init];
    if (self) {
        GList *list;
        GList *it;
        
        self.session = g_object_ref(session);
        
        // g_get_user_special_dir(G_USER_DIRECTORY_PUBLIC_SHARE) returns NULL so we replace it with a valid value here
        [self createDefaultShareReadme];
        [self setSharedDirectory:self.defaultPublicShare.path readOnly:NO];
        
        SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
        g_signal_connect(session, "channel-new",
                         G_CALLBACK(cs_channel_new), (__bridge void *)self);
        g_signal_connect(session, "channel-destroy",
                         G_CALLBACK(cs_channel_destroy), (__bridge void *)self);
        list = spice_session_get_channels(session);
        for (it = g_list_first(list); it != NULL; it = g_list_next(it)) {
            cs_channel_new(session, it->data, (__bridge void *)self);
        }
        g_list_free(list);
    }
    return self;
}

- (void)dealloc {
    SPICE_DEBUG("[CocoaSpice] %s:%d", __FUNCTION__, __LINE__);
    g_signal_handlers_disconnect_by_func(self.session, G_CALLBACK(cs_channel_new), (__bridge void *)self);
    g_signal_handlers_disconnect_by_func(self.session, G_CALLBACK(cs_channel_destroy), (__bridge void *)self);
    cs_channel_destroy(self.session, SPICE_CHANNEL(self.main), (__bridge void *)self);
    g_object_unref(self.session);
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kCSPasteboardChangedNotification
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kCSPasteboardRemovedNotification
                                                  object:nil];
}

#pragma mark - Notification handler

- (void)pasteboardDidChange:(NSNotification *)notification {
    SpiceMainChannel *main = self.main;
    SPICE_DEBUG("[CocoaSpice] seen UIPasteboardChangedNotification");
    if (!main || !self.shareClipboard || self.sessionReadOnly || !self.pasteboardDelegate) {
        return;
    }
    guint32 type = VD_AGENT_CLIPBOARD_NONE;
    id<CSPasteboardDelegate> pb = self.pasteboardDelegate;
    if ([pb canReadItemForType:kCSPasteboardTypePng]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_PNG;
    } else if ([pb canReadItemForType:kCSPasteboardTypeBmp]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_BMP;
    } else if ([pb canReadItemForType:kCSPasteboardTypeTiff]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_TIFF;
    } else if ([pb canReadItemForType:kCSPasteboardTypeJpg]) {
        type = VD_AGENT_CLIPBOARD_IMAGE_JPG;
    } else if ([pb canReadItemForType:kCSPasteboardTypeString]) {
        type = VD_AGENT_CLIPBOARD_UTF8_TEXT;
    } else {
        SPICE_DEBUG("[CocoaSpice] pasteboard with unrecognized type");
    }
    if (spice_main_channel_agent_test_capability(self.main, VD_AGENT_CAP_CLIPBOARD_BY_DEMAND)) {
        [CSMain.sharedInstance asyncWith:^{
            guint32 _type = type;
            spice_main_channel_clipboard_selection_grab(main, VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD, &_type, 1);
        }];
    }
}

- (void)pasteboardDidRemove:(NSNotification *)notification {
    SpiceMainChannel *main = self.main;
    SPICE_DEBUG("[CocoaSpice] seen UIPasteboardRemovedNotification");
    if (!main || !self.shareClipboard || self.sessionReadOnly) {
        return;
    }
    if (spice_main_channel_agent_test_capability(self.main, VD_AGENT_CAP_CLIPBOARD_BY_DEMAND)) {
        [CSMain.sharedInstance asyncWith:^{
            guint32 type = VD_AGENT_CLIPBOARD_UTF8_TEXT;
            spice_main_channel_clipboard_selection_grab(main, VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD, &type, 1);
        }];
    }
}

#pragma mark - Instance methods

- (BOOL)sessionReadOnly {
    return spice_session_get_read_only(_session);
}
        
/* This will convert line endings if needed (between Windows/Unix conventions),
 * and will make sure 'len' does not take into account any trailing \0 as this could
 * cause some confusion guest side.
 * The 'len' argument will be modified by this function to the length of the modified
 * string
 */
- (NSString *)fixupClipboardText:(NSString *)text {
    if (spice_main_channel_agent_test_capability(self.main,
                                                 VD_AGENT_CAP_GUEST_LINEEND_CRLF)) {
        char *conv = NULL;
        conv = spice_unix2dos([text cStringUsingEncoding:NSUTF8StringEncoding], text.length);
        text = [NSString stringWithUTF8String:conv];
        g_free(conv);
    }
    return text;
}

@end
