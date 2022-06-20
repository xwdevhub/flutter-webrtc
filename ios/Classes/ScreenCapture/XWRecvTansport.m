//
//  XWRecvTansport.m
//  flutter_webrtc
//
//  Created by QiangJindong on 2022/6/13.
//

#import "XWRecvTansport.h"
#import "GCDAsyncSocket.h"
#import "XWReplayConvertTool.h"

@interface XWRecvTansport () <GCDAsyncSocketDelegate>

@end

@implementation XWRecvTansport {
    NSString *_host;
    uint16_t _port;
    GCDAsyncSocket *_socket;
    NSMutableArray<GCDAsyncSocket *> *_sockets;
    NSMutableData *_cacheData;
    dispatch_queue_t _queue;
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

- (void)connect {
    //    _queue = dispatch_queue_create("com.webrtc.replay.recv", DISPATCH_QUEUE_SERIAL);
    _queue = dispatch_get_main_queue();
    _socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_queue];
    [_socket acceptOnPort:8999 error:nil];
    [_socket readDataWithTimeout:-1 tag:0];
}

- (void)reset {
    dispatch_async(_queue, ^{
        if (self->_socket && self->_socket.isConnected) {
            [self->_socket disconnect];
            self->_socket = nil;
        }
        [self->_sockets removeAllObjects];
        self->_cacheData = [NSMutableData data];
    });
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
    @autoreleasepool {
        [_cacheData appendData:data];

        struct PixelBufferHead head;
        memcpy(&head, _cacheData.bytes, sizeof(head));
//        NSLog(@">>>size %d, w %d, h %d, cache %lu", head.size, head.width, head.height, (unsigned long)_cacheData.length);

        int32_t bufferSize = (int32_t)head.size;

        while (_cacheData.length >= sizeof(head) + bufferSize) {
            void *buffer = malloc(bufferSize);
            memcpy(buffer, _cacheData.bytes + sizeof(head), bufferSize);

            CVPixelBufferRef pixelBuffer = [XWReplayConvertTool createCVPixelBufferRefFromNV12buffer:buffer head:head];
            free(buffer);

            int32_t leftOverSize = (int32_t)_cacheData.length - sizeof(head) - bufferSize;
            if (leftOverSize > 0) {
                void *leftOver = malloc(leftOverSize);
                memcpy(leftOver, _cacheData.bytes + sizeof(head) + bufferSize, leftOverSize);
                _cacheData = [NSMutableData dataWithBytes:leftOver length:leftOverSize];
                free(leftOver);
            } else {
                _cacheData = [NSMutableData data];
            }

            if ([self.delegate respondsToSelector:@selector(transport:didReceivedBuffer:info:)]) {
                NSDictionary *info = @{
                    @"size" : @(bufferSize),
                    @"width" : @(head.width),
                    @"height" : @(head.height),
                    @"timeStamp" : @(head.timeStamp),
                };
                [self.delegate transport:self didReceivedBuffer:pixelBuffer info:info];
            }
            CVPixelBufferRelease(pixelBuffer);
        }

        [sock readDataWithTimeout:-1 tag:0];
    }
}

@end
