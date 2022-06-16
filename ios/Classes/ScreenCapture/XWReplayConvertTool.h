//
//  XWReplayConvertTool.h
//  Broadcast
//
//  Created by QiangJindong on 2022/6/13.
//

#import <Foundation/Foundation.h>
#import <ReplayKit/ReplayKit.h>

NS_ASSUME_NONNULL_BEGIN

struct PixelBufferHead {
    uint16_t width;
    uint16_t height;
    uint16_t yPerRow;
    uint16_t uvPerRow;
    uint32_t size;
    int64_t timeStamp;
};

typedef struct PixelBufferHead PixelBufferHead;

@interface XWReplayConvertTool : NSObject

+ (NSData *)convertSampleBufferToData:(CMSampleBufferRef)sampleBuffer head:(PixelBufferHead *)head;

+ (NSData *)convertVideoSampleBufferToYuvData:(CMSampleBufferRef)sampleBuffer head:(PixelBufferHead *)head;

+ (CVPixelBufferRef)createCVPixelBufferRefFromBuffer:(unsigned char *)buffer head:(PixelBufferHead)head;

+ (CVPixelBufferRef)createCVPixelBufferRefFromNV12buffer:(unsigned char *)buffer head:(PixelBufferHead)head;

@end

NS_ASSUME_NONNULL_END
