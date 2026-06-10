#import "StatsAdapterIOHID.h"

NSDictionary<NSString *, NSNumber *> * _Nullable StatsAdapterCopyAppleSiliconTemperatureSensors(int32_t page, int32_t usage, int32_t type) {
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage": @(usage),
    };

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (system == NULL) {
        return nil;
    }

    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == NULL) {
        CFRelease(system);
        return nil;
    }

    NSMutableDictionary<NSString *, NSNumber *> *values = [NSMutableDictionary dictionary];
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex index = 0; index < count; index += 1) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        if (service == NULL) {
            continue;
        }

        NSString *name = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, type, 0, 0);
        if (name == nil || event == NULL) {
            if (event != NULL) {
                CFRelease(event);
            }
            continue;
        }

        double value = IOHIDEventGetFloatValue(event, StatsAdapterIOHIDEventFieldBase(type));
        values[name] = @(value);
        CFRelease(event);
    }

    CFRelease(services);
    CFRelease(system);

    return values;
}
