#import "FlutterRPScreenRecorder.h"
#if TARGET_OS_IPHONE
#import <ReplayKit/ReplayKit.h>
#import "libyuv.h"
#import "XWYUVConverter.h"
#import "XWBroadcastManager.h"
#import "XWServerSocket.h"

//See: https://developer.apple.com/videos/play/wwdc2017/606/


static const int DEFAULT_WIDTH = 1280;
static const int DEFAULT_HEIGHT = 720;
static const int DEFAULT_FPS = 30;

//static void *KVOContext = &KVOContext;

static CFStringRef TScreenShareHostRequestStopNotification = (__bridge CFStringRef)@"TScreenShareHostRequestStopNotification";

@interface FlutterRPScreenRecorder ()

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@property (nonatomic, strong) NSDictionary *videoConstraints;

@end

@implementation FlutterRPScreenRecorder {
    RTCVideoSource *_source;
}

- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
    _source = delegate;
    if (self = [super initWithDelegate:_source]) {
        XWServerSocket *serverSocket = [XWServerSocket shared];
        [serverSocket setupSocket];
        __weak typeof(self) wSelf = self;
        [serverSocket setOnBufferReceived:^(CMSampleBufferRef sampleBuffer) {
            __strong typeof(wSelf) self = wSelf;
            [self onBufferReceived:sampleBuffer];
        }];
    }
    return self;
}

- (void)onBufferReceived:(CMSampleBufferRef)sampleBuffer {
    if (!CMSampleBufferIsValid(sampleBuffer)) {
        return;
    }

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

//    size_t width = CVPixelBufferGetWidth(pixelBuffer);
//    size_t height = CVPixelBufferGetHeight(pixelBuffer);

//    int width = [self->_videoConstraints[@"width"] intValue];
//    int height = [self->_videoConstraints[@"height"] intValue];
//    int fps = [self->_videoConstraints[@"fps"] intValue];
//
//    [self->_source adaptOutputFormatToWidth:width height:height fps:fps];

    int64_t timeStampNs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * NSEC_PER_SEC;

    RTCCVPixelBuffer *rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
    RTCVideoFrame *videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
                                                             rotation:RTCVideoRotation_0
                                                          timeStampNs:timeStampNs];
    [self.delegate capturer:self didCaptureVideoFrame:videoFrame];
}

- (void)setupUserDefaults {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"ScreenReplay" ofType:@"entitlements"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *groupID = [dict[@"com.apple.security.application-groups"] firstObject];
    if (groupID == nil) {
        NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"resource" ofType:@"plist"];
        NSDictionary *resource = [NSDictionary dictionaryWithContentsOfFile:resourcePath];
        groupID = resource[@"screen_replay_extension_group_id"];
    }
    if (groupID == nil) {
        groupID = @"group.com.xanway.weilink.ScreenReplay";
    }
    // 通过UserDefaults建立数据通道，接收Extension传递来的视频帧
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:groupID];
//    [self.userDefaults addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:KVOContext];
}

- (void)startCapture {
    if (@available(iOS 12.0, *)) {
        [[XWBroadcastManager shareInstance].button sendActionsForControlEvents:UIControlEventAllTouchEvents];
        if (!_userDefaults) {
            [self setupUserDefaults];
        }
        [_userDefaults setObject:@"gortc" forKey:@"requester"];
    }
}

- (void)stopCapture {
    if (@available(iOS 12.0, *)) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), TScreenShareHostRequestStopNotification, nil, nil, true);
        if (_userDefaults) {
//            [self.userDefaults removeObserver:self forKeyPath:@"frame"];
            _userDefaults = nil;
            [XWBroadcastManager clear];
        }
    }
    [[XWServerSocket shared] stopSocket];
}

- (void)setConstraints:(NSDictionary *)constraints {
    NSDictionary *videoConstraints = constraints[@"video"];
    NSNumber *width = videoConstraints[@"width"] != nil ? videoConstraints[@"width"] : @(DEFAULT_WIDTH);
    NSNumber *height = videoConstraints[@"height"] != nil ? videoConstraints[@"height"] : @(DEFAULT_HEIGHT);
    NSNumber *fps = videoConstraints[@"fps"] != nil ? videoConstraints[@"fps"] : @(DEFAULT_FPS);
    _videoConstraints = @{
        @"width" : width,
        @"height" : height,
        @"fps" : fps
    };
}

- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler {
    [self stopCapture];
    if(completionHandler != nil) {
        completionHandler();
    }
}

@end
#endif
