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

@class CSConnection;
@class CSDisplayMetal;
@class CSInput;
@class CSPort;
@class CSSession;

/// Supported feature flags used in `-spiceAgentConnected:supportingFeatures:`
typedef NS_OPTIONS(NSInteger, CSConnectionAgentFeature) {
    /// Empty flag
    kCSConnectionAgentFeatureNone,
    
    /// Supports dynamic resizing of monitor resolution
    kCSConnectionAgentFeatureMonitorsConfig
};

/// Supported error codes
typedef NS_ENUM(NSInteger, CSConnectionError) {
    /// No error
    kCSConnectionErrorNone,
    
    /// Connection error
    kCSConnectionErrorConnect,
    
    /// Authentication error
    kCSConnectionErrorAuthentication,
    
    /// I/O error
    kCSConnectionErrorIO,
    
    /// Other error
    kCSConnectionErrorUnknown,
};

NS_ASSUME_NONNULL_BEGIN

/// Implement this protocol to handle `CSConnection` events
@protocol CSConnectionDelegate <NSObject>

/// Client connected
/// @param connection The connection
- (void)spiceConnected:(CSConnection *)connection;

/// Client disconnected
/// @param connection The connection
- (void)spiceDisconnected:(CSConnection *)connection;

/// Client was not able to connect due to an error
/// @param connection The connection
/// @param msg Error message (in English)
- (void)spiceError:(CSConnection *)connection code:(CSConnectionError)code message:(nullable NSString *)message;

/// Client created a new display
/// @param connection The connection
/// @param display The display created
- (void)spiceDisplayCreated:(CSConnection *)connection display:(CSDisplayMetal *)display;

/// Client closed a display
/// @param connection The connection
/// @param display The display that was closed
- (void)spiceDisplayDestroyed:(CSConnection *)connection display:(CSDisplayMetal *)display;

/// Client running SPICE guest tools connected
/// @param connection The connection
/// @param features A bit-masked set of flags listing supported features
- (void)spiceAgentConnected:(CSConnection *)connection supportingFeatures:(CSConnectionAgentFeature)features;

/// Client running SPICE guest tools disconnected
/// @param connection The connection
- (void)spiceAgentDisconnected:(CSConnection *)connection;

/// Client opened a new port channel
/// @param connection The connection
/// @param port Port channel that is created.
- (void)spiceForwardedPortOpened:(CSConnection *)connection port:(CSPort *)port;

/// Client closed a port channel
/// @param connection The connection
/// @param port Port channel that is destroyed.
- (void)spiceForwardedPortClosed:(CSConnection *)connection port:(CSPort *)port;

@end

NS_ASSUME_NONNULL_END
