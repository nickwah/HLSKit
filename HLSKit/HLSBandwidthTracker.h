//
//  HLSBandwidthTracker.h
//  HLSKit
//
//  Created by Nicholas White on 10/8/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HLSBandwidthTracker : NSObject

@property (readonly) double averageBitrate; // In bits/sec
@property (readonly) double trailingAverageBitrate; // In bits/sec
@property (nonatomic) int numDatapoints;

- (void)addDatapoint:(NSUInteger)bytes time:(double)time;

@end
