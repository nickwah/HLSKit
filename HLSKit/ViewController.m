//
//  ViewController.m
//  HLSKit
//
//  Created by Nicholas White on 10/7/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import "ViewController.h"
#import "HLSDownloader.h"

@interface ViewController ()<HLSDownloaderDelegate>

@end

@implementation ViewController {
    HLSDownloader *_downloader;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _downloader = [[HLSDownloader alloc] initWithUrl:@"http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8" delegate:self];
    [_downloader play];
}

- (void)downloader:(HLSDownloader *)downloader gotLevels:(NSArray *)levels {
    NSLog(@"We have the following levels: %@", levels);
}

- (void)downloader:(HLSDownloader *)downloader gotSegment:(NSData *)mpegTsData {
    NSLog(@"Got mpeg ts segment with length %ld", mpegTsData.length);
}

- (void)downloader:(HLSDownloader *)downloader playlistError:(NSError *)error {
    NSLog(@"downloader error: %@", error);
}

- (void)downloaderStopped:(HLSDownloader *)downloader {
    NSLog(@"HLS downloading stopped");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
