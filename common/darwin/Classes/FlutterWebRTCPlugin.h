#if TARGET_OS_IPHONE
#import <Flutter/Flutter.h>
#elif TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#endif

#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

// <<< 自定义iOS屏幕共享采集
#if TARGET_OS_IPHONE
#import "FlutterRPScreenRecorder.h"
#endif
// 自定义iOS屏幕共享采集 >>>

@class FlutterRTCVideoRenderer;
@class FlutterRTCFrameCapturer;

typedef void (^CompletionHandler)(void);

typedef void (^CapturerStopHandler)(CompletionHandler handler);

@interface FlutterWebRTCPlugin : NSObject <FlutterPlugin,
                                           RTCPeerConnectionDelegate,
                                           FlutterStreamHandler
#if TARGET_OS_OSX
                                           ,
                                           RTCDesktopMediaListDelegate,
                                           RTCDesktopCapturerDelegate
#endif
                                           >

@property(nonatomic, strong) RTCPeerConnectionFactory* peerConnectionFactory;
@property(nonatomic, strong) NSMutableDictionary<NSString*, RTCPeerConnection*>* peerConnections;
@property(nonatomic, strong) NSMutableDictionary<NSString*, RTCMediaStream*>* localStreams;
@property(nonatomic, strong) NSMutableDictionary<NSString*, RTCMediaStreamTrack*>* localTracks;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, FlutterRTCVideoRenderer*>* renders;
@property(nonatomic, strong)
    NSMutableDictionary<NSString*, CapturerStopHandler>* videoCapturerStopHandlers;

@property(nonatomic, strong) NSMutableDictionary<NSString*, RTCFrameCryptor*>* frameCryptors;
@property(nonatomic, strong) NSMutableDictionary<NSString*, RTCFrameCryptorKeyProvider*>* keyProviders;

#if TARGET_OS_IPHONE
@property(nonatomic, retain) UIViewController* viewController; /*for broadcast or ReplayKit */
#endif

@property(nonatomic, strong) FlutterEventSink eventSink;
@property(nonatomic, strong) NSObject<FlutterBinaryMessenger>* messenger;
@property(nonatomic, strong) RTCCameraVideoCapturer* videoCapturer;
@property(nonatomic, strong) FlutterRTCFrameCapturer* frameCapturer;
@property(nonatomic, strong) AVAudioSessionPort preferredInput;
@property(nonatomic) BOOL _usingFrontCamera;
@property(nonatomic) NSInteger _lastTargetWidth;
@property(nonatomic) NSInteger _lastTargetHeight;
@property(nonatomic) NSInteger _lastTargetFps;

// <<< 自定义iOS屏幕共享采集
#if TARGET_OS_IPHONE
@property (nonatomic, strong) FlutterRPScreenRecorder *screenCapturer;
#endif
// 自定义iOS屏幕共享采集 >>>

- (RTCMediaStream*)streamForId:(NSString*)streamId peerConnectionId:(NSString*)peerConnectionId;
- (RTCRtpTransceiver*)getRtpTransceiverById:(RTCPeerConnection*)peerConnection Id:(NSString*)Id;
- (NSDictionary*)mediaStreamToMap:(RTCMediaStream*)stream ownerTag:(NSString*)ownerTag;

- (NSDictionary*)mediaTrackToMap:(RTCMediaStreamTrack*)track;
- (NSDictionary*)receiverToMap:(RTCRtpReceiver*)receiver;
- (NSDictionary*)transceiverToMap:(RTCRtpTransceiver*)transceiver;

- (BOOL)hasLocalAudioTrack;
- (void)ensureAudioSession;
- (void)deactiveRtcAudioSession;

- (RTCRtpReceiver*)getRtpReceiverById:(RTCPeerConnection*)peerConnection Id:(NSString*)Id;
- (RTCRtpSender*)getRtpSenderById:(RTCPeerConnection*)peerConnection Id:(NSString*)Id;

@end
