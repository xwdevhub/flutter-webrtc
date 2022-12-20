//
//  XWRecvTansport.h
//  flutter_webrtc
//
//  Created by QiangJindong on 2022/6/13.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol XWRecvTansportDelegate;

@interface XWRecvTansport : NSObject

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port;
@property (nonatomic, weak) id<XWRecvTansportDelegate> delegate;
- (void)connect;
- (void)reset;

@end


@protocol XWRecvTansportDelegate <NSObject>

- (void)transport:(XWRecvTansport *)transport didReceivedBuffer:(CVPixelBufferRef)pixelBuffer info:(NSDictionary *)info;

@end

NS_ASSUME_NONNULL_END
