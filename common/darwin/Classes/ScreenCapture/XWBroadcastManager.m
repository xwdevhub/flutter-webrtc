//
//  XWBroadcastManager.m
//  ReplayLive
//
//  Created by lnd on 2022/5/5.
//

#import "XWBroadcastManager.h"
#import <ReplayKit/ReplayKit.h>

API_AVAILABLE(ios(12.0))
@interface XWBroadcastManager ()

@property (nonatomic, strong) RPSystemBroadcastPickerView *picker;

@end

@implementation XWBroadcastManager

static dispatch_once_t onceToken;

+ (instancetype)shareInstance {
    static XWBroadcastManager *_shareInstance = nil;
    dispatch_once(&onceToken, ^{
        _shareInstance = [[XWBroadcastManager alloc] init];
    });
    return _shareInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        if (@available(iOS 12.0, *)) {
            if (!self.picker) {
                self.picker                       = [[RPSystemBroadcastPickerView alloc] initWithFrame:CGRectZero];
                self.picker.showsMicrophoneButton = NO;
                NSString *path = [[NSBundle mainBundle] pathForResource:@"resource" ofType:@"plist"];
                NSDictionary *resource = [NSDictionary dictionaryWithContentsOfFile:path];
                NSString *preferredExtension = resource[@"share_extension_bundle_id"];
                if (preferredExtension == nil) {
                    preferredExtension = @"com.xanway.distribute.screenReplay";
                }
                self.picker.preferredExtension    = preferredExtension;
                for (NSObject *subView in self.picker.subviews) {
                    if ([subView isKindOfClass:[UIButton class]]) {
                        self.button = (UIButton *)subView;
                    }
                }
            }
        } else {
            NSLog(@"不支持录制系统屏幕");
        }
    }
    return self;
}

+ (void)clear {
    onceToken = 0;
}

- (void)dealloc {
    NSLog(@"%s", __func__);
}

@end
