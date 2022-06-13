//
//  XWRecvTansport.m
//  flutter_webrtc
//
//  Created by QiangJindong on 2022/6/13.
//

#import "XWRecvTansport.h"
#import "GCDAsyncSocket.h"
#import "XWReplayConvertTool.h"

struct SampleBufferHead {
    int32_t sampleBufferLength;
    int16_t sampleBufferWidth;
    int16_t sampleBufferHeight;
    int64_t timeStamp;
};

@interface XWRecvTansport () <GCDAsyncSocketDelegate>

@end

@implementation XWRecvTansport {
    NSString *_host;
    uint16_t _port;
    GCDAsyncSocket *_socket;
    NSMutableArray<GCDAsyncSocket *> *_sockets;
    NSMutableData *_cacheData;
    dispatch_queue_t _queue;
    dispatch_queue_t _videoProcessQueue;
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port {
    if (self = [super init]) {
        _host = host;
        _port = port;
        _sockets = [NSMutableArray array];
        _cacheData = [NSMutableData data];
    }
    return self;
}

- (void)dealloc {
    [self reset];
}

- (void)connect {
    _queue = dispatch_get_main_queue();
    _socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_queue];
    [_socket acceptOnPort:8999 error:nil];
    [_socket readDataWithTimeout:-1 tag:0];
}

- (void)reset {
    if (_socket && _socket.isConnected) {
        [_socket disconnect];
        _socket = nil;
    }
    [_sockets removeAllObjects];
    _cacheData = [NSMutableData data];
}

#pragma mark - GCDAsyncSocketDelegate
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    _socket = nil;
    [self connect];
}

- (void)socketDidCloseReadStream:(GCDAsyncSocket *)sock {
    [_sockets removeObject:sock];
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    [_sockets addObject:newSocket];
    [newSocket readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    [_cacheData appendData:data];

    struct SampleBufferHead head;
    memcpy(&head, _cacheData.bytes, sizeof(head));
//    NSLog(@">>>length %d, w %d, h %d ", head.sampleBufferLength, head.sampleBufferWidth, head.sampleBufferHeight);

    int32_t sampleBufferLength = (int32_t)head.sampleBufferLength;

    if (_cacheData.length > sizeof(head) + sampleBufferLength) {
        void *buffer = malloc(sampleBufferLength);
        memcpy(buffer, _cacheData.bytes + sizeof(head), head.sampleBufferLength);

        CVPixelBufferRef pixelBuffer = [XWReplayConvertTool createCVPixelBufferRefFromBuffer:buffer
                                                                                        size:head.sampleBufferLength
                                                                                       width:head.sampleBufferWidth
                                                                                      height:head.sampleBufferHeight];

        int32_t otherLength = (int32_t)_cacheData.length - sampleBufferLength - sizeof(head);
        void *other = malloc(otherLength);
        memcpy(other, _cacheData.bytes + head.sampleBufferLength + sizeof(head), otherLength);

        _cacheData = [NSMutableData dataWithBytes:other length:otherLength];

        if ([self.delegate respondsToSelector:@selector(transport:didReceivedBuffer:info:)]) {
            NSDictionary *info = @{
                @"length" : @(head.sampleBufferLength),
                @"width" : @(head.sampleBufferWidth),
                @"height" : @(head.sampleBufferHeight),
                @"timeStamp" : @(head.timeStamp),
            };
            [self.delegate transport:self didReceivedBuffer:pixelBuffer info:info];
        }

        free(other);
        free(buffer);
        CVPixelBufferRelease(pixelBuffer);
    }

    [sock readDataWithTimeout:-1 tag:0];
}

@end
