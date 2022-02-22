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

#import "TargetConditionals.h"
#if TARGET_OS_IPHONE
#include <UIKit/UIKit.h>
#else
#include <AppKit/AppKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Platform agnostic way to represent a screenshot PNG image
@interface CSScreenshot : NSObject

#if TARGET_OS_IPHONE

/// UIImage representation of the screenshot
@property (nonatomic, readonly) UIImage *image;

#else

/// NSImage representation of the screenshot
@property (nonatomic, readonly) NSImage *image;

#endif

- (instancetype)init NS_UNAVAILABLE;

#if TARGET_OS_IPHONE

/// Create a screenshot from a UIImage
/// @param image Screenshot image
- (instancetype)initWithImage:(UIImage *)image NS_DESIGNATED_INITIALIZER;

#else

/// Create a screenshot from a NSImage
/// @param image Screenshot image
- (instancetype)initWithImage:(NSImage *)image NS_DESIGNATED_INITIALIZER;

#endif

/// Create a screenshot from a PNG file
/// @param url File URL of PNG
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url;

/// Writes a screenshot image to a PNG file
/// @param url File URL of PNG destination
/// @param atomically If true, the write should be atomic
- (void)writeToURL:(NSURL *)url atomically:(BOOL)atomically;

@end

NS_ASSUME_NONNULL_END
