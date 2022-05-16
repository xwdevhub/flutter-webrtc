#import "FlutterRPScreenRecorder.h"
#if TARGET_OS_IPHONE
#import "XWBroadcastManager.h"
#import "XWYUVConverter.h"
#import "libyuv.h"
#import <ReplayKit/ReplayKit.h>

//See: https://developer.apple.com/videos/play/wwdc2017/606/

static NSString *_Nonnull kAppGroup = @"group.com.xanway.weilink.ScreenReplay"; //!< 需要替换成自己的App Group
static void *KVOContext             = &KVOContext;

static NSString *TScreenShareBroadcastStartedNotification  = @"TScreenShareBroadcastStartedNotification";
static NSString *TScreenShareBroadcastFinishedNotification = @"TScreenShareBroadcastFinishedNotification";
static NSString *TScreenShareBroadcastPausedNotification   = @"TScreenShareBroadcastPausedNotification";
static NSString *TScreenShareBroadcastResumedNotification  = @"TScreenShareBroadcastResumedNotification";

static CFStringRef TScreenShareHostRequestStopNotification = (__bridge CFStringRef) @"TScreenShareHostRequestStopNotification";

@interface FlutterRPScreenRecorder ()

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@end

@implementation FlutterRPScreenRecorder {
    RTCVideoSource *source;
}

- (void)dealloc {
    if (_userDefaults) {
        [self.userDefaults removeObserver:self forKeyPath:@"frame"];
        _userDefaults = nil;
    }
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastStartedNotification, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastFinishedNotification, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastPausedNotification, NULL);
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)(self), (__bridge CFStringRef)TScreenShareBroadcastResumedNotification, NULL);
}

- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
    source = delegate;
    // 屏幕共享开始
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    onBroadcastStarted,
                                    (__bridge CFStringRef)TScreenShareBroadcastStartedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    // 屏幕共享完成
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    onBroadcastFinished,
                                    (__bridge CFStringRef)TScreenShareBroadcastFinishedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    // 屏幕共享暂停
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    onBroadcastPaused,
                                    (__bridge CFStringRef)TScreenShareBroadcastPausedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    // 屏幕共享暂停
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    onBroadcastResumed,
                                    (__bridge CFStringRef)TScreenShareBroadcastResumedNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    return [super initWithDelegate:delegate];
}

// 实现方法
static void onBroadcastStarted(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef
                               userInfo) {
    NSLog(@"onBroadcastStarted");
}

static void onBroadcastFinished(CFNotificationCenterRef center,
                                void *observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef
                                userInfo) {
    NSLog(@"onBroadcastFinished");
}

static void onBroadcastPaused(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef
                              userInfo) {
    NSLog(@"onBroadcastPaused");
}

static void onBroadcastResumed(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef
                               userInfo) {
    NSLog(@"onBroadcastResumed");
}

- (void)setupUserDefaults {
    // 通过UserDefaults建立数据通道，接收Extension传递来的视频帧
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroup];
    [self.userDefaults addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:KVOContext];
}

- (void)startCapture {
    
    if (@available(iOS 12.0, *)) {
        [[XWBroadcastManager shareInstance].button sendActionsForControlEvents:UIControlEventAllTouchEvents];
        if (!_userDefaults) {
            [self setupUserDefaults];
        }
    }
}

- (void)stopCapture {
    
    if (@available(iOS 12.0, *)) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), TScreenShareHostRequestStopNotification, nil, nil, true);
        if (_userDefaults) {
            [self.userDefaults removeObserver:self forKeyPath:@"frame"];
            _userDefaults = nil;
            [XWBroadcastManager clear];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"frame"]) {
        NSDictionary *i420Frame = change[NSKeyValueChangeNewKey];
        
        XWI420Frame *frame           = [XWI420Frame initWithData:i420Frame[@"data"]];
        CVPixelBufferRef pixelBuffer = [XWYUVConverter i420FrameToPixelBuffer:frame];
        
        size_t width  = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        
        [source adaptOutputFormatToWidth:(int)(width / 2) height:(int)(height / 2) fps:8];
        
        RTCCVPixelBuffer *rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
        RTCVideoFrame *videoFrame        = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
                                                                        rotation:RTCVideoRotation_0
                                                                     timeStampNs:[i420Frame[@"timestamp"] intValue]];
        [self.delegate capturer:self didCaptureVideoFrame:videoFrame];
        
        if (pixelBuffer != NULL) {
            CFRelease(pixelBuffer);
        }
    }
}

- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler {
    
    [self stopCapture];
    if (completionHandler != nil) {
        completionHandler();
    }
}

@end
#endif
