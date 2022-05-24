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

#import "CSChannel+Protected.h"
#import <glib-object.h>

@implementation CSChannel

- (void)setSpiceMain:(SpiceMainChannel *)spiceMain {
    if (_spiceMain) {
        g_object_unref(_spiceMain);
    }
    _spiceMain = spiceMain ? g_object_ref(spiceMain) : NULL;
}

@end
