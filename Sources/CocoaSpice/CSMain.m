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

#import "CSMain.h"
#import <glib.h>
#import <spice-client.h>
#import <pthread.h>
#import "gst_ios_init.h"

@interface CSMain ()

@property (nonatomic, readwrite) BOOL running;
@property (nonatomic) pthread_t spiceThread;

@end

@interface _CSMainBlock : NSObject

@property (nonatomic, copy) dispatch_block_t userBlock;
@property (nonatomic, nullable, strong) dispatch_group_t group;

@end

@implementation _CSMainBlock @end

@implementation CSMain {
    GMainContext *_main_context;
    GMainLoop *_main_loop;
}

static void logHandler(const gchar *log_domain, GLogLevelFlags log_level,
                       const gchar *message, gpointer user_data)
{
    GDateTime *now;
    gchar *dateTimeStr;
    const char *glog_domains = g_getenv("G_MESSAGES_DEBUG");
    LogHandler_t handler = (__bridge LogHandler_t)user_data;

    if (!spice_util_get_debug() &&
        ((log_level & (G_LOG_LEVEL_INFO | G_LOG_LEVEL_DEBUG)) != 0)) {
        return;
    }

    char* levelStr = "UNKNOWN";
    if (log_level & G_LOG_LEVEL_ERROR) {
        levelStr = "ERROR";
    } else if (log_level & G_LOG_LEVEL_CRITICAL) {
        levelStr = "CRITICAL";
    } else if (log_level & G_LOG_LEVEL_WARNING) {
        levelStr = "WARNING";
    } else if (log_level & G_LOG_LEVEL_MESSAGE) {
        levelStr = "MESSAGE";
    } else if (log_level & G_LOG_LEVEL_INFO) {
        levelStr = "INFO";
    } else if (log_level & G_LOG_LEVEL_DEBUG) {
        levelStr = "DEBUG";
    }
    
    now = g_date_time_new_now_local();
    dateTimeStr = g_date_time_format(now, "%Y-%m-%d %T");
    
    if (handler) {
        NSString *line = [NSString stringWithFormat:@"%s,%03d %s %s-%s\n", dateTimeStr,
                          g_date_time_get_microsecond(now) / 1000, levelStr,
                          log_domain, message];
        handler(line);
    } else {
        fprintf(stdout, "%s,%03d %s %s-%s\n", dateTimeStr,
                g_date_time_get_microsecond(now) / 1000, levelStr,
                log_domain, message);
    }
    
    g_date_time_unref(now);
    g_free(dateTimeStr);
}

void *spice_main_loop(void *args) {
    CSMain *self = (__bridge_transfer CSMain *)args;
    
    pthread_setname_np("SPICE Main Loop");
    gst_ios_init();
    
    g_main_context_ref(self->_main_context);
    g_main_context_push_thread_default(self->_main_context);
    g_main_loop_run(self->_main_loop);
    g_main_context_pop_thread_default(self->_main_context);
    g_main_context_unref(self->_main_context);
    
    return NULL;
}

+ (CSMain *)sharedInstance {
    static CSMain *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void *)glibMainContext {
    return _main_context;
}

- (void)setLogHandler:(LogHandler_t)newLogHandler {
    _logHandler = newLogHandler;
    g_log_set_default_handler(logHandler, (__bridge gpointer)newLogHandler);
}

- (id)init {
    self = [super init];
    if (self) {
        if ((_main_context = g_main_context_new()) == NULL) {
            return nil;
        }
        if ((_main_loop = g_main_loop_new(_main_context, FALSE)) == NULL) {
            g_main_context_unref(_main_context);
            return nil;
        }
        g_log_set_default_handler(logHandler, NULL);
    }
    return self;
}

- (void)dealloc {
    [self spiceStop];
    g_main_loop_unref(_main_loop);
    g_main_context_unref(_main_context);
    g_log_set_default_handler(g_log_default_handler, NULL);
}

- (void)spiceSetDebug:(BOOL)enabled {
    spice_util_set_debug(enabled);
}

- (BOOL)spiceStart {
    @synchronized (self) {
        if (!self.running) {
            pthread_t spiceThread;
            spice_util_set_main_context(_main_context);
            pthread_attr_t qosAttribute;
            pthread_attr_init(&qosAttribute);
            pthread_attr_set_qos_class_np(&qosAttribute, QOS_CLASS_USER_INTERACTIVE, 0);
            if (pthread_create(&spiceThread, &qosAttribute, &spice_main_loop, (__bridge_retained void *)self) != 0) {
                return NO;
            }
            self.running = YES;
            self.spiceThread = spiceThread;
        }
    }
    return YES;
}

- (void)spiceStop {
    @synchronized (self) {
        if (self.running) {
            void *status;
            spice_util_set_main_context(NULL);
            g_main_loop_quit(_main_loop);
            pthread_join(self.spiceThread, &status);
            self.running = NO;
            self.spiceThread = NULL;
        }
    }
}

static gboolean callBlockInMainContext(gpointer data) {
    _CSMainBlock *block = (__bridge _CSMainBlock *)data;
    block.userBlock();
    return FALSE;
}

static void cleanupBlock(gpointer data) {
    _CSMainBlock *block = (__bridge_transfer _CSMainBlock *)data;
    block.userBlock = nil;
    if (block.group) {
        dispatch_group_leave(block.group);
    }
}

- (void)asyncWithBlock:(_CSMainBlock *)block {
    gpointer data = (__bridge_retained void *)block;
    g_main_context_invoke_full(self.glibMainContext,
                               G_PRIORITY_DEFAULT,
                               callBlockInMainContext,
                               data,
                               cleanupBlock);
}

- (void)asyncWith:(dispatch_block_t)block {
    _CSMainBlock *_block = [[_CSMainBlock alloc] init];
    _block.userBlock = block;
    [self asyncWithBlock:_block];
}

- (void)syncWith:(dispatch_block_t)block {
    if (g_main_context_is_owner(self.glibMainContext)) {
        block();
    } else {
        _CSMainBlock *_block = [[_CSMainBlock alloc] init];
        dispatch_group_t mainContextGroup = dispatch_group_create();
        dispatch_group_enter(mainContextGroup);
        _block.userBlock = block;
        _block.group = mainContextGroup;
        [self asyncWithBlock:_block];
        dispatch_group_wait(mainContextGroup, DISPATCH_TIME_FOREVER);
    }
}

@end
