//
// Copyright © 2021 osy. All rights reserved.
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

#import "CSUSBDevice.h"
#import <glib.h>
#import <spice-client.h>
#import <libusb.h>

@interface CSUSBDevice ()

@property (nonatomic, readwrite, nonnull) SpiceUsbDevice *device;
@property (nonatomic, readwrite, nonnull) SpiceUsbDeviceManager *manager;
@property (nonatomic) BOOL hasReadDescriptors;

@end

@implementation CSUSBDevice

@synthesize usbManufacturerName = _usbManufacturerName;
@synthesize usbProductName = _usbProductName;
@synthesize usbSerial = _usbSerial;
@synthesize usbVendorId = _usbVendorId;
@synthesize usbProductId = _usbProductId;

+ (instancetype)usbDeviceWithDevice:(SpiceUsbDevice *)device manager:(SpiceUsbDeviceManager *)manager {
    return [[CSUSBDevice alloc] initWithDevice:device manager:manager];
}

- (instancetype)initWithDevice:(SpiceUsbDevice *)device manager:(SpiceUsbDeviceManager *)manager {
    if (self = [super init]) {
        self.device = g_boxed_copy(SPICE_TYPE_USB_DEVICE, device);
        self.manager = g_object_ref(manager);
    }
    return self;
}

- (void)dealloc {
    g_boxed_free(SPICE_TYPE_USB_DEVICE, self.device);
    // must unref manager after device because manager's finalize can call `libusb_exit`
    g_object_unref(self.manager);
}

- (void)readDescriptors {
    libusb_device *dev = (libusb_device *)spice_usb_device_get_libusb_device(self.device);
    struct libusb_device_descriptor ddesc;
    libusb_device_handle *handle;
    if (libusb_get_device_descriptor(dev, &ddesc) != 0) {
        return;
    }
    _usbVendorId = ddesc.idVendor;
    _usbProductId = ddesc.idProduct;
    self.hasReadDescriptors = YES;
    if (libusb_open(dev, &handle) == 0) {
        unsigned char name[64] = { 0 };
        libusb_get_string_descriptor_ascii(handle,
                                           ddesc.iProduct,
                                           name, sizeof(name));
        if (name[0] != '\0') {
            _usbProductName = [NSString stringWithCString:(char *)name encoding:NSASCIIStringEncoding];
        }
        name[0] = '\0';
        libusb_get_string_descriptor_ascii(handle,
                                           ddesc.iManufacturer,
                                           name, sizeof(name));
        if (name[0] != '\0') {
            _usbManufacturerName = [NSString stringWithCString:(char *)name encoding:NSASCIIStringEncoding];
        }
        name[0] = '\0';
        libusb_get_string_descriptor_ascii(handle,
                                           ddesc.iSerialNumber,
                                           name, sizeof(name));
        if (name[0] != '\0') {
            _usbSerial = [NSString stringWithCString:(char *)name encoding:NSASCIIStringEncoding];
        }
        libusb_close(handle);
    }
}

- (NSString *)usbManufacturerName {
    if (!self.hasReadDescriptors) {
        [self readDescriptors];
    }
    return _usbManufacturerName;
}

- (NSString *)usbProductName {
    if (!self.hasReadDescriptors) {
        [self readDescriptors];
    }
    return _usbProductName;
}

- (NSString *)usbSerial {
    if (!self.hasReadDescriptors) {
        [self readDescriptors];
    }
    return _usbSerial;
}

- (NSInteger)usbVendorId {
    if (!self.hasReadDescriptors) {
        [self readDescriptors];
    }
    return _usbVendorId;
}

- (NSInteger)usbProductId {
    if (!self.hasReadDescriptors) {
        [self readDescriptors];
    }
    return _usbProductId;
}

- (NSInteger)usbBusNumber {
    libusb_device *dev = (libusb_device *)spice_usb_device_get_libusb_device(self.device);
    return libusb_get_bus_number(dev);
}

- (NSInteger)usbPortNumber {
    libusb_device *dev = (libusb_device *)spice_usb_device_get_libusb_device(self.device);
    return libusb_get_port_number(dev);
}

- (NSString *)name {
    if (self.usbProductName) {
        return [NSString stringWithFormat:@"%@ (%ld:%ld)", self.usbProductName, self.usbBusNumber, self.usbPortNumber];
    } else {
        return nil;
    }
}

- (NSString *)description {
    gchar *description = spice_usb_device_get_description(self.device, NULL);
    if (!description) {
        return @"";
    }
    NSString *nsdescription = [NSString stringWithUTF8String:description];
    g_free(description);
    return nsdescription;
}

- (BOOL)isEqualToUSBDevice:(CSUSBDevice *)usbDevice {
    if (self.usbBusNumber == usbDevice.usbBusNumber &&
        self.usbPortNumber == usbDevice.usbPortNumber &&
        self.usbVendorId == usbDevice.usbVendorId &&
        self.usbProductId == usbDevice.usbProductId &&
        [self.usbManufacturerName isEqualToString:usbDevice.usbManufacturerName] &&
        [self.usbProductName isEqualToString:usbDevice.usbProductName] &&
        [self.usbSerial isEqualToString:usbDevice.usbSerial]) {
        return YES;
    }
    return NO;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[CSUSBDevice class]]) {
        return NO;
    }
    
    return [self isEqualToUSBDevice:object];
}

- (NSUInteger)hash {
    return self.description.hash;
}

@end
