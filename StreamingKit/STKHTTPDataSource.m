//
//  STKNewHTTPDataSource.m
//  StreamingKit
//
//  Created by iSmicro on 2020/10/4.
//  Copyright © 2020 iSmicro. All rights reserved.
//

#import "STKHTTPDataSource.h"
#import "STKLocalFileDataSource.h"
#import "STKAFNetworking.h"

typedef void(^STKURLBlock)(NSURL* url);
typedef NSURL* _Nonnull (^STKURLProvider)(void);
typedef void(^STKAsyncURLProvider)(STKHTTPDataSource* dataSource, BOOL forSeek, STKURLBlock callback);


@interface STKHTTPDataSource ()

@property (nonatomic , strong) STKAFHTTPSessionManager * __nullable dataSession;
@property (nonatomic , strong) NSURLSessionDataTask * __nullable dataTask;
@property (atomic , strong) NSMutableData * __nullable dataM;

@property (assign) BOOL isInErrorState;
@property (nonatomic, strong) NSURL* url;
@property (nonatomic, assign) UInt32 httpStatusCode;
@property (nonatomic, assign) BOOL dataDidCacheFinished;

@property (nonatomic , strong) NSOperationQueue *inQueue;
@property (nonatomic , strong) NSOperationQueue *outQueue;
// open 方法私有化？
- (void) open;
@end

@implementation STKHTTPDataSource
{
    NSRunLoop *_eventsRunLoop;
    
    // 是否支持 seek
    BOOL supportsSeek;
    //
    SInt64 seekStart;
    // readIntoBuffer
    SInt64 relativePosition;
    // 文件长度
    SInt64 fileLength;
    // 无效
    int discontinuous;
    // num
    int requestSerialNumber;
    
    int prefixBytesRead;
    NSData* prefixBytes;
    
    NSMutableData* iceHeaderData;
    BOOL iceHeaderSearchComplete;
    BOOL iceHeaderAvailable;
    BOOL httpHeaderNotAvailable;

    NSMutableData *_metadataData;
    int _metadataOffset;
    int _metadataBytesRead;
    int _metadataStep;
    int _metadataLength;
    
    STKAsyncURLProvider asyncUrlProvider;
    // 请求返回 header
    NSDictionary* httpHeaders;
    AudioFileTypeID audioFileTypeHint;
    NSDictionary* requestHeaders;
        
    CGFloat _didReadLength;
    
    NSInteger _testCount;
}

- (void) dataAvailable {
    if (!self.dataSession) {
        [self printDebugInfo:@"out queue data avalid - data session nil"];
        return;
    }
    
//    if (_didReadLength >= self.length && self.length > 0) {
//        [self printDebugInfo:@"out queue data avalid - data over"];
//        return;
//    }
    
    if (self.httpStatusCode == 0) {
        if ([self parseHttpHeader]) {
            if ([self hasBytesAvailable]) {
                [self.delegate dataSourceDataAvailable:self];
            }
            
            return;
        }
        else {
            return;
        }
    }
    else {
        if ([self hasBytesAvailable]) {
            [self.delegate dataSourceDataAvailable:self];
        }
    }
}

- (void) eof {
    [self.delegate dataSourceEof:self];
}

- (void) errorOccured {
    self.isInErrorState = YES;
    
    [self.delegate dataSourceErrorOccured:self];
}

- (void) dealloc {
    NSLog(@"\n\nSTKHTTPDataSource dealloc!!!\n\n");
}

- (void) close {
    if (self.dataSession) {
        if (_eventsRunLoop) {
            [self unregisterForEvents];
        }
        [self.dataSession.session invalidateAndCancel];
        self.dataSession = nil;
    }
}

- (void) unregisterForEvents {
    if (self.dataSession) {
        // stream 取消 client 事件监听
        // stream 和 runloop 取消关联
    }
}

- (BOOL) reregisterForEvents {
    if (_eventsRunLoop && self.dataSession) {
        // stream 设置 client 做事件监听
        // stream 和 runloop 关联，防止线程阻塞，保证回调正常执行
        return YES;
    }
    
    return NO;
}

- (BOOL) registerForEvents:(NSRunLoop*)runLoop {

    _eventsRunLoop = runLoop;
    
    if (!self.dataSession) {
        // Will register when they open or seek
        return YES;
    }
 
    // stream 设置 client 做事件监听
    // stream 和 runloop 关联，防止线程阻塞，保证回调正常执行
    return YES;
}

- (BOOL) hasBytesAvailable {
    
    if (!self.dataSession || self.dataM.length <= 0) {
        return NO;
    }
    return YES;
}

- (void) openCompleted {
}


#pragma mark - STKHTTPDataSource
- (instancetype) initWithURL:(NSURL*)urlIn {
    self.url = urlIn;
    // 重新初始化 tsQueue
    self.inQueue = [[NSOperationQueue alloc]init];
    self.inQueue.maxConcurrentOperationCount = 1;
    self.outQueue = [[NSOperationQueue alloc]init];
    self.outQueue.maxConcurrentOperationCount = 1;
    _testCount = 0;
    return [self initWithURLProvider:^NSURL* { return urlIn; }];
}

- (instancetype) initWithURL:(NSURL *)urlIn httpRequestHeaders:(NSDictionary *)httpRequestHeaders {
    self = [self initWithURLProvider:^NSURL* { return urlIn; }];
    self->requestHeaders = httpRequestHeaders;
    return self;
}

- (instancetype) initWithURLProvider:(STKURLProvider)urlProviderIn {
    urlProviderIn = [urlProviderIn copy];
    return [self initWithAsyncURLProvider:^(STKHTTPDataSource* dataSource, BOOL forSeek, STKURLBlock block) {
        block(urlProviderIn());
    }];
}

- (instancetype) initWithAsyncURLProvider:(STKAsyncURLProvider)asyncUrlProviderIn {
    if (self = [super init]) {
        seekStart = 0;
        relativePosition = 0;
        fileLength = -1;
        
        self->asyncUrlProvider = [asyncUrlProviderIn copy];
        
        audioFileTypeHint = [STKLocalFileDataSource audioFileTypeHintFromFileExtension:self.url.pathExtension];
    }
    
    return self;
}

#pragma mark - private methods
- (int) readData:(int)size toBuffer:(UInt8*)buffer {
    int returnValue = (int)MIN(size, self.dataM.length);
    [self.dataM getBytes:buffer range:NSMakeRange(0, returnValue)];
    if (self.dataM.length <= size) {
        self.dataM = NSMutableData.new;
    }
    else {
        self.dataM = [[self.dataM subdataWithRange:NSMakeRange(size, self.dataM.length - size)] mutableCopy];
    }
//    _didReadLength += returnValue;
//    if ([self length] > 0 && _didReadLength >= [self length]) {
//
//        [self.inQueue cancelAllOperations];
//        [self.outQueue cancelAllOperations];
//
//        [self printDebugInfo:@"read data - did read over"];
//
//        self.dataDidCacheFinished = YES;
//        [self eof];
//    }
    [self printDebugInfo:@"read data"];
    return returnValue;
}

- (int) privateReadIntoBuffer:(UInt8*)buffer withSize:(int)size {
    if (size == 0) {
        return 0;
    }
    
    if (prefixBytes != nil) {
        int count = MIN(size, (int)prefixBytes.length - prefixBytesRead);
        
        [prefixBytes getBytes:buffer length:count];
        
        prefixBytesRead += count;
        
        if (prefixBytesRead >= prefixBytes.length) {
            prefixBytes = nil;
        }
        
        return count;
    }
    
    int read;
    
    // read ICY stream metadata
    // http://www.smackfu.com/stuff/programming/shoutcast.html
    //
    if (_metadataStep > 0) {
        // read audio stream before next metadata chunk
        if (_metadataOffset > 0) {
            read = [self readData:MIN(_metadataOffset, size) toBuffer:buffer];
            
            if(read > 0)
                _metadataOffset -= read;
        }
        // read metadata
        else {
            // first we need to read one byte with length
            if (_metadataLength == 0) {
                // read only 1 byte
                UInt8 metadataLengthByte;
                read = [self readData:1 toBuffer:&metadataLengthByte];
                
                if (read > 0) {
                    _metadataLength = metadataLengthByte * 16;
                    
                    // prepare
                    if(_metadataLength > 0) {
                        _metadataData       = [NSMutableData dataWithLength:_metadataLength];
                        _metadataBytesRead  = 0;
                    }
                    // reset
                    else {
                        _metadataOffset = _metadataStep;
                        _metadataData   = nil;
                        _metadataLength = 0;
                    }
                    
                    // return 0, because no audio bytes read
                    relativePosition += read;
                    read = 0;
                }
            }
            // read metadata bytes
            else {
                read = [self readData:(_metadataLength - _metadataBytesRead) toBuffer:(_metadataData.mutableBytes + _metadataBytesRead)];
                
                if (read > 0) {
                    _metadataBytesRead += read;
                    
                    // done reading, so process it
                    if (_metadataBytesRead == _metadataLength) {
                        if([self.delegate respondsToSelector:@selector(dataSource:didReadStreamMetadata:)])
                            [self.delegate dataSource:self didReadStreamMetadata:[self _processIcyMetadata:_metadataData]];
                        
                        // reset
                        _metadataData       = nil;
                        _metadataOffset     = _metadataStep;
                        _metadataLength     = 0;
                        _metadataBytesRead  = 0;
                    }

                    // return 0, because no audio bytes read
                    relativePosition += read;
                    read = 0;
                }
            }
        }
    }
    else {
        read = [self readData:size toBuffer:buffer];
    }
    
    if (read < 0)
        return read;
    
    relativePosition += read;
    
    return read;
}

- (AudioFileTypeID) audioFileTypeHint {
    return audioFileTypeHint;
}

+ (AudioFileTypeID) audioFileTypeHintFromMimeType:(NSString*)mimeType {
    static dispatch_once_t onceToken;
    static NSDictionary* fileTypesByMimeType;
    
    dispatch_once(&onceToken, ^
    {
        fileTypesByMimeType =
        @{
            @"audio/mp3": @(kAudioFileMP3Type),
            @"audio/mpg": @(kAudioFileMP3Type),
            @"audio/mpeg": @(kAudioFileMP3Type),
            @"audio/wav": @(kAudioFileWAVEType),
            @"audio/x-wav": @(kAudioFileWAVEType),
            @"audio/vnd.wav": @(kAudioFileWAVEType),
            @"audio/aifc": @(kAudioFileAIFCType),
            @"audio/aiff": @(kAudioFileAIFFType),
            @"audio/x-m4a": @(kAudioFileM4AType),
            @"audio/x-mp4": @(kAudioFileMPEG4Type),
            @"audio/aacp": @(kAudioFileAAC_ADTSType),
            @"audio/m4a": @(kAudioFileM4AType),
            @"audio/mp4": @(kAudioFileMPEG4Type),
            @"video/mp4": @(kAudioFileMPEG4Type),
            @"audio/caf": @(kAudioFileCAFType),
            @"audio/x-caf": @(kAudioFileCAFType),
            @"audio/aac": @(kAudioFileAAC_ADTSType),
            @"audio/aacp": @(kAudioFileAAC_ADTSType),
            @"audio/ac3": @(kAudioFileAC3Type),
            @"audio/3gp": @(kAudioFile3GPType),
            @"video/3gp": @(kAudioFile3GPType),
            @"audio/3gpp": @(kAudioFile3GPType),
            @"video/3gpp": @(kAudioFile3GPType),
            @"audio/3gp2": @(kAudioFile3GP2Type),
            @"video/3gp2": @(kAudioFile3GP2Type)
        };
    });
    
    NSNumber* number = [fileTypesByMimeType objectForKey:mimeType];
    
    if (number == nil) {
        return 0;
    }
    
    return (AudioFileTypeID)number.intValue;
}

- (NSDictionary*) parseIceHeader:(NSData*)headerData {
    NSMutableDictionary* retval = [[NSMutableDictionary alloc] init];
    NSCharacterSet* characterSet = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSString* fullString = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
    NSArray* strings = [fullString componentsSeparatedByCharactersInSet:characterSet];
    
    httpHeaders = [NSMutableDictionary dictionary];
    
    for (NSString* s in strings) {
        if (s.length == 0) {
            continue;
        }
        
        if ([s hasPrefix:@"ICY "]) {
            NSArray* parts = [s componentsSeparatedByString:@" "];
            
            if (parts.count >= 2) {
                self.httpStatusCode = [parts[1] intValue];
            }
            
            continue;
        }
        
        NSRange range = [s rangeOfString:@":"];
        
        if (range.location == NSNotFound) {
            continue;
        }
        
        NSString* key = [s substringWithRange: (NSRange){.location = 0, .length = range.location}];
        NSString* value = [s substringFromIndex:range.location + 1];
        
        [retval setValue:value forKey:key];
    }
    
    return retval;
}

- (BOOL) parseHttpHeader {
    if (!httpHeaderNotAvailable) {
        NSURLResponse *resp = self.dataTask.response;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
            httpHeaders = httpResp.allHeaderFields;
            if (httpHeaders.count == 0) {
                httpHeaderNotAvailable = YES;
            }
            else {
                self.httpStatusCode = (UInt32)httpResp.statusCode;
            }
        }
    }
    
    if (httpHeaderNotAvailable) {
        if (self->iceHeaderSearchComplete && !self->iceHeaderAvailable) {
            return YES;
        }
        
        if (!self->iceHeaderSearchComplete) {
            UInt8 byte;
            UInt8 terminal1[] = { '\n', '\n' };
            UInt8 terminal2[] = { '\r', '\n', '\r', '\n' };

            if (iceHeaderData == nil) {
                iceHeaderData = [NSMutableData dataWithCapacity:1024];
            }
            
            while (true) {
                if (![self hasBytesAvailable]) {
                    break;
                }
                
                int read = [super readIntoBuffer:&byte withSize:1];
                
                if (read <= 0) {
                    break;
                }
                
                [iceHeaderData appendBytes:&byte length:read];
                
                if (iceHeaderData.length >= sizeof(terminal1)) {
                    if (memcmp(&terminal1[0], [self->iceHeaderData bytes] + iceHeaderData.length - sizeof(terminal1), sizeof(terminal1)) == 0) {
                        self->iceHeaderAvailable = YES;
                        self->iceHeaderSearchComplete = YES;
                        
                        break;
                    }
                }
                
                if (iceHeaderData.length >= sizeof(terminal2)) {
                    if (memcmp(&terminal2[0], [self->iceHeaderData bytes] + iceHeaderData.length - sizeof(terminal2), sizeof(terminal2)) == 0) {
                        self->iceHeaderAvailable = YES;
                        self->iceHeaderSearchComplete = YES;
                        
                        break;
                    }
                }
                
                if (iceHeaderData.length >= 4) {
                    if (memcmp([self->iceHeaderData bytes], "ICY ", 4) != 0 && memcmp([self->iceHeaderData bytes], "HTTP", 4) != 0) {
                        self->iceHeaderAvailable = NO;
                        self->iceHeaderSearchComplete = YES;
                        prefixBytes = iceHeaderData;
                        
                        return YES;
                    }
                }
            }
            
            if (!self->iceHeaderSearchComplete) {
                return NO;
            }
        }

        httpHeaders = [self parseIceHeader:self->iceHeaderData];
        
        self->iceHeaderData = nil;
    }
    
    // check ICY headers
    if ([httpHeaders objectForKey:@"Icy-metaint"] != nil) {
        _metadataBytesRead  = 0;
        _metadataStep       = [[httpHeaders objectForKey:@"Icy-metaint"] intValue];
        _metadataOffset     = _metadataStep;
    }

    if (([httpHeaders objectForKey:@"Accept-Ranges"] ?: [httpHeaders objectForKey:@"accept-ranges"]) != nil) {
        self->supportsSeek = ![[httpHeaders objectForKey:@"Accept-Ranges"] isEqualToString:@"none"];
    }
    
    if (self.httpStatusCode == 200) {
        if (seekStart == 0) {
            id value = [httpHeaders objectForKey:@"Content-Length"] ?: [httpHeaders objectForKey:@"content-length"];
            
            fileLength = (SInt64)[value longLongValue];
        }
        
        NSString* contentType = [httpHeaders objectForKey:@"Content-Type"] ?: [httpHeaders objectForKey:@"content-type"] ;
        AudioFileTypeID typeIdFromMimeType = [STKHTTPDataSource audioFileTypeHintFromMimeType:contentType];
        
        if (typeIdFromMimeType != 0) {
            audioFileTypeHint = typeIdFromMimeType;
        }
    }
    else if (self.httpStatusCode == 206) {
        NSString* contentRange = [httpHeaders objectForKey:@"Content-Range"] ?: [httpHeaders objectForKey:@"content-range"];
        NSArray* components = [contentRange componentsSeparatedByString:@"/"];
        
        if (components.count == 2)
        {
            fileLength = [[components objectAtIndex:1] integerValue];
        }
    }
    else if (self.httpStatusCode == 416) {
        if (self.length >= 0) {
            seekStart = self.length;
        }
        
        [self eof];
        
        return NO;
    }
    else if (self.httpStatusCode >= 300) {
        [self errorOccured];
        
        return NO;
    }
    
    return YES;
}

- (SInt64) position {
    return seekStart + relativePosition;
}

- (SInt64) length {
    return fileLength >= 0 ? fileLength : 0;
}

- (void) reconnect {
//    if (_didReadLength >= self.length && self.length > 0) {
//        if (self.length >= 0) {
//            seekStart = self.length;
//        }
//        [self eof];
//        return;
//    }
    
    NSRunLoop* savedEventsRunLoop = _eventsRunLoop;
    [self close];
    _eventsRunLoop = savedEventsRunLoop;

    [self seekToOffset:self->supportsSeek ? self.position : 0];
}

- (void) seekToOffset:(SInt64)offset {
    
    NSRunLoop* savedEventsRunLoop = _eventsRunLoop;
    [self close];
    _eventsRunLoop = savedEventsRunLoop;
    
    NSAssert([NSRunLoop currentRunLoop] == _eventsRunLoop, @"Seek called on wrong thread");
    
    self.dataM = nil;
    NSLog(@"\n\ndata session should be nil: %s\n\n", self.dataSession == nil ? "true" : "false");
    relativePosition = 0;
    seekStart = offset;
//    _didReadLength = offset;
    
    self.isInErrorState = NO;
    
    if (!self->supportsSeek && offset != self->relativePosition) {
        return;
    }
    
    [self openForSeek:YES];
}

- (int) readIntoBuffer:(UInt8*)buffer withSize:(int)size {
    return [self privateReadIntoBuffer:buffer withSize:size];
}

#pragma mark - Custom buffer reading
- (void) open {
    return [self openForSeek:NO];
}

- (void) openForSeek:(BOOL)forSeek {
    NSLog(@"\n\n\n|*********|-> openForSeek: %d", forSeek);
    self.dataDidCacheFinished = NO;
    int localRequestSerialNumber;
    
    requestSerialNumber++;
    localRequestSerialNumber = requestSerialNumber;
    
    // 只有在使用 initWithAsyncURLProvider: 初始化时才有可能是 async
    asyncUrlProvider(self, forSeek, ^(NSURL* url) {
        
        // 如果初始化只保留 initWithURL:（实际 STK 也只使用了 initWithURL:） 实际是同步
        // 则下面 4 行代码均为冗余代码
        if (localRequestSerialNumber != self->requestSerialNumber) {
            return;
        }
        self.url = url;
        
        if (url == nil) {
            return;
        }
        
        self.dataM = NSMutableData.new;
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url];
        
        if (self->seekStart > 0 && self->supportsSeek) {
            [request addValue:[NSString stringWithFormat:@"bytes=%lld-", self->seekStart] forHTTPHeaderField:@"Range"];
            self->discontinuous = YES;
        }
        
//        // for test
//        [request addValue:@"bytes=3577927-" forHTTPHeaderField:@"Range"];
        
        for (NSString* key in self->requestHeaders) {
            NSString* value = [self->requestHeaders objectForKey:key];
            [request addValue:value forHTTPHeaderField:key];
        }
        
        [request addValue:@"*/*" forHTTPHeaderField:@"Accept"];
        [request addValue:@"1" forHTTPHeaderField:@"Icy-MetaData"];
        
        // request
        __weak typeof(self) weakSelf = self;
        self.dataSession  = [STKAFHTTPSessionManager manager];
        NSMutableSet *setM = [self.dataSession.responseSerializer.acceptableContentTypes mutableCopy];
        [setM addObject:@"audio/mpeg"];
        self.dataSession.responseSerializer.acceptableContentTypes = [setM copy];
        
        self.dataTask = [self.dataSession dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
            dispatch_queue_t q = dispatch_queue_create("com.mosi.treamingKit.STKHTTPDataSource.request.callback", DISPATCH_QUEUE_CONCURRENT);
            dispatch_async(q, ^{
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                     __strong typeof(weakSelf) self = weakSelf;
                    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                    if (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) {
                        NSLog(@"\n\n【SUCCESS】did end read data\n\n");
                    }
                    else {
                        [self parseHttpHeader];
                    }
                }
            });
            
        }];
        
        // 数据持续读取回调
        [self.dataSession setDataTaskDidReceiveDataBlock:^(NSURLSession * _Nonnull session, NSURLSessionDataTask * _Nonnull dataTask, NSData * _Nonnull data) {
            __strong typeof(weakSelf) self = weakSelf;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSOperation *inOp = [NSBlockOperation blockOperationWithBlock:^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self.dataM) {
                        self.dataM = NSMutableData.new;
                    }
                    [self.dataM appendData:data];
                    
                    [self dataAvailable];
                    
                    if (dataTask.countOfBytesReceived >= dataTask.countOfBytesExpectedToReceive) {
                        
                        [self.inQueue cancelAllOperations];
                        [self.outQueue cancelAllOperations];
                        
                        [self printDebugInfo:@"read data - did read over"];
                        
                        self.dataDidCacheFinished = YES;
                        [self eof];
                    }
                }];
                
                // outOp 执行明显比 inOp 慢，导致最后数据请求完了，有比较大的概率再次执行一次 outOp 导致错误
//                NSOperation *outOp = [NSBlockOperation blockOperationWithBlock:^{
//                    __strong typeof(weakSelf) self = weakSelf;
//                    [self printDebugInfo:@"start out queue data avalid"];
//                    [self dataAvailable];
//                }];
//                outOp.name = [NSString stringWithFormat:@"outOp_%ld", self->_testCount];
//
//                self->_testCount ++;
//
//                [outOp addDependency:inOp];
                
                [self.inQueue addOperation:inOp];
//                [self.outQueue addOperation:outOp];
            });
        }];

        // 如果以 URLSession 的方式请求数据，就没有必要将 stream 和 runloop 关联了
        // 这里需要将 URLSession 和 stream 的回调关联
        [self reregisterForEvents];
        
        self.httpStatusCode = 0;

        [self.dataTask resume];

        self.isInErrorState = NO;
        
    });
}

- (void) printDebugInfo:(NSString *)str {
//    NSLog(@"\n\n");
//    NSLog(@"======= %@ =======", str);
//    NSLog(@"didRead: %lf / %lld | thread: %@", _didReadLength, [self length], [NSThread currentThread]);
//    NSLog(@"\n\n");
}

- (NSRunLoop*) eventsRunLoop {
    return _eventsRunLoop;
}

- (NSString*) description {
    return [NSString stringWithFormat:@"HTTP data source with file length: %lld and position: %lld", self.length, self.position];
}

- (BOOL) supportsSeek {
    return self->supportsSeek;
}

#pragma mark - Private

- (NSDictionary*)_processIcyMetadata:(NSData*)data
{
    NSMutableDictionary *metadata       = [NSMutableDictionary new];
    NSString            *metadataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray             *pairs          = [metadataString componentsSeparatedByString:@";"];
    
    for(NSString *pair in pairs)
    {
        NSArray *components = [pair componentsSeparatedByString:@"="];
        if(components.count < 2)
            continue;
        
        NSString *key   = components[0];
        NSString *value = [pair substringWithRange:NSMakeRange(key.length + 2, pair.length - (key.length + 2) - 1)];
        
        [metadata setValue:value forKey:key];
    }
    
    return metadata;
}

@end
