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
        completion:(drawCompletionCallback_t)completion {
    dispatch_async(self.displayQueue, ^{
        if (self.renderers.count == 1) {
            [self.renderers[0] renderSouce:self
                                copyBuffer:sourceBuffer
                                    region:region
                              sourceOffset:sourceOffset
                         sourceBytesPerRow:sourceBytesPerRow
                                completion:completion];
        } else if (self.renderers.count > 1) {
            // wait for all to finish
            dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INTERACTIVE, 0);
            dispatch_queue_t allRender = dispatch_queue_create("Display Copy Buffer Dispatch", attr);
            __block BOOL allSuccess = YES;
            for (NSInteger i = 0; i < self.renderers.count; i++) {
                dispatch_async(allRender, ^{
                    dispatch_semaphore_t waitUntilDrawn = dispatch_semaphore_create(0);
                    if (i == 0) {
                        // only need to copy the buffer once
                        [self.renderers[i] renderSouce:self
                                            copyBuffer:sourceBuffer
                                                region:region
                                          sourceOffset:sourceOffset
                                     sourceBytesPerRow:sourceBytesPerRow
                                            completion:^(BOOL success) {
                            allSuccess = allSuccess && success;
                            dispatch_semaphore_signal(waitUntilDrawn);
                        }];
                    } else {
                        // the rest should just get a copy of the buffer
                        [self.renderers[i] renderSource:self drawWithCompletion:^(BOOL success) {
                            allSuccess = allSuccess && success;
                            dispatch_semaphore_signal(waitUntilDrawn);
                        }];
                    }
                    dispatch_semaphore_wait(waitUntilDrawn, DISPATCH_TIME_FOREVER);
                });
            }
            dispatch_barrier_async(allRender, ^{
                completion(allSuccess);
            });
        }
    });
}

- (void)drawWithCompletion:(drawCompletionCallback_t)completion {
    dispatch_async(self.displayQueue, ^{
        if (self.renderers.count == 1) {
            [self.renderers[0] renderSource:self drawWithCompletion:completion];
        } else if (self.renderers.count > 1) {
            // wait for all to finish
            dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INTERACTIVE, 0);
            dispatch_queue_t allRender = dispatch_queue_create("Display Draw Dispatch", attr);
            __block BOOL allSuccess = YES;
            for (NSInteger i = 0; i < self.renderers.count; i++) {
                dispatch_async(allRender, ^{
                    dispatch_semaphore_t waitUntilDrawn = dispatch_semaphore_create(0);
                    [self.renderers[i] renderSource:self drawWithCompletion:^(BOOL success) {
                        allSuccess = allSuccess && success;
                        dispatch_semaphore_signal(waitUntilDrawn);
                    }];
                    dispatch_semaphore_wait(waitUntilDrawn, DISPATCH_TIME_FOREVER);
                });
            }
            dispatch_barrier_async(allRender, ^{
                completion(allSuccess);
            });
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
