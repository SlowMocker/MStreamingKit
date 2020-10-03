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

/*
 
 数据读取入口
 
 */

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@class STKDataSource;

// stream 监听的回调接口
@protocol STKDataSourceDelegate<NSObject>
- (void) dataSourceDataAvailable:(STKDataSource*)dataSource;
- (void) dataSourceErrorOccured:(STKDataSource*)dataSource;
- (void) dataSourceEof:(STKDataSource*)dataSource;
- (void) dataSource:(STKDataSource*)dataSource didReadStreamMetadata:(NSDictionary*)metadata;
@end

@interface STKDataSource : NSObject

// data source 信息
@property (readonly) BOOL supportsSeek;
@property (readonly) SInt64 position;
@property (readonly) SInt64 length;
@property (readonly) BOOL hasBytesAvailable;
@property (nonatomic, readwrite, assign) double durationHint;
@property (readwrite, unsafe_unretained, nullable) id<STKDataSourceDelegate> delegate;
@property (nonatomic, strong, nullable) NSURL *recordToFileUrl;

/// 1. stream 设置 client 监听事件
/// 2. stream 和 eventRunLoop 关联（防止线程阻塞，保证监听事件的正常执行）
- (BOOL) registerForEvents:(NSRunLoop*)runLoop;
/// 1. stream 解绑 client
/// 2. stream 取消 eventRunLoop 关联
- (void) unregisterForEvents;

/// 关闭 stream 读取流
- (void) close;

- (void) seekToOffset:(SInt64)offset;

/// 读取 stream size 的数据到 buffer 【0：stream 已读到最后，-1：读取出错，size：实际填充的大小 size】
/// @param buffer 需要填充的 buffer
/// @param size 填充的最大大小
- (int) readIntoBuffer:(UInt8*)buffer withSize:(int)size;

/// 音频格式
- (AudioFileTypeID) audioFileTypeHint;

@end

NS_ASSUME_NONNULL_END
