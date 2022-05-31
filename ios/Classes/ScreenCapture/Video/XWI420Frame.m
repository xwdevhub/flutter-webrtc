//
//
//  Created by fenric on 15/4/17.
//  Copyright (c) 2015年 Netease. All rights reserved.
//

#import "XWI420Frame.h"
#import "XWYUVConverter.h"

@interface XWI420Frame () {
    CFMutableDataRef _cfData;
    UInt8 *_planeData[3];
    NSUInteger _stride[3];
}

@end

@implementation XWI420Frame

+ (instancetype)initWithData:(NSData *)data {
    int width = 0;
    int height = 0;
    int i420DataLength = 0;
    UInt64 timetag = 0;

    int structSize = sizeof(width) + sizeof(height) + sizeof(i420DataLength) + sizeof(timetag);
    if (structSize > data.length) {
        return nil;
    }

    const void *buffer = [data bytes];
    int offset = 0;

    memcpy(&width, buffer + offset, sizeof(width));
    offset += sizeof(width);

    memcpy(&height, buffer + offset, sizeof(height));
    offset += sizeof(height);

    memcpy(&i420DataLength, buffer + offset, sizeof(i420DataLength));
    offset += sizeof(i420DataLength);

    memcpy(&timetag, buffer + offset, sizeof(timetag));
    offset += sizeof(timetag);

    if (i420DataLength > data.length - structSize) {
        return nil;
    }
    XWI420Frame *frame = [[[self class] alloc] initWithWidth:width height:height];

    memcpy([frame dataOfPlane:XWI420FramePlaneY], buffer + offset, [frame strideOfPlane:XWI420FramePlaneY] * height);
    offset += [frame strideOfPlane:XWI420FramePlaneY] * height;

    memcpy([frame dataOfPlane:XWI420FramePlaneU], buffer + offset, [frame strideOfPlane:XWI420FramePlaneU] * height / 2);
    offset += [frame strideOfPlane:XWI420FramePlaneU] * height / 2;

    memcpy([frame dataOfPlane:XWI420FramePlaneV], buffer + offset, [frame strideOfPlane:XWI420FramePlaneV] * height / 2);
    offset += [frame strideOfPlane:XWI420FramePlaneV] * height / 2;

    return frame;
}

- (NSData *)bytes {
    int structSize = sizeof(self.width) + sizeof(self.height) + sizeof(self.i420DataLength) + sizeof(self.timetag);

    void *buffer = malloc(structSize + self.i420DataLength);

    memset(buffer, 0, structSize + self.i420DataLength);
    int offset = 0;

    memcpy(buffer + offset, &_width, sizeof(_width));
    offset += sizeof(_width);

    memcpy(buffer + offset, &_height, sizeof(_height));
    offset += sizeof(_height);

    memcpy(buffer + offset, &_i420DataLength, sizeof(_i420DataLength));
    offset += sizeof(_i420DataLength);

    memcpy(buffer + offset, &_timetag, sizeof(_timetag));
    offset += sizeof(_timetag);

    memcpy(buffer + offset, [self dataOfPlane:XWI420FramePlaneY], [self strideOfPlane:XWI420FramePlaneY] * self.height);
    offset += [self strideOfPlane:XWI420FramePlaneY] * self.height;

    memcpy(buffer + offset, [self dataOfPlane:XWI420FramePlaneU], [self strideOfPlane:XWI420FramePlaneU] * self.height / 2);
    offset += [self strideOfPlane:XWI420FramePlaneU] * self.height / 2;

    memcpy(buffer + offset, [self dataOfPlane:XWI420FramePlaneV], [self strideOfPlane:XWI420FramePlaneV] * self.height / 2);
    offset += [self strideOfPlane:XWI420FramePlaneV] * self.height / 2;

    NSData *data = [NSData dataWithBytes:buffer length:offset];
    free(buffer);
    return data;
}

- (void)getBytesQueue:(void (^)(NSData *data, NSInteger index))complete {
    int offset = 0;
    {
        int structSize = sizeof(self.width) + sizeof(self.height) + sizeof(self.i420DataLength) + sizeof(self.timetag);

        void *buffer = malloc(structSize + self.i420DataLength);

        memset(buffer, 0, structSize + self.i420DataLength);

        memcpy(buffer + offset, &_width, sizeof(_width));
        offset += sizeof(_width);

        memcpy(buffer + offset, &_height, sizeof(_height));
        offset += sizeof(_height);

        memcpy(buffer + offset, &_i420DataLength, sizeof(_i420DataLength));
        offset += sizeof(_i420DataLength);

        memcpy(buffer + offset, &_timetag, sizeof(_timetag));
        offset += sizeof(_timetag);
        NSData *data = [NSData dataWithBytes:buffer length:offset];
        if (complete) {
            complete(data, 0);
        }
        free(buffer);
        data = NULL;
    }

    {
        void *buffer = malloc([self strideOfPlane:XWI420FramePlaneY] * self.height);
        offset = 0;
        memset(buffer, 0, [self strideOfPlane:XWI420FramePlaneY] * self.height);
        memcpy(buffer + offset, [self dataOfPlane:XWI420FramePlaneY], [self strideOfPlane:XWI420FramePlaneY] * self.height);
        offset += [self strideOfPlane:XWI420FramePlaneY] * self.height;
        NSData *data = [NSData dataWithBytes:buffer length:offset];
        if (complete) {
            complete(data, 0);
        }
        free(buffer);
        data = NULL;
    }

    {
        void *buffer = malloc([self strideOfPlane:XWI420FramePlaneU] * self.height / 2);
        offset = 0;
        memset(buffer, 0, [self strideOfPlane:XWI420FramePlaneU] * self.height / 2);
        memcpy(buffer + offset, [self dataOfPlane:XWI420FramePlaneU], [self strideOfPlane:XWI420FramePlaneU] * self.height / 2);
        offset += [self strideOfPlane:XWI420FramePlaneU] * self.height / 2;
        NSData *data = [NSData dataWithBytes:buffer length:offset];
        if (complete) {
            complete(data, 1);
        }
        free(buffer);
        data = NULL;
    }

    {
        void *buffer = malloc([self strideOfPlane:XWI420FramePlaneV] * self.height / 2);
        offset = 0;
        memset(buffer, 0, [self strideOfPlane:XWI420FramePlaneV] * self.height / 2);
        memcpy(buffer + offset, [self dataOfPlane:XWI420FramePlaneV], [self strideOfPlane:XWI420FramePlaneV] * self.height / 2);
        offset += [self strideOfPlane:XWI420FramePlaneV] * self.height / 2;
        NSData *data = [NSData dataWithBytes:buffer length:offset];
        if (complete) {
            complete(data, 2);
        }
        free(buffer);
        data = NULL;
    }
}

- (id)initWithWidth:(int)w
             height:(int)h {
    if (self = [super init]) {
        _width = w;
        _height = h;
        _i420DataLength = _width * _height * 3 >> 1;
        _cfData = CFDataCreateMutable(kCFAllocatorDefault, _i420DataLength);
        _data = CFDataGetMutableBytePtr(_cfData);
        _planeData[XWI420FramePlaneY] = _data;
        _planeData[XWI420FramePlaneU] = _planeData[XWI420FramePlaneY] + _width * _height;
        _planeData[XWI420FramePlaneV] = _planeData[XWI420FramePlaneU] + _width * _height / 4;
        _stride[XWI420FramePlaneY] = _width;
        _stride[XWI420FramePlaneU] = _width >> 1;
        _stride[XWI420FramePlaneV] = _width >> 1;
    }

    return self;
}

- (UInt8 *)dataOfPlane:(XWI420FramePlane)plane {
    return _planeData[plane];
}

- (NSUInteger)strideOfPlane:(XWI420FramePlane)plane {
    return _stride[plane];
}

- (void)freeData {
    CFRelease(_cfData);

    _data = NULL;
    _width = _height = _i420DataLength = 0;
}

- (void)dealloc {
    [self freeData];
}

- (CMSampleBufferRef)convertToSampleBuffer {
    CVPixelBufferRef pixelBuffer = [XWYUVConverter i420FrameToPixelBuffer:self];
    if (!pixelBuffer) {
        return nil;
    }
    CMSampleBufferRef sampleBuffer = [XWYUVConverter pixelBufferToSampleBuffer:pixelBuffer];
    return sampleBuffer;
}

@end
