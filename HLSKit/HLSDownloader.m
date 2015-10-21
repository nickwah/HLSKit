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
    NSMutableArray<M3U8SegmentInfo*>*_downloadQueue;
    HLSBandwidthTracker *_bandwidthTracker;
    NSTimer *_downloadTimer;
    NSTimeInterval _downloadInterval;
    BOOL _downloading;
}
@synthesize numLevels = _numLevels;
@synthesize currentLevel = _currentLevel;
@synthesize bufferTime = _bufferTime;
@synthesize logLevel = _logLevel;
@synthesize maxSegmentQueue = _maxSegmentQueue;

- (instancetype)initWithUrl:(NSString *)url {
    return [self initWithUrl:url delegate:nil];
}

- (instancetype)initWithUrl:(NSString *)url delegate:(id<HLSDownloaderDelegate>)delegate {
    if (self = [super init]) {
        _url = url;
        self.delegate = delegate;
        self.refreshInterval = 0.5;
        _downloadInterval = self.refreshInterval / 2.0;
        _currentLevel = -1;
        _bufferTime = 2.0;
        _seenSegments = [NSMutableSet set];
        _bandwidthTracker = [[HLSBandwidthTracker alloc] init];
        _downloadQueue = [NSMutableArray array];
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
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_networkBusy = NO;
        [strongSelf.delegate downloader:strongSelf playlistError:error];
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

- (void)downloadSegments {
    M3U8SegmentInfo *segment;
    @synchronized(_downloadQueue) {
        if (_maxSegmentQueue > 0) {
            while (_downloadQueue.count > _maxSegmentQueue) {
                [_downloadQueue removeObjectAtIndex:0];
            }
        }
        //NSLog(@"downloadSegments; queue length %d", _downloadQueue.count);
        if (_downloadQueue.count == 0) {
            [_downloadTimer invalidate];
            _downloadTimer = nil;
            return;
        }
        if (_downloading) return; // We wait for the previous call to finish
        segment = _downloadQueue.firstObject;
        [_downloadQueue removeObjectAtIndex:0]; // We essentially want a popFirst or "shift" operation
    }
    id segmentId = segment.sequence ? @(segment.sequence) : segment.mediaURL;
    if ([_seenSegments containsObject:segmentId]) {
        // We got a duplicate segment?
        [self downloadSegments];
        return;
    }
    [_seenSegments addObject:segmentId];
    double startTime = CACurrentMediaTime();
    _downloading = YES;
    __weak typeof(self)weakSelf = self;
    [[HLSNetworkManager sharedManager] getData:segment.mediaURL success:^(NSData *response) {
        if (!weakSelf) return;
        __strong typeof(weakSelf)strongSelf = weakSelf;
        BOOL downloadMore = NO;
        @synchronized(strongSelf->_downloadQueue) {
            strongSelf->_downloading = NO;
            NSTimeInterval timeElapsed = (CACurrentMediaTime() - startTime);
            [strongSelf->_bandwidthTracker addDatapoint:response.length time:timeElapsed];
            if (strongSelf->_logLevel >= HLSLogLevelDebug)
                NSLog(@"After sequence %@: Avg bandwidth: %d  trailing: %d", segmentId, (int)strongSelf->_bandwidthTracker.averageBitrate, (int)strongSelf->_bandwidthTracker.trailingAverageBitrate);
            [strongSelf maybeChangeLevels];
            if (strongSelf->_downloadQueue.count > 0 && timeElapsed < strongSelf->_downloadInterval) {
                // If there are more segments queued up, just plow ahead
                downloadMore = YES;
            }
        }
        if (downloadMore) [strongSelf downloadSegments];
        [weakSelf.delegate downloader:weakSelf gotSegment:response];
    } failure:^(NSError *error) {
        if (!weakSelf) return;
        __strong typeof(weakSelf)strongSelf = weakSelf;
        strongSelf->_downloading = NO;
        [weakSelf.delegate downloader:weakSelf playlistError:error];
    }];
}

- (void)fetchAllSegments:(NSArray<M3U8SegmentInfo*>*)segments {
    if (!segments.count) return;
    [_downloadQueue addObjectsFromArray:segments];
    if (!_downloadTimer) {
        if (_downloadQueue.count > 1) {
            dispatch_async(dispatch_get_main_queue(), ^{
                _downloadTimer = [NSTimer scheduledTimerWithTimeInterval:_downloadInterval target:self selector:@selector(downloadSegments) userInfo:nil repeats:YES];
            });
        }
        [self downloadSegments];
    }
}

@end
