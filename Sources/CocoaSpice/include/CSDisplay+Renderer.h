//
// Copyright © 2023 osy. All rights reserved.
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

#import "CSDisplay.h"
#import "CSRenderer.h"

NS_ASSUME_NONNULL_BEGIN

/// Links a CSDisplay to a CSRenderer
@interface CSDisplay (Renderer)

/// Add a renderer that will present this display
///
/// Important: once the first renderer is added, all subsequent renderers MUST be on the same MTLDevice!
/// @param renderer Renderer to add.
- (void)addRenderer:(id<CSRenderer>)renderer NS_SWIFT_NAME(addRenderer(_:));

/// Remove a renderer and stop presenting to it
/// @param renderer Renderer to remove.
- (void)removeRenderer:(id<CSRenderer>)renderer NS_SWIFT_NAME(removeRenderer(_:));

@end

NS_ASSUME_NONNULL_END
