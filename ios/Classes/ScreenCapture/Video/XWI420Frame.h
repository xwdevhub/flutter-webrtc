//
//
//  Created by Netease on 15/4/17.
//  Copyright (c) 2017年 Netease. All rights reserved.
//

#import <CoreMedia/CMSampleBuffer.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, XWI420FramePlane) {
    XWI420FramePlaneY = 0,
    XWI420FramePlaneU = 1,
    XWI420FramePlaneV = 2,
};

@interface XWI420Frame : NSObject

@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) int i420DataLength;
@property (nonatomic, assign) UInt64 timetag;
@property (nonatomic, readonly) UInt8 *data;

+ (instancetype)initWithData:(NSData *)data;

- (NSData *)bytes;

- (id)initWithWidth:(int)w height:(int)h;

- (UInt8 *)dataOfPlane:(XWI420FramePlane)plane;

- (NSUInteger)strideOfPlane:(XWI420FramePlane)plane;

- (CMSampleBufferRef)convertToSampleBuffer;

- (void)getBytesQueue:(void (^)(NSData *data, NSInteger index))complete;

@end
