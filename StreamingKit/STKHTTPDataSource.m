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

#import "STKHTTPDataSource.h"
#import "STKLocalFileDataSource.h"
#import "Downloader.h"

@interface STKHTTPDataSource()
{
@private
    BOOL supportsSeek;
    UInt32 httpStatusCode;
    SInt64 seekStart;
    SInt64 relativePosition;
    SInt64 fileLength;
    int discontinuous;
	int requestSerialNumber;
    int prefixBytesRead;
    NSData* prefixBytes;
    NSMutableData* iceHeaderData;
    BOOL iceHeaderSearchComplete;
    BOOL iceHeaderAvailable;
    BOOL httpHeaderNotAvailable;

    NSMutableData *_metadataData;
    int            _metadataOffset;
    int            _metadataBytesRead;
    int            _metadataStep;
    int            _metadataLength;
    
    NSURL* currentUrl;
    STKAsyncURLProvider asyncUrlProvider;
    NSDictionary* httpHeaders;
    AudioFileTypeID audioFileTypeHint;
    NSDictionary* requestHeaders;
}
-(void) open;

@end

@implementation STKHTTPDataSource

- (instancetype) initWithURL:(NSURL*)urlIn {
    currentUrl = urlIn;
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
        
        audioFileTypeHint = [STKLocalFileDataSource audioFileTypeHintFromFileExtension:self->currentUrl.pathExtension];
    }
    
    return self;
}

- (void) dealloc {
    NSLog(@"STKHTTPDataSource dealloc");
}

- (NSURL*) url {
    return self->currentUrl;
}

+ (AudioFileTypeID) audioFileTypeHintFromMimeType:(NSString*)mimeType {
    static dispatch_once_t onceToken;
    static NSDictionary* fileTypesByMimeType;
    
    dispatch_once(&onceToken, ^ {
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
    
    if (!number) {
        return 0;
    }
    
    return (AudioFileTypeID)number.intValue;
}

- (AudioFileTypeID) audioFileTypeHint {
    return audioFileTypeHint;
}

//- (NSDictionary*) parseIceHeader:(NSData*)headerData {
//    NSMutableDictionary* retval = [[NSMutableDictionary alloc] init];
//    NSCharacterSet* characterSet = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
//    NSString* fullString = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding];
//    NSArray* strings = [fullString componentsSeparatedByCharactersInSet:characterSet];
//    
//    httpHeaders = [NSMutableDictionary dictionary];
//    
//    for (NSString* s in strings) {
//        if (s.length == 0) {
//            continue;
//        }
//        
//        if ([s hasPrefix:@"ICY "]) {
//            NSArray* parts = [s componentsSeparatedByString:@" "];
//            
//            if (parts.count >= 2)
//            {
//                self->httpStatusCode = [parts[1] intValue];
//            }
//            
//            continue;
//        }
//        
//        NSRange range = [s rangeOfString:@":"];
//        
//        if (range.location == NSNotFound) {
//            continue;
//        }
//        
//        NSString* key = [s substringWithRange: (NSRange){.location = 0, .length = range.location}];
//        NSString* value = [s substringFromIndex:range.location + 1];
//        
//        [retval setValue:value forKey:key];
//    }
//    
//    return retval;
//}
//
//- (BOOL) parseHttpHeader {
//    // http response 解析
//    if (!httpHeaderNotAvailable) {
//        CFTypeRef response = CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
//        
//        if (response) {
//            httpHeaders = (__bridge_transfer NSDictionary*)CFHTTPMessageCopyAllHeaderFields((CFHTTPMessageRef)response);
//            
//            if (httpHeaders.count == 0) {
//                httpHeaderNotAvailable = YES;
//            }
//            else {
//                self->httpStatusCode = (UInt32)CFHTTPMessageGetResponseStatusCode((CFHTTPMessageRef)response);
//            }
//
//            CFRelease(response);
//        }
//    }
//    
//    if (httpHeaderNotAvailable) {
//        if (self->iceHeaderSearchComplete && !self->iceHeaderAvailable) {
//            return YES;
//        }
//        
//        if (!self->iceHeaderSearchComplete) {
//            UInt8 byte;
//            UInt8 terminal1[] = { '\n', '\n' };
//            UInt8 terminal2[] = { '\r', '\n', '\r', '\n' };
//
//            if (iceHeaderData == nil) {
//                iceHeaderData = [NSMutableData dataWithCapacity:1024];
//            }
//            
//            while (true) {
//                if (![self hasBytesAvailable]) {
//                    break;
//                }
//                
//                int read = [super readIntoBuffer:&byte withSize:1];
//                
//                if (read <= 0) {
//                    break;
//                }
//                
//                [iceHeaderData appendBytes:&byte length:read];
//                
//                if (iceHeaderData.length >= sizeof(terminal1)) {
//                    if (memcmp(&terminal1[0], [self->iceHeaderData bytes] + iceHeaderData.length - sizeof(terminal1), sizeof(terminal1)) == 0) {
//                        self->iceHeaderAvailable = YES;
//                        self->iceHeaderSearchComplete = YES;
//                        
//                        break;
//                    }
//                }
//                
//                if (iceHeaderData.length >= sizeof(terminal2)) {
//                    if (memcmp(&terminal2[0], [self->iceHeaderData bytes] + iceHeaderData.length - sizeof(terminal2), sizeof(terminal2)) == 0) {
//                        self->iceHeaderAvailable = YES;
//                        self->iceHeaderSearchComplete = YES;
//                        
//                        break;
//                    }
//                }
//                
//                if (iceHeaderData.length >= 4) {
//                    if (memcmp([self->iceHeaderData bytes], "ICY ", 4) != 0 && memcmp([self->iceHeaderData bytes], "HTTP", 4) != 0) {
//                        self->iceHeaderAvailable = NO;
//                        self->iceHeaderSearchComplete = YES;
//                        prefixBytes = iceHeaderData;
//                        
//                        return YES;
//                    }
//                }
//            }
//            
//            if (!self->iceHeaderSearchComplete) {
//                return NO;
//            }
//        }
//
//        httpHeaders = [self parseIceHeader:self->iceHeaderData];
//        
//        self->iceHeaderData = nil;
//    }
//    
//    // check ICY headers
//    if ([httpHeaders objectForKey:@"Icy-metaint"] != nil) {
//        _metadataBytesRead  = 0;
//        _metadataStep       = [[httpHeaders objectForKey:@"Icy-metaint"] intValue];
//        _metadataOffset     = _metadataStep;
//    }
//
//    if (([httpHeaders objectForKey:@"Accept-Ranges"] ?: [httpHeaders objectForKey:@"accept-ranges"]) != nil) {
//        self->supportsSeek = ![[httpHeaders objectForKey:@"Accept-Ranges"] isEqualToString:@"none"];
//    }
//    
//    if (self.httpStatusCode == 200) {
//        if (seekStart == 0) {
//            id value = [httpHeaders objectForKey:@"Content-Length"] ?: [httpHeaders objectForKey:@"content-length"];
//            
//            fileLength = (SInt64)[value longLongValue];
//        }
//        
//        NSString* contentType = [httpHeaders objectForKey:@"Content-Type"] ?: [httpHeaders objectForKey:@"content-type"] ;
//        AudioFileTypeID typeIdFromMimeType = [STKHTTPDataSource audioFileTypeHintFromMimeType:contentType];
//        
//        if (typeIdFromMimeType != 0) {
//            audioFileTypeHint = typeIdFromMimeType;
//        }
//    }
//    else if (self.httpStatusCode == 206) {
//        NSString* contentRange = [httpHeaders objectForKey:@"Content-Range"] ?: [httpHeaders objectForKey:@"content-range"];
//        NSArray* components = [contentRange componentsSeparatedByString:@"/"];
//        
//        if (components.count == 2) {
//            fileLength = [[components objectAtIndex:1] integerValue];
//        }
//    }
//    else if (self.httpStatusCode == 416) {
//        if (self.length >= 0) {
//            seekStart = self.length;
//        }
//        
//        [self eof];
//        
//        return NO;
//    }
//    else if (self.httpStatusCode >= 300) {
//        [self errorOccured];
//        
//        return NO;
//    }
//    
//    return YES;
//}

//- (void) dataAvailable {
//    if (stream == NULL) {
//        return;
//    }
//
//	if (self.httpStatusCode == 0) {
//        if ([self parseHttpHeader]) {
//            if ([self hasBytesAvailable]) {
//                [super dataAvailable];
//            }
//
//            return;
//        }
//        else {
//            return;
//        }
//	}
//    else {
//        [super dataAvailable];
//    }
//}

- (SInt64) position {
    return seekStart + relativePosition;
}

- (SInt64) length {
    return fileLength >= 0 ? fileLength : 0;
}

- (void) reconnect {
    NSRunLoop* savedEventsRunLoop = eventsRunLoop;
    
    [self close];
    
    eventsRunLoop = savedEventsRunLoop;
	
    [self seekToOffset:self->supportsSeek ? self.position : 0];
}

- (void) seekToOffset:(SInt64)offset {
    NSRunLoop* savedEventsRunLoop = eventsRunLoop;
    
    [self close];
    
    eventsRunLoop = savedEventsRunLoop;
	
    NSAssert([NSRunLoop currentRunLoop] == eventsRunLoop, @"Seek called on wrong thread");
    
    stream = 0;
    relativePosition = 0;
    seekStart = offset;
    
    self->isInErrorState = NO;
    
    if (!self->supportsSeek && offset != self->relativePosition) {
        return;
    }
    
    [self openForSeek:YES];
}

- (int) readIntoBuffer:(UInt8*)buffer withSize:(int)size {
    int returnValue = (int)MIN(size, self.dataM.length);
    [self.dataM getBytes:buffer range:NSMakeRange(0, MIN(size, self.dataM.length))];
    if (self.dataM.length < size) {
        self.dataM = NSMutableData.new;
    }
    else {
        self.dataM = [[self.dataM subdataWithRange:NSMakeRange(size, self.dataM.length - size)] mutableCopy];
    }
    return returnValue;
}

- (void) open {
    return [self openForSeek:NO];
}

- (void) openForSeek:(BOOL)forSeek {
	int localRequestSerialNumber;
	
	requestSerialNumber++;
	localRequestSerialNumber = requestSerialNumber;
	
    asyncUrlProvider(self, forSeek, ^(NSURL* url) {
		if (localRequestSerialNumber != self->requestSerialNumber) {
			return;
		}
	
        self->currentUrl = url;

        if (url == nil) {
            return;
        }
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self->currentUrl];
        
        if (self->seekStart > 0 && self->supportsSeek) {
            [request addValue:[NSString stringWithFormat:@"bytes=%lld-", self->seekStart] forHTTPHeaderField:@"Range"];
            self->discontinuous = YES;
        }
        
        for (NSString* key in self->requestHeaders) {
            NSString* value = [self->requestHeaders objectForKey:key];
            [request addValue:value forHTTPHeaderField:key];
        }
        
        [request addValue:@"*/*" forHTTPHeaderField:@"Accept"];
        [request addValue:@"1" forHTTPHeaderField:@"Icy-MetaData"];
        
        __weak typeof(self) weakSelf = self;
        self.dataSession  = [AFHTTPSessionManager manager];
        NSURLSessionDataTask *dataTask = [self.dataSession dataTaskWithRequest:request uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
            
            // 请求结束
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                if (httpResponse.statusCode == 200) {
                    NSLog(@"\n\n【SUCCESS】did end read data\n\n");
                    __strong typeof(weakSelf) self = weakSelf;
                    [self eof];
                }
                else {
                    NSLog(@"\n\n【ERROR】did end read data: %@\n\n", error);
                    [self errorOccured];
                }
            }
        }];
        // 数据持续读取回调
        [self.dataSession setDataTaskDidReceiveDataBlock:^(NSURLSession * _Nonnull session, NSURLSessionDataTask * _Nonnull dataTask, NSData * _Nonnull data) {
            
            NSLog(@"did read leaf data: %ld",(long)data.length);
            __strong typeof(weakSelf) self = weakSelf;
            if (!self.dataM) {
                self.dataM = NSMutableData.new;
            }
            [self.dataM appendData:data];
            [super dataAvailable];
            // read data
        }];
        
        self->httpStatusCode = 0;
        self->isInErrorState = NO;
        // 开始请求
        [dataTask resume];
    });
}

- (UInt32) httpStatusCode {
    return self->httpStatusCode;
}

- (NSRunLoop*) eventsRunLoop {
    return self->eventsRunLoop;
}

- (NSString*) description {
    return [NSString stringWithFormat:@"HTTP data source with file length: %lld and position: %lld", self.length, self.position];
}

- (BOOL) supportsSeek {
    return self->supportsSeek;
}

#pragma mark - Private

- (NSDictionary*) _processIcyMetadata:(NSData*)data {
    NSMutableDictionary *metadata       = [NSMutableDictionary new];
    NSString            *metadataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray             *pairs          = [metadataString componentsSeparatedByString:@";"];
    
    for (NSString *pair in pairs) {
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
