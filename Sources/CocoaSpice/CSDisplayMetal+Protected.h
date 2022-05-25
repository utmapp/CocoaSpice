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

#import "CSDisplayMetal.h"

typedef struct _SpiceSession SpiceSession;

NS_ASSUME_NONNULL_BEGIN

@interface CSDisplayMetal ()

/// SPICE GTK session
@property (nonatomic, readonly, nullable) SpiceSession *session;

/// Channel number for this display
@property (nonatomic, readonly) NSInteger channelID;

/// Monitor number for this display
@property (nonatomic, readonly) NSInteger monitorID;

/// True if currently rendering from GL backend
@property (nonatomic, readonly) BOOL isGLEnabled;

@property (nonatomic, nullable, weak, readwrite) CSCursor *cursor;

/// Create a new display for a given channel and monitor
/// @param session SPICE session handling this display
/// @param channelID Channel ID
/// @param monitorID Monitor ID
- (instancetype)initWithSession:(nonnull SpiceSession *)session channelID:(NSInteger)channelID monitorID:(NSInteger)monitorID NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
