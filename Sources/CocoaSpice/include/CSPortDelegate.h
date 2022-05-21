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

@class CSPort;

NS_ASSUME_NONNULL_BEGIN

/// Get data from SPICE port channel
/// @related CSPort
@protocol CSPortDelegate <NSObject>

/// Port channel disconnected from SPICE server
/// @param port The port connection
- (void)portDidDisconect:(CSPort *)port;

/// An error occurred handling the port
/// @param port The port connection
/// @param error A non-localized error message
- (void)port:(CSPort *)port didError:(NSString *)error;

/// Port channel recieved data
/// @param port The port conection
/// @param data Data to write to the channel
- (void)port:(CSPort *)port didRecieveData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
