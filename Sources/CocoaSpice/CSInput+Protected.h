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

#import "CSInput.h"

typedef struct _SpiceInputsChannel SpiceInputsChannel;
typedef struct _SpiceMainChannel SpiceMainChannel;

NS_ASSUME_NONNULL_BEGIN

@interface CSInput ()

/// SPICE inputs channel
@property (nonatomic, readonly) SpiceInputsChannel *channel;

/// SPICE main channel
///
/// This must be set before server/client mode switching can occur
@property (nonatomic, readwrite, nullable) SpiceMainChannel *main;

/// Create a new input for a SPICE inputs channel
/// @param channel SPICE inputs channel
- (instancetype)initWithChannel:(SpiceInputsChannel *)channel NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
