#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef void(^OnBufferReceived) (CMSampleBufferRef sampleBuffer);

@interface XWServerSocket : NSObject
+ (XWServerSocket *)shared;
- (void)stopSocket;
- (void)setupSocket;
@property(nonatomic, copy) OnBufferReceived onBufferReceived;
@end
NS_ASSUME_NONNULL_END
