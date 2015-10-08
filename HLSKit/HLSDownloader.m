//
//  HLSDownloader.m
//  HLSKit
//
//  Created by Nicholas White on 10/7/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import "HLSDownloader.h"
#import "HLSNetworkManager.h"
#import "M3U8Kit.h"

@implementation HLSDownloader {
    NSString *_url;
    NSString *_baseUrl;
    NSTimer *_timer;
    M3U8MasterPlaylist *_masterList;
    M3U8MediaPlaylist *_mediaList;
    NSString *_lastPlaylistResponse;
    BOOL _networkBusy;
    NSMutableSet *_seenSegments;
}
@synthesize numLevels = _numLevels;
@synthesize currentLevel = _currentLevel;
@synthesize bufferTime = _bufferTime;

- (instancetype)initWithUrl:(NSString *)url {
    return [self initWithUrl:url delegate:nil];
}

- (instancetype)initWithUrl:(NSString *)url delegate:(id<HLSDownloaderDelegate>)delegate {
    if (self = [super init]) {
        _url = url;
        self.delegate = delegate;
        self.refreshInterval = 0.5;
        _currentLevel = -1;
        _bufferTime = 4.0;
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
        _mediaList = nil;
        _currentLevel = currentLevel;
    }
}

- (void)fetchPlaylist:(NSString*) url baseUrl:(NSString *)baseUrl {
    //NSLog(@"Fetch %@ with base url %@", url, baseUrl);
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
            NSArray *streamUrls = strongSelf->_masterList.allStreamURLs;
            strongSelf->_numLevels = (int)streamUrls.count;
            if (strongSelf->_currentLevel == -1) {
                strongSelf->_currentLevel = _numLevels - 1;
                [strongSelf.delegate downloader:strongSelf gotLevels:streamUrls];
            }
            [strongSelf fetchPlaylist:streamUrls[strongSelf->_currentLevel] baseUrl:url];
        } else if ([response isMediaPlaylist]) {
            if ([response isEqualToString:strongSelf->_lastPlaylistResponse]) return;
            strongSelf->_lastPlaylistResponse = response;
            M3U8MediaPlaylist *mediaList = [[M3U8MediaPlaylist alloc] initWithContent:response type:M3U8MediaPlaylistTypeMedia baseURL:url];
            strongSelf->_mediaList = mediaList;
            
            NSArray *segments = [mediaList segmentsAtTimeFromEnd:strongSelf->_bufferTime];

            if (!segments.count) {
                [strongSelf.delegate downloader:strongSelf playlistError:[NSError errorWithDomain:@"HLSDownloader" code:0 userInfo:@{@"message": @"No segments in playlist"}]];
                return;
            }
            [strongSelf fetchAllSegments:segments];
            for (NSString *segment in segments) {
                [strongSelf->_seenSegments addObject:segment];
            }
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

- (void)fetchAllSegments:(NSArray*)segments {
    if (!segments.count) return;
    NSString *segment = segments.firstObject;
    NSArray *remaining = [segments subarrayWithRange:NSMakeRange(1, segments.count - 1)];
    if ([_seenSegments containsObject:segment]) {
        [self fetchAllSegments:remaining];
        return;
    }
    __weak typeof(self)weakSelf = self;
    [[HLSNetworkManager sharedManager] getData:segment success:^(NSData *response) {
        if (!weakSelf) return;
        [weakSelf.delegate downloader:weakSelf gotSegment:response];
        [weakSelf fetchAllSegments:remaining];
    } failure:^(NSError *error) {
        [weakSelf.delegate downloader:weakSelf playlistError:error];
    }];
}

@end
