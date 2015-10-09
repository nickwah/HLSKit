//
//  HLSDownloader.h
//  HLSKit
//
//  Created by Nicholas White on 10/7/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HLSDownloader;

@protocol HLSDownloaderDelegate <NSObject>

- (void)downloader:(HLSDownloader*)downloader playlistError:(NSError*)error;
- (void)downloader:(HLSDownloader*)downloader gotSegment:(NSData*)mpegTsData;

@optional
- (void)downloader:(HLSDownloader*)downloader gotLevels:(NSArray<NSNumber*>*)levels;
- (void)downloaderStopped:(HLSDownloader*)downloader;

@end

typedef enum : NSUInteger {
    HLSLogLevelError,
    HLSLogLevelInfo,
    HLSLogLevelDebug,
    HLSLogLevelVerbose,
} HLSLogLevel;

@interface HLSDownloader : NSObject

@property (weak, nonatomic) id<HLSDownloaderDelegate>delegate;
@property (nonatomic, strong, readonly) NSString* url;
@property (nonatomic) int numLevels;
@property (nonatomic) int currentLevel;
@property (nonatomic) HLSLogLevel logLevel;

// How often to refresh the m3u8 file containing video segments.
@property (nonatomic) NSTimeInterval refreshInterval; // Defaults to 0.5 seconds
// How many segments to download, expressed as a total duration.
@property (nonatomic) NSTimeInterval bufferTime; // Defaults to 4.0 seconds


- (instancetype)initWithUrl:(NSString*)url;
- (instancetype)initWithUrl:(NSString*)url delegate:(id<HLSDownloaderDelegate>)delegate;
- (void)play;

@end
