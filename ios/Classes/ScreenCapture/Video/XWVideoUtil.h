//
//
//  Created by fenric on 17/3/20.
//  Copyright © 2017年 Netease. All rights reserved.
//

#import <CoreMedia/CMFormatDescription.h>
#import <Foundation/Foundation.h>

@interface XWVideoUtil : NSObject

+ (CMVideoDimensions)outputVideoDimens:(CMVideoDimensions)inputDimens
                                  crop:(float)ratio;

+ (CMVideoDimensions)calculateDiemnsDividedByTwo:(int)width andHeight:(int)height;

+ (CMVideoDimensions)outputVideoDimensEnhanced:(CMVideoDimensions)inputDimens crop:(float)ratio;

@end
