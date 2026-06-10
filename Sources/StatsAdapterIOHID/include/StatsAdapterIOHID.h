#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif

#define StatsAdapterIOHIDEventFieldBase(type) (type << 16)
#define StatsAdapterIOHIDEventTypeTemperature 15
#define StatsAdapterIOHIDEventTypePower 25

IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef _Nonnull client, CFDictionaryRef _Nonnull match);
IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef _Nonnull service, int64_t type, int32_t field, int64_t options);
CFTypeRef _Nullable IOHIDServiceClientCopyProperty(IOHIDServiceClientRef _Nonnull service, CFStringRef _Nonnull property);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef _Nonnull event, int32_t field);

FOUNDATION_EXPORT NSDictionary<NSString *, NSNumber *> * _Nullable StatsAdapterCopyAppleSiliconTemperatureSensors(int32_t page, int32_t usage, int32_t type);

struct nvme_smart_log {
    UInt8 critical_warning;
    UInt8 temperature[2];
    UInt8 avail_spare;
    UInt8 spare_thresh;
    UInt8 percent_used;
    UInt8 reserved_6[26];
    UInt8 data_units_read[16];
    UInt8 data_units_written[16];
    UInt8 host_reads[16];
    UInt8 host_writes[16];
    UInt8 ctrl_busy_time[16];
    UInt32 power_cycles[4];
    UInt32 power_on_hours[4];
    UInt32 unsafe_shutdowns[4];
    UInt32 media_errors[4];
    UInt16 temp_sensor[8];
    UInt32 thermal_temp1_transition_count;
    UInt32 thermal_temp2_transition_count;
    UInt32 thermal_temp1_total_time;
    UInt32 thermal_temp2_total_time;
    UInt8 reserved_232[280];
};

typedef struct IONVMeSMARTInterface {
    IUNKNOWN_C_GUTS;

    UInt16 version;
    UInt16 revision;

    IOReturn (* _Nonnull SMARTReadData)(void * _Nonnull interface, struct nvme_smart_log * _Nonnull smartData);
} IONVMeSMARTInterface;
