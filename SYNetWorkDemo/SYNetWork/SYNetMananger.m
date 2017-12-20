//
//  SYHttpNetMananger.m
//  SYNetDome
//
//  Created by ksw on 2017/9/14.
//  Copyright © 2017年 ksw. All rights reserved.
//

#import "SYNetMananger.h"
#import "SYNetLocalCache.h"
#import "AFNetworking.h"


extern NSString *SYConvertMD5FromParameter(NSString *url, NSString* method, NSDictionary* paramDict);

static NSString *SYNetProcessingQueue = @"com.eoc.SunyNet";

NS_ASSUME_NONNULL_BEGIN

@interface SYNetMananger (){
    dispatch_queue_t _SYNetQueue;
}

@property (nonatomic, strong)SYNetLocalCache *cache;
@property (nonatomic, strong) NSMutableArray *batchGroups;//批处理
@property (nonatomic, strong)dispatch_queue_t SYNetQueue;
@end

@implementation SYNetMananger


- (instancetype)init
{
    self = [super init];
    if (self) {
        _SYNetQueue = dispatch_queue_create([SYNetProcessingQueue UTF8String], DISPATCH_QUEUE_CONCURRENT);
        _cache      = [SYNetLocalCache sharedInstance];
        _batchGroups = [NSMutableArray new];
    }
    return self;
}

+ (instancetype)sharedInstance
{
    static SYNetMananger *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    return instance;
}

- (void)syGetCacheWithUrl:(NSString*)urlString
               parameters:(NSDictionary * _Nullable)parameters
        completionHandler:(SYRequestCompletionHandler)completionHandler{
    
        [self syGetWithURLString:urlString parameters:parameters ignoreCache:NO cacheDuration:NetCacheDuration completionHandler:completionHandler];
}


- (void)syPostCacheWithUrl:(NSString*)urlString
                parameters:(NSDictionary * _Nullable)parameters
         completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    [self syPostWithURLString:urlString parameters:parameters ignoreCache:NO cacheDuration:NetCacheDuration completionHandler:completionHandler];
}


- (void)syPostNoCacheWithUrl:(NSString*)urlString
                  parameters:(NSDictionary * _Nullable)parameters
           completionHandler:(SYRequestCompletionHandler)completionHandler{
        
     [self syPostWithURLString:urlString parameters:parameters ignoreCache:YES cacheDuration:0 completionHandler:completionHandler];

}

- (void)syGetNoCacheWithUrl:(NSString*)urlString
                 parameters:(NSDictionary * _Nullable)parameters
          completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    [self syGetWithURLString:urlString parameters:parameters ignoreCache:YES cacheDuration:0 completionHandler:completionHandler];
}


- (void)syPostWithURLString:(NSString *)URLString
               parameters:(NSDictionary * _Nullable)parameters
              ignoreCache:(BOOL)ignoreCache
            cacheDuration:(NSTimeInterval)cacheDuration
        completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(_SYNetQueue, ^{
        
        [weakSelf taskWithMethod:@"POST" urlString:URLString parameters:parameters ignoreCache:ignoreCache cacheDuration:cacheDuration completionHandler:completionHandler];
    });
    
}

- (void)syGetWithURLString:(NSString *)URLString
              parameters:(NSDictionary *)parameters
             ignoreCache:(BOOL)ignoreCache
           cacheDuration:(NSTimeInterval)cacheDuration
       completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(_SYNetQueue, ^{
        
        [weakSelf taskWithMethod:@"GET" urlString:URLString parameters:parameters ignoreCache:ignoreCache cacheDuration:cacheDuration completionHandler:completionHandler];
    });
}


- (void)taskWithMethod:(NSString*)method
                          urlString:(NSString*)urlStr
                         parameters:(NSDictionary *)parameters
                        ignoreCache:(BOOL)ignoreCache
                      cacheDuration:(NSTimeInterval)cacheDuration
                  completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    
    
    NSString *fileKeyFromUrl = SYConvertMD5FromParameter(urlStr, method, parameters);
    __weak typeof(self) weakSelf = self;
    
    if (!ignoreCache && [self.cache checkIfShouldSkipCacheWithCacheDuration:cacheDuration cacheKey:fileKeyFromUrl]) {
        
        NSMutableDictionary *localCache = [NSMutableDictionary dictionary];
        NSDictionary *cacheDict = [self.cache searchCacheWithUrl:fileKeyFromUrl];
        [localCache setDictionary:cacheDict];
        if (cacheDict) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if (weakSelf.exceptionBlock) {
                    weakSelf.exceptionBlock(nil, localCache);
                }
                completionHandler(nil, YES, localCache);
            });
            return;
        }
    }
    
    SYRequestCompletionHandler newCompletionBlock = ^( NSError* error,  BOOL isCache, NSDictionary* result){
       
        result = [NSMutableDictionary dictionaryWithDictionary:result];
        if (cacheDuration > 0) {
            if (result) {
                if (weakSelf.cacheConditionBlock) {
                    if (weakSelf.cacheConditionBlock(result)) {
                        [weakSelf.cache saveCacheData:result forKey:fileKeyFromUrl];
                    }
                }else{
                    [weakSelf.cache saveCacheData:result forKey:fileKeyFromUrl];
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (weakSelf.exceptionBlock) {
                weakSelf.exceptionBlock(error, (NSMutableDictionary*)result);
            }
            completionHandler(error, NO, result);
        });
        
    };
    
    
    NSURLSessionTask *task = nil;
    if ([method isEqualToString:@"GET"]) {
        
        task = [self.afHttpManager  GET:urlStr parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            
            newCompletionBlock(nil,NO, responseObject);
            
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            
            newCompletionBlock(error,NO, nil);;
        }];
        
    }else{
        
        task = [self.afHttpManager POST:urlStr parameters:parameters progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            
            newCompletionBlock(nil,NO, responseObject);
            
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            
            newCompletionBlock(error,NO, nil);
        }];
        
    }
    
    [task resume];
}

- (AFHTTPSessionManager*)afHttpManager{
    
    AFHTTPSessionManager *afManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    return afManager;
}

- (SYNetRequestInfo*)syNetRequestWithURLStr:(NSString *)URLString
                                     method:(NSString*)method
                                 parameters:(NSDictionary *)parameters
                                ignoreCache:(BOOL)ignoreCache
                              cacheDuration:(NSTimeInterval)cacheDuration
                          completionHandler:(SYRequestCompletionHandler)completionHandler{
    
    SYNetRequestInfo *syNetRequestInfo = [SYNetRequestInfo new];
    syNetRequestInfo.urlStr = URLString;
    syNetRequestInfo.method = method;
    syNetRequestInfo.parameters = parameters;
    syNetRequestInfo.ignoreCache = ignoreCache;
    syNetRequestInfo.cacheDuration = cacheDuration;
    syNetRequestInfo.completionBlock = completionHandler;
    return syNetRequestInfo;
}

- (void)syBatchOfRequestOperations:(NSArray<SYNetRequestInfo *> *)tasks
                   progressBlock:(void (^)(NSUInteger numberOfFinishedTasks, NSUInteger totalNumberOfTasks))progressBlock
                 completionBlock:(netSuccessbatchBlock)completionBlock{
    
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(_SYNetQueue, ^{
        
        __block dispatch_group_t group = dispatch_group_create();
        [weakSelf.batchGroups addObject:group];

        __block NSInteger finishedTasksCount = 0;
        __block NSInteger totalNumberOfTasks = tasks.count;
        
        [tasks enumerateObjectsUsingBlock:^(SYNetRequestInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if (obj) {
                
                dispatch_group_enter(group);
                
                SYRequestCompletionHandler newCompletionBlock = ^( NSError* error,  BOOL isCache, NSDictionary* result){
                    
                    progressBlock(finishedTasksCount, totalNumberOfTasks);
                    if (obj.completionBlock) {
                        obj.completionBlock(error, isCache, result);
                    }
                    dispatch_group_leave(group);
                    
                };
                if ([obj.method isEqual:@"POST"]) {
                    
                    [[SYNetMananger sharedInstance] syPostWithURLString:obj.urlStr parameters:obj.parameters ignoreCache:obj.ignoreCache cacheDuration:obj.cacheDuration completionHandler:newCompletionBlock];
                    
                }else{
                    
                    [[SYNetMananger sharedInstance] syGetWithURLString:obj.urlStr parameters:obj.parameters ignoreCache:obj.ignoreCache cacheDuration:obj.cacheDuration completionHandler:newCompletionBlock];
                }
                
            }
            
        }];
        
        
        //监听
        NSLog(@"wait:::%@", [NSThread currentThread]);
        
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [weakSelf.batchGroups removeObject:group];
            if (completionBlock) {
                completionBlock(tasks);
            }
        });
    });
}

@end

NS_ASSUME_NONNULL_END
