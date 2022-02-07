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

typedef NS_ENUM(NSInteger, CSPasteboardType) {
    kCSPasteboardTypeURL = 0,
    kCSPasteboardTypeBmp = 1,
    kCSPasteboardTypeFileURL = 2,
    kCSPasteboardTypeFont = 3,
    kCSPasteboardTypeHtml = 4,
    kCSPasteboardTypeJpg = 5,
    kCSPasteboardTypePdf = 6,
    kCSPasteboardTypePng = 7,
    kCSPasteboardTypeRtf = 8,
    kCSPasteboardTypeRtfd = 9,
    kCSPasteboardTypeSound = 10,
    kCSPasteboardTypeString = 11,
    kCSPasteboardTypeTabularText = 12,
    kCSPasteboardTypeTiff = 13,
};

extern const NSNotificationName _Nonnull CSPasteboardChangedNotification;
extern const NSNotificationName _Nonnull CSPasteboardRemovedNotification;

NS_ASSUME_NONNULL_BEGIN

@protocol CSPasteboardDelegate <NSObject>

- (BOOL)canReadItemForType:(CSPasteboardType)type;
- (NSData *)dataForType:(CSPasteboardType)type;
- (void)setData:(NSData *)data forType:(CSPasteboardType)type;
- (NSString *)string;
- (void)setString:(NSString *)string;
- (void)clearContents;

@end

NS_ASSUME_NONNULL_END
