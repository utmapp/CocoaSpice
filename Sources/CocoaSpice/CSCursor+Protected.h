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

#import "CSCursor.h"

typedef struct _SpiceCursorChannel SpiceCursorChannel;

@class CSDisplay;

NS_ASSUME_NONNULL_BEGIN

@interface CSCursor ()

/// Display to render this cursor into
///
/// Used to get the display size in order to compute the right viewpoint origin.
@property (nonatomic, weak) CSDisplay *display;

/// Create a new cursor for a SPICE cursor channel
/// @param channel SPICE cursor channel
- (instancetype)initWithChannel:(SpiceCursorChannel *)channel NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
