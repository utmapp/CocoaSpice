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
#import "CSPortDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// Handles port forwarding through SPICE
///
/// In order to handle races in channel connection and application handling,
/// a cache buffer of 4096 bytes will store any incoming data before `delegate` is set.
@interface CSPort : NSObject

/// Delegate to handle port events
///
/// When set, any cached data will be sent via `- port:didRecieveData:`
@property (nonatomic, weak) id<CSPortDelegate> delegate;

/// Name of the port
@property (nonatomic, nullable, readonly) NSString *name;

/// Port is open at the other end
@property (nonatomic, readonly) BOOL isOpen;

/// Write data to port
/// @param data Data to write
- (void)writeData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
