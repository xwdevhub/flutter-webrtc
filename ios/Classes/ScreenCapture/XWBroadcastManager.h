//
//  XWBroadcastManager.h
//  ReplayLive
//
//  Created by lnd on 2022/5/5.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XWBroadcastManager : NSObject

@property (nonatomic, strong) UIButton *button;

+(instancetype)shareInstance;

+ (void)clear;

@end

NS_ASSUME_NONNULL_END
