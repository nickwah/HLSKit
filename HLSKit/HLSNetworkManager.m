//
//  HLSNetworkManager.m
//  HLSKit
//
//  Created by Nicholas White on 10/7/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import "HLSNetworkManager.h"

@implementation HLSNetworkManager {
    NSURLSession *_urlSession;
}

@synthesize baseUrl = _baseUrl;
@synthesize ignoreSSLErrors = _ignoreSSLErrors;
@synthesize timeout = _timeout;

static HLSNetworkManager*singleton;

+ (instancetype)sharedManager {
    if (!singleton) {
        singleton = [[HLSNetworkManager alloc] init];
    }
    return singleton;
}

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _urlSession = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:Nil];
        _timeout = 5.0;
    }
    return self;
}

- (void)getString:(NSString *)url success:(void (^)(NSString *))success failure:(void (^)(NSError *))failure {
    [self getData:url success:^(NSData *response) {
        NSString *stringData = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
        if (success) success(stringData);
    } failure:failure];
}
- (void)getData:(NSString *)url success:(void (^)(NSData *))success failure:(void (^)(NSError *))failure {
    NSURL* finalUrl = [NSURL URLWithString:url];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:finalUrl cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:_timeout];
    NSURLSessionDataTask *task = [_urlSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            if (failure) failure(error);
            return;
        }
        if (success) success(data);
    }];
    [task resume];
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    //NSLog(@"trust issues... %@", challenge.protectionSpace.host);
    if ([challenge.protectionSpace.authenticationMethod
        isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if (_ignoreSSLErrors) {
            NSURLCredential *credential =
            [NSURLCredential credentialForTrust:
             challenge.protectionSpace.serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential,credential);
        } else {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        }
    }
}

@end
