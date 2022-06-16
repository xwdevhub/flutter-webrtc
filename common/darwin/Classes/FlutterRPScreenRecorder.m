#import "FlutterRPScreenRecorder.h"
#if TARGET_OS_IPHONE
#import <ReplayKit/ReplayKit.h>
#import "XWBroadcastManager.h"
#import "XWRecvTansport.h"

//See: https://developer.apple.com/videos/play/wwdc2017/606/

static const int DEFAULT_WIDTH = 1280;
static const int DEFAULT_HEIGHT = 720;
static const int DEFAULT_FPS = 30;

static CFStringRef TScreenShareHostRequestStopNotification = (__bridge CFStringRef) @"TScreenShareHostRequestStopNotification";

@interface FlutterRPScreenRecorder () <XWRecvTansportDelegate>

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@property (nonatomic, strong) NSDictionary *videoConstraints;

@end

@implementation FlutterRPScreenRecorder {
    RTCVideoSource *_source;
    XWRecvTansport *_recvTransport;
}

- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
    _source = delegate;
    if (self = [super initWithDelegate:_source]) {
        _recvTransport = [[XWRecvTansport alloc] initWithHost:@"127.0.0.1" port:8999];
        [_recvTransport connect];
        _recvTransport.delegate = self;
    }
    return self;
}

- (void)transport:(XWRecvTansport *)transport didReceivedBuffer:(CVPixelBufferRef)pixelBuffer info:(NSDictionary *)info {
    int64_t timeStamp = [info[@"timeStamp"] integerValue];
    int w = [info[@"width"] intValue];
    int h = [info[@"height"] intValue];

    int width = [self->_videoConstraints[@"width"] intValue];
    //  int height = [self->_videoConstraints[@"height"] intValue];
    int fps = [self->_videoConstraints[@"fps"] intValue];

    [self->_source adaptOutputFormatToWidth:width height:width * h / w fps:fps];

    RTCCVPixelBuffer *rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
    RTCVideoFrame *videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
                                                             rotation:RTCVideoRotation_0
                                                          timeStampNs:timeStamp];

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
            _userDefaults = nil;
            [XWBroadcastManager clear];
        }
    }
    [_recvTransport reset];
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
    if (completionHandler != nil) {
        completionHandler();
    }
}

@end
#endif
