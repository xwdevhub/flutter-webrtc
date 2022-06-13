//
//  XWReplayConvertTool.h
//  Broadcast
//
//  Created by QiangJindong on 2022/6/13.
//

#import <Foundation/Foundation.h>
#import <ReplayKit/ReplayKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XWReplayConvertTool : NSObject

+ (NSData *)convertSampleBufferToData:(CMSampleBufferRef)sampleBuffer;

+ (NSData *)convertVideoSampleBufferToYuvData:(CMSampleBufferRef)sampleBuffer;

+ (CVPixelBufferRef)createCVPixelBufferRefFromBuffer:(unsigned char *)buffer size:(int)size width:(int)w height:(int)h;

+ (CVPixelBufferRef)createCVPixelBufferRefFromNV12buffer:(unsigned char *)buffer width:(int)w height:(int)h;

@end

NS_ASSUME_NONNULL_END
