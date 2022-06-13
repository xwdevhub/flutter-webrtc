//
//  XWReplayConvertTool.m
//  Broadcast
//
//  Created by QiangJindong on 2022/6/13.
//

#import "XWReplayConvertTool.h"

@implementation XWReplayConvertTool

+ (NSData *)convertSampleBufferToData:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t row = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    void *src_buff = CVPixelBufferGetBaseAddress(pixelBuffer);
    NSData *data = [NSData dataWithBytes:src_buff length:row * height];
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return data;
}

+ (NSData *)convertVideoSampleBufferToYuvData:(CMSampleBufferRef)sampleBuffer {
    // 获取yuv数据
    // 通过CMSampleBufferGetImageBuffer方法，获得CVImageBufferRef。
    // 这里面就包含了yuv420(NV12)数据的指针
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    //表示开始操作数据
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    //图像宽度（像素）
    size_t pixelWidth = CVPixelBufferGetWidth(pixelBuffer);
    //图像高度（像素）
    size_t pixelHeight = CVPixelBufferGetHeight(pixelBuffer);
    //yuv中的y所占字节数
    size_t y_size = pixelWidth * pixelHeight;
    //yuv中的uv所占的字节数
    size_t uv_size = y_size / 2;

    uint8_t *yuv_frame = (uint8_t *)malloc(uv_size + y_size);

    //获取CVImageBufferRef中的y数据
    uint8_t *y_frame = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    memcpy(yuv_frame, y_frame, y_size);

    //获取CMVImageBufferRef中的uv数据
    uint8_t *uv_frame = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    memcpy(yuv_frame + y_size, uv_frame, uv_size);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    //返回数据
    NSData *data = [NSData dataWithBytesNoCopy:yuv_frame length:y_size + uv_size];
    CVPixelBufferRelease(pixelBuffer);

    return data;
}

+ (CVPixelBufferRef)createCVPixelBufferRefFromBuffer:(unsigned char *)buffer size:(int)size width:(int)w height:(int)h {
    NSDictionary *pixelAttributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}};

    CVPixelBufferRef pixelBuffer = NULL;

    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                          w,
                                          h,
                                          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                          (__bridge CFDictionaryRef)(pixelAttributes),
                                          &pixelBuffer); //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char *dst = CVPixelBufferGetBaseAddress(pixelBuffer);

    memcpy(dst, buffer, size);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
    }
    return pixelBuffer;
}

+ (CVPixelBufferRef)createCVPixelBufferRefFromNV12buffer:(unsigned char *)buffer width:(int)w height:(int)h {
    NSDictionary *pixelAttributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}};

    CVPixelBufferRef pixelBuffer = NULL;

    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                          w,
                                          h,
                                          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                          (__bridge CFDictionaryRef)(pixelAttributes),
                                          &pixelBuffer); //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);

    // Here y_ch0 is Y-Plane of YUV(NV12) data.
    unsigned char *y_ch0 = buffer;
    memcpy(yDestPlane, y_ch0, w * h);
    unsigned char *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);

    // Here y_ch1 is UV-Plane of YUV(NV12) data.
    unsigned char *y_ch1 = buffer + w * h;
    memcpy(uvDestPlane, y_ch1, w * h / 2);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
        CVPixelBufferRelease(pixelBuffer);
    }
    return pixelBuffer;
}

@end
