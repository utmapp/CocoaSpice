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

@interface CSDisplay ()

@property (nonatomic, readonly) dispatch_queue_t displayQueue;
@property (nonatomic) NSMutableArray<id<CSRenderer>> *renderers;

@end

@implementation CSDisplay (Renderer)

- (void)addRenderer:(id<CSRenderer>)renderer {
    dispatch_async(self.displayQueue, ^{
        if (![self.renderers containsObject:renderer]) {
            [self.renderers addObject:renderer];
        }
    });
    if (!self.device) {
        self.device = renderer.device;
    } else {
        NSAssert(self.device == renderer.device, @"Cannot use two renderers from different Metal devices!");
    }
}

- (void)removeRenderer:(id<CSRenderer>)renderer {
    dispatch_async(self.displayQueue, ^{
        [self.renderers removeObject:renderer];
    });
}

- (void)copyBuffer:(id<MTLBuffer>)sourceBuffer
            region:(MTLRegion)region
      sourceOffset:(NSUInteger)sourceOffset
 sourceBytesPerRow:(NSUInteger)sourceBytesPerRow
        completion:(copyCompletionCallback_t)completion {
    dispatch_async(self.displayQueue, ^{
        id<CSRenderSource> blitSource = self;
        if (self.renderers.count > 0) {
            blitSource =
                [self.renderers[0] renderSouce:self
                                    copyBuffer:sourceBuffer
                                        region:region
                                  sourceOffset:sourceOffset
                             sourceBytesPerRow:sourceBytesPerRow
                                    completion:completion];
        }
        if (self.renderers.count > 1) {
            // invalidate all others
            for (NSInteger i = 1; i < self.renderers.count; i++) {
                [self.renderers[i] invalidateRenderSource:blitSource];
            }
        }
    });
}

- (void)invalidate {
    dispatch_async(self.displayQueue, ^{
        for (NSInteger i = 0; i < self.renderers.count; i++) {
            [self.renderers[i] invalidateRenderSource:self];
        }
    });
}

@end
