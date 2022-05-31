#import <ReplayKit/ReplayKit.h>
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface XWClientSocket : NSObject
+ (XWClientSocket *)shared;
- (void)setUpSocket;
- (void)socketDelloc;
- (void)sendVideoBufferToHostApp:(CMSampleBufferRef)sampleBuffer;
- (long)getCurUsedMemory;
@end
NS_ASSUME_NONNULL_END
