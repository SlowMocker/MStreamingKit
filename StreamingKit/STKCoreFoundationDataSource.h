/**********************************************************************************
 AudioPlayer.m
 
 Created by Thong Nguyen on 14/05/2012.
 https://github.com/tumtumtum/audjustable
 
 Copyright (c) 2012 Thong Nguyen (tumtumtum@gmail.com). All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 3. All advertising materials mentioning features or use of this software
 must display the following acknowledgement:
 This product includes software developed by Thong Nguyen (tumtumtum@gmail.com)
 4. Neither the name of Thong Nguyen nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY Thong Nguyen ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THONG NGUYEN BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********************************************************************************/

#import "STKDataSource.h"
#import "STKAFNetworking.h"

NS_ASSUME_NONNULL_BEGIN

@class STKCoreFoundationDataSource;

@interface CoreFoundationDataSourceClientInfo : NSObject
@property (readwrite) CFReadStreamRef readStreamRef;
@property (readwrite, retain) STKCoreFoundationDataSource* datasource;
@end

@interface STKCoreFoundationDataSource : STKDataSource
{
@public
    // 流读取指针
    CFReadStreamRef stream;
@protected
    BOOL isInErrorState;
    NSRunLoop* eventsRunLoop;
}

/// 数据 session
@property (nonatomic , strong) STKAFHTTPSessionManager * __nullable dataSession;
@property (atomic , strong) NSMutableData * __nullable dataM;

@property (readonly) BOOL isInErrorState;

/// 1. stream 设置 client 监听事件
/// 2. stream 和 eventRunLoop 关联（防止线程阻塞，保证监听事件的正常执行）
- (BOOL) reregisterForEvents;

/// 1. 创建 stream
/// 2. registerForEvents
- (void) open;
- (void) openCompleted;
- (void) dataAvailable;
- (void) eof;
- (void) errorOccured;
- (CFStreamStatus) status;

@end

NS_ASSUME_NONNULL_END
