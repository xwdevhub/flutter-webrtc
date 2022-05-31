

#import "XWClientSocket.h"

#import "Video/XWYUVConverter.h"
#import "Video/XWVideoUtil.h"
#import "GCDAsyncSocket.h"
#import "NTESSocketPacket.h"
#import "NTESTPCircularBuffer.h"
#import <mach/mach.h>

@interface XWClientSocket () <GCDAsyncSocketDelegate> {
    long evenlyMem;
}

@property (nonatomic, strong) dispatch_queue_t videoQueue;
@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, assign) BOOL connected;

@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation XWClientSocket
+ (XWClientSocket *)shared {
    static XWClientSocket *shareInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[self alloc] init];
        shareInstance.videoQueue = dispatch_queue_create("com.replaykit.videoprocess", DISPATCH_QUEUE_SERIAL);
    });
    return shareInstance;
}

- (void)setUpSocket {
    self.queue = dispatch_queue_create("com.replaykit.client", DISPATCH_QUEUE_SERIAL);
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    NSError *error;
    [self.socket connectToHost:@"127.0.0.1" onPort:8999 error:&error];
    NSLog(@"setupSocket:%@", error);
}

- (void)socketDelloc {
    _connected = NO;

    if (_socket) {
        [_socket disconnect];
        _socket = nil;
    }
}

#pragma mark - Process
- (void)sendVideoBufferToHostApp:(CMSampleBufferRef)sampleBuffer {
    if (!self.socket) {
        return;
    }
    if (self.frameCount > 0) {
        //每次只处理1帧画面
        return;
    }
    long curMem = [self getCurUsedMemory];
    //    NSLog(@"curMem:%@", @(curMem / 1024.0 / 1024.0));
    //    if (evenlyMem > 0
    //        && (curMem > evenlyMem
    //            || curMem > 45 * 1024 * 1024)) {
    //        //当前内存暴增2M以上，或者总共超过45M，则不处理
    //        return;
    //    }
    if (curMem > 40 * 1024 * 1024) {
        return;
    }

    self.frameCount++;

    CFRetain(sampleBuffer);
    dispatch_async(self.videoQueue, ^{ // queue optimal
        @autoreleasepool {
            CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

          // 方式一：
//            size_t width = CVPixelBufferGetWidth(pixelBuffer);
//            size_t height = CVPixelBufferGetHeight(pixelBuffer);
//            float cropRate = 1.0 * width / height;
//            CGSize targetSize = CGSizeMake(width, height);
//            XWVideoPackOrientation targetOrientation = XWVideoPackOrientationPortrait;
//            if (@available(iOS 11.0, *)) {
//                CFStringRef RPVideoSampleOrientationKeyRef = (__bridge CFStringRef)RPVideoSampleOrientationKey;
//                NSNumber *orientation = (NSNumber *)CMGetAttachment(sampleBuffer, RPVideoSampleOrientationKeyRef, NULL);
//                if (orientation.integerValue == kCGImagePropertyOrientationUp ||
//                    orientation.integerValue == kCGImagePropertyOrientationUpMirrored) {
//                    targetOrientation = XWVideoPackOrientationPortrait;
//                } else if (orientation.integerValue == kCGImagePropertyOrientationDown ||
//                           orientation.integerValue == kCGImagePropertyOrientationDownMirrored) {
//                    targetOrientation = XWVideoPackOrientationPortraitUpsideDown;
//                } else if (orientation.integerValue == kCGImagePropertyOrientationLeft ||
//                           orientation.integerValue == kCGImagePropertyOrientationLeftMirrored) {
//                    targetOrientation = XWVideoPackOrientationLandscapeLeft;
//                } else if (orientation.integerValue == kCGImagePropertyOrientationRight ||
//                           orientation.integerValue == kCGImagePropertyOrientationRightMirrored) {
//                    targetOrientation = XWVideoPackOrientationLandscapeRight;
//                }
//            }
//            XWI420Frame *videoFrame = [XWYUVConverter pixelBufferToI420:pixelBuffer
//                                                               withCrop:cropRate
//                                                             targetSize:targetSize
//                                                         andOrientation:targetOrientation];

            // To data
            // 方式二：
            XWI420Frame *videoFrame = [XWYUVConverter pixelBufferToI420:pixelBuffer scale:0.5];

            CFRelease(sampleBuffer);

            // To Host App
            if (videoFrame) {
                __block NSUInteger length = 0;
                [videoFrame getBytesQueue:^(NSData *data, NSInteger index) {
                    length += data.length;
                    [self.socket writeData:data withTimeout:5 tag:0];
                    data = NULL;
                    data = nil;
                }];
                [self.socket writeData:[NTESSocketPacket packetWithBufferLength:length] withTimeout:5 tag:0];
            }
        }
        //        if (self->evenlyMem <= 0) {
        //            self->evenlyMem = [self getCurUsedMemory];
        //            NSLog(@"平均内存:%@", @(self->evenlyMem));
        //        }
        self.frameCount--;
    });
}

#pragma mark - Socket

- (void)setupSocket {
    self.queue = dispatch_queue_create("com.replaykit.client", DISPATCH_QUEUE_SERIAL);
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.queue];
    NSError *error;
    [self.socket connectToHost:@"127.0.0.1" onPort:8999 error:&error];
    [self.socket readDataWithTimeout:-1 tag:0];
    NSLog(@"setupSocket:%@", error);
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToUrl:(NSURL *)url {
    [self.socket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    [self.socket readDataWithTimeout:-1 tag:0];
    self.connected = YES;
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    self.connected = NO;
    [self.socket disconnect];
    self.socket = nil;
    [self setupSocket];
    [self.socket readDataWithTimeout:-1 tag:0];
}

- (long)getCurUsedMemory {
    struct task_basic_info info;
    mach_msg_type_number_t size = TASK_BASIC_INFO_COUNT; //sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    long cur_used_mem = (kerr == KERN_SUCCESS) ? info.resident_size : 0; // size in bytes
    return cur_used_mem;
}

@end
