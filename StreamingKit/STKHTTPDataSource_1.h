//
//  STKNewHTTPDataSource.h
//  StreamingKit
//
//  Created by iSmicro on 2020/10/4.
//  Copyright © 2020 iSmicro. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "STKDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface STKHTTPDataSource : STKDataSource

@property (readonly) BOOL isInErrorState;

- (BOOL) reregisterForEvents;

- (void) open;
- (void) openCompleted;
- (void) dataAvailable;
- (void) eof;
- (void) errorOccured;

#pragma mark STKHTTPDataSource
@property (nonatomic, strong, readonly) NSURL* url;
@property (nonatomic, assign, readonly) UInt32 httpStatusCode;
@property (nonatomic, assign, readonly) BOOL dataDidCacheFinished;

- (instancetype) initWithURL:(NSURL*)url;

- (nullable NSRunLoop*) eventsRunLoop;
- (void) reconnect;

+ (AudioFileTypeID) audioFileTypeHintFromMimeType:(NSString*)fileExtension;
@end

NS_ASSUME_NONNULL_END
