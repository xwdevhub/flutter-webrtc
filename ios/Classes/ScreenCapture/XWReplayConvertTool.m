//
//  XWReplayConvertTool.m
//  Broadcast
//
//  Created by QiangJindong on 2022/6/13.
//

#import "XWReplayConvertTool.h"

@implementation XWReplayConvertTool

+ (NSData *)convertSampleBufferToData:(CMSampleBufferRef)sampleBuffer head:(PixelBufferHead *)head {
    head->timeStamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * NSEC_PER_SEC;
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t row = CVPixelBufferGetBytesPerRow(pixelBuffer);

    uint16_t width = (uint16_t)CVPixelBufferGetWidth(pixelBuffer);
    head->width = width;

    uint16_t height = (uint16_t)CVPixelBufferGetHeight(pixelBuffer);
    head->height = height;

    size_t left, right, top, bottom;
    CVPixelBufferGetExtendedPixels(pixelBuffer, &left, &right, &top, &bottom);
    head->extendLeft = (int32_t)left;
    head->extendRight = (int32_t)right;
    head->extendTop = (int32_t)top;
    head->extendBottom = (int32_t)bottom;

    void *src_buff = CVPixelBufferGetBaseAddress(pixelBuffer);
    NSData *data = [NSData dataWithBytes:src_buff length:row * height];

    head->size = (uint32_t)data.length;
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return data;
}

+ (NSData *)convertVideoSampleBufferToYuvData:(CMSampleBufferRef)sampleBuffer head:(PixelBufferHead *)head {
    head->timeStamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * NSEC_PER_SEC;
    // 获取yuv数据
    // 通过CMSampleBufferGetImageBuffer方法，获得CVImageBufferRef。
    // 这里面就包含了yuv420(NV12)数据的指针
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

    //表示开始操作数据
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    size_t left, right, top, bottom;
    CVPixelBufferGetExtendedPixels(pixelBuffer, &left, &right, &top, &bottom);
    head->extendLeft = (int32_t)left;
    head->extendRight = (int32_t)right;
    head->extendTop = (int32_t)top;
    head->extendBottom = (int32_t)bottom;

    //图像宽度（像素）
    size_t pixelWidth = CVPixelBufferGetWidth(pixelBuffer);
    head->width = pixelWidth;

    //图像高度（像素）
    size_t pixelHeight = CVPixelBufferGetHeight(pixelBuffer);
    head->height = pixelHeight;

    //yuv中的y所占字节数
    size_t y_perRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    head->yPerRow = y_perRow;
    size_t y_size = y_perRow * pixelHeight;

    //yuv中的uv所占的字节数
    size_t uv_perRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    head->uvPerRow = uv_perRow;
    size_t uv_size = uv_perRow * pixelHeight / 2;

    uint8_t *yuv_frame = (uint8_t *)malloc(y_size + uv_size);

    //获取CVImageBufferRef中的y数据
    uint8_t *y_frame = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    memcpy(yuv_frame, y_frame, y_size);

    //获取CMVImageBufferRef中的uv数据
    uint8_t *uv_frame = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    memcpy(yuv_frame + y_size, uv_frame, uv_size);

    //返回数据
    NSData *data = [NSData dataWithBytesNoCopy:yuv_frame length:y_size + uv_size];
    head->size = (uint32_t)data.length;

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return data;
}

+ (CVPixelBufferRef)createCVPixelBufferRefFromBuffer:(unsigned char *)buffer head:(PixelBufferHead)head {
    NSDictionary *pixelAttributes = @{
        (NSString *)kCVPixelBufferExtendedPixelsLeftKey : @(head.extendLeft),
        (NSString *)kCVPixelBufferExtendedPixelsRightKey : @(head.extendRight),
        (NSString *)kCVPixelBufferExtendedPixelsTopKey : @(head.extendTop),
        (NSString *)kCVPixelBufferExtendedPixelsBottomKey : @(head.extendBottom),
    };

    CVPixelBufferRef pixelBuffer = NULL;

    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                          head.width,
                                          head.height,
                                          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                          (__bridge CFDictionaryRef)(pixelAttributes),
                                          &pixelBuffer); //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char *dst = CVPixelBufferGetBaseAddress(pixelBuffer);

    memcpy(dst, buffer, head.size);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
    }
    return pixelBuffer;
}

+ (CVPixelBufferRef)createCVPixelBufferRefFromNV12buffer:(unsigned char *)buffer head:(PixelBufferHead)head {
    NSDictionary *pixelAttributes = @{
        (NSString *)kCVPixelBufferExtendedPixelsLeftKey : @(head.extendLeft),
        (NSString *)kCVPixelBufferExtendedPixelsRightKey : @(head.extendRight),
        (NSString *)kCVPixelBufferExtendedPixelsTopKey : @(head.extendTop),
        (NSString *)kCVPixelBufferExtendedPixelsBottomKey : @(head.extendBottom),
    };

    CVPixelBufferRef pixelBuffer = NULL;

    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault,
                                          head.width,
                                          head.height,
                                          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                          (__bridge CFDictionaryRef)(pixelAttributes),
                                          &pixelBuffer); //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    unsigned char *yDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);

    // Here y_ch0 is Y-Plane of YUV(NV12) data.
    unsigned char *y_ch0 = buffer;
    memcpy(yDestPlane, y_ch0, head.yPerRow * head.height);
    unsigned char *uvDestPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);

    // Here y_ch1 is UV-Plane of YUV(NV12) data.
    unsigned char *y_ch1 = buffer + head.yPerRow * head.height;
    memcpy(uvDestPlane, y_ch1, head.uvPerRow * head.height / 2);

    CVBufferSetAttachment(pixelBuffer, kCVImageBufferChromaLocationBottomFieldKey, kCVImageBufferChromaLocation_Left, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferChromaLocationTopFieldKey, kCVImageBufferChromaLocation_Left, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    if (@available(iOS 11.0, *)) {
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
    }
    CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    if (result != kCVReturnSuccess) {
        NSLog(@"Unable to create cvpixelbuffer %d", result);
    }
    return pixelBuffer;
}

@end
