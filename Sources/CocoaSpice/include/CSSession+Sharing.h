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

#import "CSSession.h"

NS_ASSUME_NONNULL_BEGIN

/// Handles SPICE WebDAV based directory sharing
///
/// By default, if the server supports WebDAV directory sharing, the `Documents/Public` directory will be shared.
/// The caller can change this to any directory by calling `-setSharedDirectory:readOnly:`.
@interface CSSession (Sharing)

/// Get path to `Documents/Public` either in the app sandbox or in the user's home directory
@property (nonatomic, readonly) NSURL *defaultPublicShare;

/// Change the current shared directory
/// @param path Local path to share (must be readable)
/// @param readOnly Share as read-only to the server
- (void)setSharedDirectory:(NSString *)path readOnly:(BOOL)readOnly;

@end

NS_ASSUME_NONNULL_END
