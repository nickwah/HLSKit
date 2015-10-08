//
//  HLSNetworkManager.h
//  HLSKit
//
//  Created by Nicholas White on 10/7/15.
//  Copyright © 2015 Nicholas White. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HLSNetworkManager : NSObject<NSURLSessionDelegate>

@property (nonatomic, strong) NSString* baseUrl;
@property (nonatomic) BOOL ignoreSSLErrors;
@property (nonatomic) NSTimeInterval timeout;

+ (instancetype)sharedManager;

- (void)getData:(NSString*)url success:(void(^)(NSData* response))success failure:(void(^)(NSError* error))failure;
- (void)getString:(NSString*)url success:(void(^)(NSString* response))success failure:(void(^)(NSError* error))failure;
- (void)post:(NSString*)url params:(NSDictionary*)params success:(void(^)(NSString* response))success failure:(void(^)(NSError* error))failure;

@end
