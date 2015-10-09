//
//  HLSDownloader.m
//  HLSKit
//
//  Created by Nicholas White on 10/7/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import "HLSDownloader.h"
#import "HLSBandwidthTracker.h"
#import "HLSNetworkManager.h"
#import "M3U8Kit.h"
@import QuartzCore;

@implementation HLSDownloader {
    NSString *_url;
    NSString *_baseUrl;
    NSTimer *_timer;
    M3U8MasterPlaylist *_masterList;
    M3U8MediaPlaylist *_mediaList;
    NSString *_lastPlaylistResponse;
    BOOL _networkBusy;
    NSMutableSet *_seenSegments;
    HLSBandwidthTracker *_bandwidthTracker;
}
@synthesize numLevels = _numLevels;
@synthesize currentLevel = _currentLevel;
@synthesize bufferTime = _bufferTime;
@synthesize logLevel = _logLevel;

- (instancetype)initWithUrl:(NSString *)url {
    return [self initWithUrl:url delegate:nil];
}

- (instancetype)initWithUrl:(NSString *)url delegate:(id<HLSDownloaderDelegate>)delegate {
    if (self = [super init]) {
        _url = url;
        self.delegate = delegate;
        self.refreshInterval = 0.5;
        _currentLevel = -1;
        _bufferTime = 2.0;
        _seenSegments = [NSMutableSet set];
        _bandwidthTracker = [[HLSBandwidthTracker alloc] init];
    }
    return self;
}

- (NSString*)url {
    return _url;
}

- (void)play {
    if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:self.refreshInterval target:self selector:@selector(refreshPlaylist) userInfo:nil repeats:YES];
        // do it now!
        [self refreshPlaylist];
    }
}
- (void)stop {
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
        [self.delegate downloaderStopped:self];
    }
}
- (void)dealloc {
    [self stop];
}

- (void)refreshPlaylist {
    if (_networkBusy) return;
    if (_masterList && _mediaList && _currentLevel > -1) {
        NSArray *streamUrls = _masterList.allStreamURLs;
        [self fetchPlaylist:streamUrls[_currentLevel] baseUrl:_masterList.baseURL];
    } else {
        [self fetchPlaylist:_url baseUrl:_baseUrl];
    }
}
- (void)setCurrentLevel:(int)currentLevel {
    if (_currentLevel != currentLevel) {
        if (_logLevel >= HLSLogLevelInfo)
            NSLog(@"Change HLS level to %d", currentLevel);
        _mediaList = nil;
        _currentLevel = currentLevel;
    }
}

- (void)fetchPlaylist:(NSString*) url baseUrl:(NSString *)baseUrl {
    if (_logLevel >= HLSLogLevelDebug)
        NSLog(@"Fetch %@ with base url %@", url, baseUrl);
    if (baseUrl) {
        url = [[NSURL URLWithString:url relativeToURL:[NSURL URLWithString:baseUrl]] absoluteString];
    }
    _networkBusy = YES;
    __weak typeof(self)weakSelf = self;
    [[HLSNetworkManager sharedManager] getString:url success:^(NSString *response) {
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_networkBusy = NO;
        if ([response isMasterPlaylist]) {
            strongSelf->_masterList = [[M3U8MasterPlaylist alloc] initWithContent:response baseURL:url];
            NSArray *levels = strongSelf->_masterList.xStreamList.bandwidthArray; // side effect: sorts by bandwidth
            NSArray *streamUrls = strongSelf->_masterList.allStreamURLs;
            strongSelf->_numLevels = (int)streamUrls.count;
            if (strongSelf->_currentLevel == -1) {
                strongSelf->_currentLevel = 0; //strongSelf->_numLevels - 1;
                [strongSelf.delegate downloader:strongSelf gotLevels:levels];
            }
            [strongSelf fetchPlaylist:streamUrls[strongSelf->_currentLevel] baseUrl:url];
        } else if ([response isMediaPlaylist]) {
            if ([response isEqualToString:strongSelf->_lastPlaylistResponse]) return;
            strongSelf->_lastPlaylistResponse = response;
            M3U8MediaPlaylist *mediaList = [[M3U8MediaPlaylist alloc] initWithContent:response type:M3U8MediaPlaylistTypeMedia baseURL:url];
            strongSelf->_mediaList = mediaList;
            
            NSArray<M3U8SegmentInfo*> *segments = [mediaList segmentsAtTimeFromEnd:strongSelf->_bufferTime];

            if (!segments.count) {
                [strongSelf.delegate downloader:strongSelf playlistError:[NSError errorWithDomain:@"HLSDownloader" code:0 userInfo:@{@"message": @"No segments in playlist"}]];
                return;
            }
            [strongSelf fetchAllSegments:segments];
        } else {
            [strongSelf.delegate downloader:strongSelf playlistError:[NSError errorWithDomain:@"HLSDownloader" code:0 userInfo:@{@"message": @"Playlist not found"}]];
            [strongSelf stop];
        }
    } failure:^(NSError *error) {
        if (!weakSelf) return;
        _networkBusy = NO;
        [weakSelf.delegate downloader:weakSelf playlistError:error];
    }];
}

- (void)maybeChangeLevels {
    [self setCurrentLevel:[self bestAvailableLevel]];
}

- (int)bestAvailableLevel {
    if (_masterList) {
        NSArray *levels = _masterList.xStreamList.bandwidthArray;
        double downloadBitrate = _bandwidthTracker.trailingAverageBitrate;
        for (int i = (int)levels.count - 1; i >= 0; i--) {
            NSNumber *levelBitrate = levels[i];
            if ([levelBitrate doubleValue] < downloadBitrate) {
                return i;
            }
        }
    }
    return 0; // return -1 as an error case?
}

- (void)fetchAllSegments:(NSArray<M3U8SegmentInfo*>*)segments {
    if (!segments.count) return;
    M3U8SegmentInfo *segment = segments.firstObject;
    NSArray *remaining = [segments subarrayWithRange:NSMakeRange(1, segments.count - 1)];
    id segmentId = segment.sequence ? @(segment.sequence) : segment.mediaURL;
    if ([_seenSegments containsObject:segmentId]) {
        [self fetchAllSegments:remaining];
        return;
    }
    [_seenSegments addObject:segmentId];
    double startTime = CACurrentMediaTime();
    __weak typeof(self)weakSelf = self;
    [[HLSNetworkManager sharedManager] getData:segment.mediaURL success:^(NSData *response) {
        if (!weakSelf) return;
        __strong typeof(weakSelf)strongSelf = weakSelf;
        [strongSelf->_bandwidthTracker addDatapoint:response.length time:(CACurrentMediaTime() - startTime)];
        if (_logLevel >= HLSLogLevelDebug)
            NSLog(@"After sequence %@: Avg bandwidth: %d  trailing: %d", segmentId, (int)strongSelf->_bandwidthTracker.averageBitrate, (int)strongSelf->_bandwidthTracker.trailingAverageBitrate);
        [strongSelf maybeChangeLevels];
        [weakSelf.delegate downloader:weakSelf gotSegment:response];
        [weakSelf fetchAllSegments:remaining];
        
    } failure:^(NSError *error) {
        [weakSelf.delegate downloader:weakSelf playlistError:error];
    }];
}

@end
