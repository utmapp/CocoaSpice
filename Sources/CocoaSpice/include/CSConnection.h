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
#import "CSConnectionDelegate.h"
#import "CSChannel.h"

@class CSDisplay;
@class CSUSBManager;

NS_ASSUME_NONNULL_BEGIN

/// Main interface to CocoaSpice
///
/// Use this class to manage connections to SPICE and use the properties to interface with the client.
@interface CSConnection : NSObject

/// Session options including clipboard settings. Always non-null even when not connected.
@property (nonatomic, readonly) CSSession *session;

/// Contains all connected channels that CocoaSpice can handle
@property (nonatomic, readonly) NSArray<CSChannel *> *channels;

/// USB forwarding options
@property (nonatomic, readonly) CSUSBManager *usbManager;

/// Delegate for handling connection events
@property (nonatomic, weak, nullable) id<CSConnectionDelegate> delegate;

/// Set/get the host to connect to. Will be used next time `connect` is called
@property (nonatomic, nullable, copy) NSString *host;

/// Set/get the host port to connect to. Will be used next time `connect` is called
@property (nonatomic, nullable, copy) NSString *port;

/// Set/get the host socket file. Will be used next time `connect` is called and takes precedence over host/port
@property (nonatomic, nullable, copy) NSURL *unixSocketURL;

/// If true, all channels will be connected over TLS. Otherwise, no channels will be connected over TLS.
@property (nonatomic, readonly) BOOL isTLSOnly;

/// Set/get the TLS public key (SubjectPublicKey format) to check the server against. Will be used next time `connect` is called only on TLS channels.
@property (nonatomic, nullable) NSData *tlsServerPublicKey;

/// When enabled, gstreamer is used to provide audio input/output. Defaults to disabled
@property (nonatomic, assign) BOOL audioEnabled;

- (instancetype)init NS_UNAVAILABLE;

/// Create a new TCP connection
/// @param host Hostname string, can be an IPv4 address, IPv4 address, or domain name to resolve with DNS
/// @param port Port running SPICE server
- (instancetype)initWithHost:(NSString *)host port:(NSString *)port NS_DESIGNATED_INITIALIZER;

/// Create a new TCP connection with TLS support (on all channels)
/// @param host Hostname string, can be an IPv4 address, IPv4 address, or domain name to resolve with DNS
/// @param tlsPort Port running SPICE server (with TLS)
/// @param serverPublicKey Public key of the server to check against
- (instancetype)initWithHost:(NSString *)host tlsPort:(NSString *)tlsPort serverPublicKey:(NSData *)serverPublicKey NS_DESIGNATED_INITIALIZER;

/// Create a new Unix socket connection
/// @param socketFile Socket file
- (instancetype)initWithUnixSocketFile:(NSURL *)socketFile NS_DESIGNATED_INITIALIZER;

/// Connects to SPICE server
///
/// Note this returns when a connection is created. Use the `delegate` to detect when the connection is established.
/// @returns true if a connection was created and false if creation failed
- (BOOL)connect;

/// Request disconnect from SPICE server
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
