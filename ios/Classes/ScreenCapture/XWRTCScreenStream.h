//
//  XWRTCScreenStream.h
//  broadcast
//
//  Created by lnd on 2022/5/17.
//

#import "FlutterWebRTCPlugin.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FlutterWebRTCPlugin (RTCMediaStream)

#if TARGET_OS_IPHONE

- (void)addScreenShareBroadcastNotification;

- (void)getDisplayScreenMedia:(NSDictionary *)constraints
                       result:(FlutterResult)result;
#endif

@end

NS_ASSUME_NONNULL_END
