//
//  XWRTCScreenStream.m
//  broadcast
//
//  Created by lnd on 2022/5/17.
//

#import "XWRTCScreenStream.h"
#import<objc/runtime.h>

#if TARGET_OS_IPHONE
#import "FlutterRPScreenRecorder.h"
#endif

static NSString *TScreenShareBroadcastStartedNotification = @"TScreenShareBroadcastStartedNotification";
static NSString *TScreenShareBroadcastFinishedNotification = @"TScreenShareBroadcastFinishedNotification";
static NSString *TScreenShareBroadcastPausedNotification = @"TScreenShareBroadcastPausedNotification";
static NSString *TScreenShareBroadcastResumedNotification = @"TScreenShareBroadcastResumedNotification";

static NSString *TScreenShareNotification = @"TScreenShareNotification";

static const NSString *kIdentifier = @"identifier";

@interface FlutterWebRTCPlugin ()

@property (nonatomic, copy) FlutterResult result;

@property (nonatomic, copy) NSString *streamId;
@property (nonatomic, strong) NSDictionary *constraints;

@end

@implementation FlutterWebRTCPlugin (RTCMediaStream)

#if TARGET_OS_IPHONE

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastStartedNotification, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastFinishedNotification, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastPausedNotification, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastResumedNotification, NULL);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:TScreenShareNotification object:nil];
}

- (void)addScreenShareBroadcastNotification {
    // 屏幕共享开始
    [self registerNotificationsWithIdentifier:TScreenShareBroadcastStartedNotification];
    // 屏幕共享完成
    [self registerNotificationsWithIdentifier:TScreenShareBroadcastFinishedNotification];
    // 屏幕共享暂停
    [self registerNotificationsWithIdentifier:TScreenShareBroadcastPausedNotification];
    // 屏幕共享恢复
    [self registerNotificationsWithIdentifier:TScreenShareBroadcastResumedNotification];
    // 监听共享结果
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenShareAction:) name:TScreenShareNotification object:nil];
}

- (void)getDisplayScreenMedia:(NSDictionary *)constraints
                       result:(FlutterResult)result {
    RTCVideoSource *videoSource = [self.peerConnectionFactory videoSource];
    FlutterRPScreenRecorder *screenCapturer = [[FlutterRPScreenRecorder alloc] initWithDelegate:videoSource];
    [screenCapturer setConstraints:constraints];
  
    [screenCapturer startCapture];
    
    self.screenCapturer = screenCapturer;
    self.constraints = constraints;
    self.result = result;
}

#pragma mark -- 屏幕共享状态通知
- (void)screenShareAction:(NSNotification *)noti {
    NSDictionary *userInfo = noti.userInfo;
    NSString *identifier = userInfo[kIdentifier];
    if ([identifier isEqualToString:TScreenShareBroadcastStartedNotification]) {
        NSLog(@"onBroadcastStarted");
        [self startScreenShare];
        [self closeSystemPresention];
    } else if ([identifier isEqualToString:TScreenShareBroadcastFinishedNotification]) {
        NSLog(@"onBroadcastFinished");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self finishScreenShare];
        });

    } else if ([identifier isEqualToString:TScreenShareBroadcastPausedNotification]) {
        NSLog(@"onBroadcastPaused");

    } else if ([identifier isEqualToString:TScreenShareBroadcastResumedNotification]) {
        NSLog(@"onBroadcastResumed");
    }
}

static void NotificationCallback(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 void const *object,
                                 CFDictionaryRef userInfo) {
    NSString *identifier = (__bridge NSString *)name;
    NSObject *sender = (__bridge NSObject *)observer;
    NSDictionary *notiUserInfo = @{kIdentifier : identifier};
    [[NSNotificationCenter defaultCenter] postNotificationName:TScreenShareNotification object:sender userInfo:notiUserInfo];
}

#pragma mark -- privateMethod
- (void)registerNotificationsWithIdentifier:(NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str                      = (__bridge CFStringRef)identifier;
    
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)(self),
                                    NotificationCallback,
                                    str,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)startScreenShare {
    if (self.screenCapturer == nil) {
        RTCVideoSource *videoSource = [self.peerConnectionFactory videoSource];
        FlutterRPScreenRecorder *screenCapturer = [[FlutterRPScreenRecorder alloc] initWithDelegate:videoSource];
        [screenCapturer setConstraints:self.constraints];
        self.screenCapturer = screenCapturer;
    }
    NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
    self.streamId = mediaStreamId;
    RTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    RTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:self.screenCapturer.delegate trackId:trackUUID];
    [mediaStream addVideoTrack:videoTrack];

    NSMutableArray *audioTracks = [NSMutableArray array];
    NSMutableArray *videoTracks = [NSMutableArray array];

    for (RTCVideoTrack *track in mediaStream.videoTracks) {
        [self.localTracks setObject:track forKey:track.trackId];
        [videoTracks addObject:@{@"id" : track.trackId, @"kind" : track.kind, @"label" : track.trackId, @"enabled" : @(track.isEnabled), @"remote" : @(YES), @"readyState" : @"live"}];
    }

    self.localStreams[mediaStreamId] = mediaStream;
    if (self.result) {
        self.result(@{@"streamId" : mediaStreamId, @"audioTracks" : audioTracks, @"videoTracks" : videoTracks});
    }
}

- (void)finishScreenShare {
    NSString *streamId     = self.streamId;
    RTCMediaStream *stream = self.localStreams[streamId];
    if (stream) {
        NSMutableArray *removeTracks = [NSMutableArray array];
        for (RTCVideoTrack *track in stream.videoTracks) {
            [removeTracks addObject:track];
            [self.localTracks removeObjectForKey:track.trackId];
        }
        [self.localStreams removeObjectForKey:streamId];
        for (RTCVideoTrack *track in removeTracks) {
            [stream removeVideoTrack:track];
        }
    }
}

- (void)closeSystemPresention {
    NSArray *urlTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    NSDictionary *type = urlTypes.firstObject;
    if (type != nil) {
        NSArray *urlSchemes = type[@"CFBundleURLSchemes"];
        NSString *scheme = urlSchemes.firstObject;
        if (scheme != nil) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", scheme]];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

#pragma mark - getter && setting
- (FlutterResult)result {
    return objc_getAssociatedObject(self, @selector(result));
}

- (void)setResult:(FlutterResult)result {
    objc_setAssociatedObject(self, @selector(result), result, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)streamId {
    return objc_getAssociatedObject(self, @selector(streamId));
}

- (void)setStreamId:(NSString *)streamId {
    objc_setAssociatedObject(self, @selector(streamId), streamId, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSDictionary *)constraints {
    return objc_getAssociatedObject(self, @selector(constraints));
}

- (void)setConstraints:(NSDictionary *)constraints {
    objc_setAssociatedObject(self, @selector(constraints), constraints, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#endif

@end
