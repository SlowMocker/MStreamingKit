//
//  NSMutableArray+STKAudioPlayer.h
//  StreamingKit
//
//  Created by Thong Nguyen on 30/01/2014.
//  Copyright (c) 2014 Thong Nguyen. All rights reserved.
//

/*
 用 NSMutableArray 模拟 Queue
 Array 0-last 分别对应着 Queue 的入口和出口
 dequeue：对应着取出 Array 最后一个元素
 enqueue：对应着将元素添加到 Array 的 index 0
 skip：将元素直接插到 Queue 的出口处
 peek：即将出队列的元素
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMutableArray (STKAudioPlayer)
/// 入队列
- (void) enqueue:(id)obj;
/// 将 obj 在 self 中插队
- (void) skipQueue:(id)obj;
/// 将 queue 中的元素在 self 中进行插队
- (void) skipQueueWithQueue:(NSMutableArray*)queue;
/// 出队列
- (nullable id) dequeue;
/// 获取当前队列中即将出队列的元素
- (nullable id) peek;
@end

NS_ASSUME_NONNULL_END
