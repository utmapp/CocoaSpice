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

#import "CSDisplay+Renderer.h"
#import "CSDisplay+Protected.h"
#import "CSDisplay+Renderer_Protected.h"
#import "CSRenderer.h"
#import <stdatomic.h>

@interface CSDisplay ()

@property (atomic) NSArray<id<CSRenderer>> *renderers;

@end

@implementation CSDisplay (Renderer)

- (void)addRenderer:(id<CSRenderer>)renderer {
    NSArray<id<CSRenderer>> *renderers = self.renderers;
    if (![renderers containsObject:renderer]) {
        self.renderers = [renderers arrayByAddingObject:renderer];
    }
    if (!self.device) {
        self.device = renderer.device;
    } else {
        NSAssert(self.device == renderer.device, @"Cannot use two renderers from different Metal devices!");
    }
}

- (void)removeRenderer:(id<CSRenderer>)renderer {
    NSMutableArray<id<CSRenderer>> *renderers = [self.renderers mutableCopy];
    [renderers removeObject:renderer];
    self.renderers = renderers;
}

- (void)copyBuffer:(id<MTLBuffer>)sourceBuffer
            region:(MTLRegion)region
      sourceOffset:(NSUInteger)sourceOffset
 sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
        completion:(completionCallback_t)completion {
    /* lockless operation, need to get a copy of renderers */
    NSArray<id<CSRenderer>> *renderers = self.renderers;
    id<CSRenderSource> blitSource = nil;
    __block atomic_int numRemaining = renderers.count;
    if (renderers.count > 0) {
        blitSource =
            [renderers[0] renderSouce:self
                           copyBuffer:sourceBuffer
                               region:region
                         sourceOffset:sourceOffset
                    sourceBytesPerRow:sourceBytesPerRow
                           completion:^{
                if (atomic_fetch_sub(&numRemaining, 1) == 1) {
                    completion();
                }
            }];
    }
    if (blitSource && renderers.count > 1) {
        // invalidate all others
        for (NSInteger i = 1; i < renderers.count; i++) {
            [renderers[i] invalidateRenderSource:blitSource withCompletion:^{
                if (atomic_fetch_sub(&numRemaining, 1) == 1) {
                    completion();
                }
            }];
        }
    }
    if (!blitSource) {
        completion();
    }
}

- (void)invalidateWithCompletion:(completionCallback_t)completion {
    /* lockless operation, need to get a copy of renderers */
    NSArray<id<CSRenderer>> *renderers = self.renderers;
    __block atomic_int numRemaining = renderers.count;
    for (NSInteger i = 0; i < renderers.count; i++) {
        [renderers[i] invalidateRenderSource:self withCompletion:^{
            if (atomic_fetch_sub(&numRemaining, 1) == 1) {
                completion();
            }
        }];
    }
}

- (void)invalidate {
    NSArray<id<CSRenderer>> *renderers = self.renderers;
    for (NSInteger i = 0; i < renderers.count; i++) {
        [renderers[i] invalidateRenderSource:self withCompletion:nil];
    }
}

@end
