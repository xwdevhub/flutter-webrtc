#import <WebRTC/WebRTC.h>
#if TARGET_OS_IPHONE
@interface FlutterRPScreenRecorder : RTCVideoCapturer

- (void)startCapture;

- (void)startCaptureWithConstraints:(nullable NSDictionary *)constraints;

// Stops the capture session asynchronously and notifies callback on completion.
- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler;

-(void)stopCapture;

@end
#endif
