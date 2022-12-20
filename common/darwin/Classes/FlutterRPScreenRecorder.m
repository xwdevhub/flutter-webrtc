#import "FlutterRPScreenRecorder.h"
#if TARGET_OS_IPHONE
#import <ReplayKit/ReplayKit.h>
#import "XWBroadcastManager.h"
#import "XWRecvTansport.h"

// See: https://developer.apple.com/videos/play/wwdc2017/606/

static const int DEFAULT_WIDTH = 1280;
static const int DEFAULT_HEIGHT = 720;
static const int DEFAULT_FPS = 30;

static CFStringRef TScreenShareHostRequestStopNotification = (__bridge CFStringRef) @"TScreenShareHostRequestStopNotification";

@interface FlutterRPScreenRecorder () <XWRecvTansportDelegate>

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@property (nonatomic, strong) NSDictionary *videoConstraints;

@end

@implementation FlutterRPScreenRecorder {
  // RPScreenRecorder* screenRecorder;
  // RTCVideoSource* source;
  RTCVideoSource *_source;
  XWRecvTansport *_recvTransport;
}

// - (instancetype)initWithDelegate:(__weak id<RTCVideoCapturerDelegate>)delegate {
//   source = delegate;
//   return [super initWithDelegate:delegate];
// }

// - (void)startCapture {
//   if (screenRecorder == NULL)
//     screenRecorder = [RPScreenRecorder sharedRecorder];

//   [screenRecorder setMicrophoneEnabled:NO];

//   if (![screenRecorder isAvailable]) {
//     NSLog(@"FlutterRPScreenRecorder.startCapture: Screen recorder is not available!");
//     return;
//   }

//   if (@available(iOS 11.0, *)) {
//     [screenRecorder
//         startCaptureWithHandler:^(CMSampleBufferRef _Nonnull sampleBuffer,
//                                   RPSampleBufferType bufferType, NSError* _Nullable error) {
//           if (bufferType == RPSampleBufferTypeVideo) {  // We want video only now
//             [self handleSourceBuffer:sampleBuffer sampleType:bufferType];
//           }
//         }
//         completionHandler:^(NSError* _Nullable error) {
//           if (error != nil)
//             NSLog(@"!!! startCaptureWithHandler/completionHandler %@ !!!", error);
//         }];
//   } else {
//     // Fallback on earlier versions
//     NSLog(@"FlutterRPScreenRecorder.startCapture: Screen recorder is not available in versions "
//           @"lower than iOS 11 !");
//   }
// }

// - (void)stopCapture {
//   if (@available(iOS 11.0, *)) {
//     [screenRecorder stopCaptureWithHandler:^(NSError* _Nullable error) {
//       if (error != nil)
//         NSLog(@"!!! stopCaptureWithHandler/completionHandler %@ !!!", error);
//     }];
//   } else {
//     // Fallback on earlier versions
//     NSLog(@"FlutterRPScreenRecorder.stopCapture: Screen recorder is not available in versions "
//           @"lower than iOS 11 !");
//   }
// }

// - (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler {
//   [self stopCapture];
//   if (completionHandler != nil) {
//     completionHandler();
//   }
// }

// - (void)handleSourceBuffer:(CMSampleBufferRef)sampleBuffer
//                 sampleType:(RPSampleBufferType)sampleType {
//   if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
//       !CMSampleBufferDataIsReady(sampleBuffer)) {
//     return;
//   }

//   CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//   if (pixelBuffer == nil) {
//     return;
//   }

//   size_t width = CVPixelBufferGetWidth(pixelBuffer);
//   size_t height = CVPixelBufferGetHeight(pixelBuffer);

//   [source adaptOutputFormatToWidth:(int)(width / 2) height:(int)(height / 2) fps:8];

//   RTCCVPixelBuffer* rtcPixelBuffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
//   int64_t timeStampNs =
//       CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * NSEC_PER_SEC;
//   RTCVideoFrame* videoFrame = [[RTCVideoFrame alloc] initWithBuffer:rtcPixelBuffer
//                                                            rotation:RTCVideoRotation_0
//                                                         timeStampNs:timeStampNs];
//   [self.delegate capturer:self didCaptureVideoFrame:videoFrame];
// }

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

- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler {
    [self stopCapture];
    if (completionHandler != nil) {
        completionHandler();
    }
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

@end
#endif
