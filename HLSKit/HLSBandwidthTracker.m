//
//  HLSBandwidthTracker.m
//  HLSKit
//
//  Created by Nicholas White on 10/8/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import "HLSBandwidthTracker.h"

@implementation HLSBandwidthTracker {
    double _totalData;
    double _totalTime;
    NSMutableArray *_trailingData;
    int _numTrailing;
}

@synthesize numDatapoints = _numDatapoints;

- (instancetype)init {
    if (self = [super init]) {
        _trailingData = [NSMutableArray array];
        _numTrailing = 3;
    }
    return self;
}

- (double)averageBitrate {
    return _totalData / _totalTime;
}

- (double)trailingAverageBitrate {
    if (!_trailingData.count) return 0;
    double finalRate = 0;
    for (NSNumber *rate in _trailingData) {
        finalRate += [rate doubleValue];
    }
    return finalRate / _trailingData.count;
}

- (void)addDatapoint:(NSUInteger)bytes time:(double)time {
    _totalTime += time;
    _totalData += (double)bytes * 8.0;
    while (_trailingData.count >= _numTrailing) {
        [_trailingData removeObjectAtIndex:0];
    }
    [_trailingData addObject:@(8.0 * bytes / time)];
}

@end
