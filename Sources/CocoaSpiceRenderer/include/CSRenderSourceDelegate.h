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

@protocol CSRenderSource;

NS_ASSUME_NONNULL_BEGIN

typedef void (^drawCompletionCallback_t)(BOOL success);

@protocol CSRenderSourceDelegate <NSObject>

/// Called by the render source to indicate that the source should be re-drawn
/// - Parameter renderSource: Render source that is invalidatedvoid (^)(BOOL)
/// - Parameter completion: Optional completion handler to run after rendering completes
- (void)renderSource:(id<CSRenderSource>)renderSource shouldDrawWithCompletion:(nullable drawCompletionCallback_t)completion;

/// Called by the render source to request manual draw mode
///
/// In manual draw mode, rendering will only be done when invalidated. Otherwise, it will be done on a timer.
/// - Parameters:
///   - renderSource: Render source that requested the change
///   - manualDrawing: Should manual drawing be done?
- (void)renderSource:(id<CSRenderSource>)renderSource didChangeModeToManualDrawing:(BOOL)manualDrawing;

@end

NS_ASSUME_NONNULL_END
