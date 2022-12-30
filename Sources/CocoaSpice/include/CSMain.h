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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// SPICE client lifetime management
///
/// To use the SPICE client GTK library, you must call `-spiceStart` which spawns a worker thread.
/// @code
/// CSMain *spice = [CSMain sharedInstance];
/// [self.spice spiceSetDebug:YES]; // optional for debug logging
/// if (![self.spice spiceStart]) {
///     // worker failed to start, handle error
///     return;
/// }
/// // now you can use `CSConnection` or any other API
/// @endcode
@interface CSMain : NSObject

/// Is the worker thread running?
@property (nonatomic, readonly) BOOL running;

/// A `GMainContext` created by `-spiceStart`
/// Advanced users can use this with GLib to run in the worker thread's context
@property (nonatomic, readonly) void *glibMainContext;

/// Use this to get a pointer to this singleton
@property (class, nonatomic, readonly) CSMain *sharedInstance NS_SWIFT_NAME(shared);

- (instancetype)init NS_UNAVAILABLE;

/// Set verbose logging to stderr
/// @param enabled Enable debug logging
- (void)spiceSetDebug:(BOOL)enabled;

/// Create and start SPICE client worker thread
/// @attention This must be called before any other API usage
/// @return true if worker thread started successful, false otherwise
- (BOOL)spiceStart;

/// Stop and clean up SPICE client worker thread
/// @result It is unsafe to use any other API until `-spiceStart` is called again
- (void)spiceStop;

/// Run a block in the SPICE GTK main context
/// @param block Block to run
- (void)asyncWith:(dispatch_block_t)block;

/// Run a block with main context lock held
/// @param block Block to run
- (void)syncWith:(dispatch_block_t)block;

@end

NS_ASSUME_NONNULL_END
