#import "FlutterRPScreenRecorder.h"
#if TARGET_OS_IPHONE
#import <ReplayKit/ReplayKit.h>
#import "libyuv.h"
#import "XWYUVConverter.h"
#import "XWBroadcastManager.h"

//See: https://developer.apple.com/videos/play/wwdc2017/606/

static const int DEFAULT_WIDTH = 1280;
static const int DEFAULT_HEIGHT = 720;
static const int DEFAULT_FPS = 30;

static void *KVOContext = &KVOContext;

static CFStringRef TScreenShareHostRequestStopNotification = (__bridge CFStringRef)@"TScreenShareHostRequestStopNotification";

@interface FlutterRPScreenRecorder ()

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@property (nonatomic, strong) NSDictionary *videoConstraints;

@end

@implementation FlutterRPScreenRecorder {
    RTCVideoSource *source;
}

- (void)dealloc {
    if (_userDefaults) {
        [self.userDefaults removeObserver:self forKeyPath:@"frame"];
        _userDefaults = nil;
    }
}

- (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
    source = delegate;
    return [super initWithDelegate:delegate];
}

- (void)setupUserDefaults {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"ScreenReplay" ofType:@"entitlements"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *groupID = [dict[@"com.apple.security.application-groups"] firstObject];
    if (groupID == nil) {
        groupID = @"group.com.xanway.weilink.ScreenReplay";
    }
    // 通过UserDefaults建立数据通道，接收Extension传递来的视频帧
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:groupID];
    [self.userDefaults addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:KVOContext];
}

- (void)startCapture {
  [self startCaptureWithConstraints:nil];
}

- (void)startCaptureWithConstraints:(NSDictionary *)constraints {
    if (@available(iOS 12.0, *)) {
        [[XWBroadcastManager shareInstance].button sendActionsForControlEvents:UIControlEventAllTouchEvents];
        if (!_userDefaults) {
            [self setupUserDefaults];
        }
        NSDictionary *videoConstraints = constraints[@"video"];
        NSNumber *width = videoConstraints[@"width"] != nil ? videoConstraints[@"width"] : @(DEFAULT_WIDTH);
        NSNumber *height = videoConstraints[@"height"] != nil ? videoConstraints[@"height"] : @(DEFAULT_HEIGHT);
        NSNumber *fps = videoConstraints[@"fps"] != nil ? videoConstraints[@"fps"] : @(DEFAULT_FPS);
        _videoConstraints = @{
            @"width" : width,
            @"height" : height,
            @"fps" : fps
        };
        [_userDefaults setObject:@"gortc" forKey:@"requester"];
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

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"frame"]) {
        NSDictionary *i420Frame = change[NSKeyValueChangeNewKey];
        
        XWI420Frame *frame = [XWI420Frame initWithData:i420Frame[@"data"]];
        CVPixelBufferRef pixelBuffer = [XWYUVConverter i420FrameToPixelBuffer:frame];
        
//        size_t width = CVPixelBufferGetWidth(pixelBuffer);
//        size_t height = CVPixelBufferGetHeight(pixelBuffer);

        int width = [_videoConstraints[@"width"] intValue];
        int height = [_videoConstraints[@"height"] intValue];
        int fps = [_videoConstraints[@"fps"] intValue];
        [source adaptOutputFormatToWidth:width height:height fps:fps];

        RTCCVPixelBuffer *rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
        RTCVideoFrame *videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
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
    if(completionHandler != nil) {
        completionHandler();
    }
}

@end
#endif
