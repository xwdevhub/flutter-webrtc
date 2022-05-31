//
//
//  Created by fenric on 16/3/25.
//  Copyright © 2016年 Netease. All rights reserved.
//

#import "XWI420Frame.h"
#import <CoreMedia/CMSampleBuffer.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, XWVideoPackOrientation) {
    XWVideoPackOrientationPortrait           = 0, //No rotation
    XWVideoPackOrientationLandscapeLeft      = 1, //Rotate 90 degrees clockwise
    XWVideoPackOrientationPortraitUpsideDown = 2, //Rotate 180 degrees
    XWVideoPackOrientationLandscapeRight     = 3, //Rotate 270 degrees clockwise
};

@interface XWYUVConverter : NSObject

+ (XWI420Frame *)pixelBufferToI420:(CVImageBufferRef)pixelBuffer
                            withCrop:(float)cropRatio
                          targetSize:(CGSize)size
                      andOrientation:(XWVideoPackOrientation)orientation;

+ (XWI420Frame *)pixelBufferToI420:(CVImageBufferRef)pixelBuffer scale:(CGFloat)scale;

+ (CVPixelBufferRef)i420FrameToPixelBuffer:(XWI420Frame *)i420Frame;

+ (CMSampleBufferRef)pixelBufferToSampleBuffer:(CVPixelBufferRef)pixelBuffer;

@end
