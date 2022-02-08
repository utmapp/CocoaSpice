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
#import "CSRenderSource.h"
@import CoreGraphics;

@class CSScreenshot;

typedef struct _SpiceSession SpiceSession;

NS_ASSUME_NONNULL_BEGIN

@interface CSDisplayMetal : NSObject <CSRenderSource>

@property (nonatomic, assign) BOOL ready;
@property (nonatomic, readonly, nullable) SpiceSession *session;
@property (nonatomic, readonly, assign) NSInteger channelID;
@property (nonatomic, readonly, assign) NSInteger monitorID;
@property (nonatomic, assign) CGSize displaySize;
@property (nonatomic, readonly) CSScreenshot *screenshot;
@property (nonatomic, assign) BOOL inhibitCursor;
@property (nonatomic) CGSize cursorSize;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSession:(nonnull SpiceSession *)session channelID:(NSInteger)channelID monitorID:(NSInteger)monitorID NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithSession:(nonnull SpiceSession *)session channelID:(NSInteger)channelID;
- (void)updateVisibleAreaWithRect:(CGRect)rect;
- (void)requestResolution:(CGRect)bounds;
- (void)forceCursorPosition:(CGPoint)pos;

@end

NS_ASSUME_NONNULL_END
