//
//  VCRTMPChunkChannel.m
//  VideoCodecKit
//
//  Created by CmST0us on 2020/2/6.
//  Copyright © 2020 eric3u. All rights reserved.
//

#import "VCRTMPChunkChannel.h"
#import "VCTCPSocket.h"
#import "VCByteArray.h"
#import "VCRTMPChunk.h"
#import "VCRTMPMessage.h"

#define kVCRTMPChunkChannelDefaultChunkSize (128)

@interface VCRTMPChunkChannel () <VCTCPSocketDelegate>
@property (nonatomic, strong) VCTCPSocket *socket;

@property (nonatomic, strong) NSData *lastData;
/// 指的是未拆包的Chunk
@property (nonatomic, strong) VCRTMPChunk *lastSendChunk;
@property (nonatomic, strong) VCRTMPChunk *lastReadChunk;

@property (nonatomic, assign) NSUInteger totalRecvByte;
@property (nonatomic, assign) NSUInteger totalSendByte;
@end

@implementation VCRTMPChunkChannel

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastData = [NSData data];
        _localChunkSize = kVCRTMPChunkChannelDefaultChunkSize;
        _acknowlegmentWindowSize = 0;
        _totalRecvByte = 0;
        _totalSendByte = 0;
    }
    return self;
}

+ (instancetype)channelForSocket:(VCTCPSocket *)socket {
    VCRTMPChunkChannel *channel = [[VCRTMPChunkChannel alloc] init];
    channel.socket = socket;
    channel.socket.delegate = channel;
    return channel;
}

- (dispatch_block_t)makeByteArrayPositionRecoveryBlock:(VCByteArray *)arr {
    NSInteger position = arr.postion;
    return ^{
        arr.postion = position;
    };
}

- (void)handleRecvData:(NSData *)recvData {
    VCByteArray *array = [[VCByteArray alloc] initWithData:self.lastData];
    [array writeBytes:recvData];
    array.postion = 0;
    while ([array bytesAvailable]) {
        VCRTMPChunk *chunk = [[VCRTMPChunk alloc] init];
        dispatch_block_t recoveryBlock = [self makeByteArrayPositionRecoveryBlock:array];
        @try {
            /// Read Basic Chunk Header
            uint8_t firstByte = [array readUInt8];
            uint8_t format = (firstByte >> 6) & 0x03;
            uint32_t csid = firstByte & 0x3F;
            chunk.messageHeaderType = format;
            if (csid == 0) {
                uint8_t secondByte = [array readUInt8];
                
                csid = secondByte + 64;
                chunk.chunkStreamID = csid;
            } else if (csid == 0x3F) {
                uint8_t secondByte = [array readUInt8];
                uint8_t thirdByte = [array readUInt8];
                
                csid = (thirdByte * 256) + (secondByte + 64);
                chunk.chunkStreamID = csid;
            } else {
                chunk.chunkStreamID = csid;
            }
            
            /// Read Message Header
            if (chunk.messageHeaderType == VCRTMPChunkMessageHeaderType3) {
                if (self.lastReadChunk.message.messageLength > 0) {
                    chunk.chunkData = [array readBytes:self.lastReadChunk.message.messageLength];
                }
            } else {
                VCRTMPMessage *message = [[VCRTMPMessage alloc] init];
                chunk.message = message;
                do {
                    message.timestamp = [array readUInt24];
                    
                    if (chunk.messageHeaderType == VCRTMPChunkMessageHeaderType2) {
                        break;
                    }
                    
                    message.messageLength = [array readUInt24];
                    message.messageTypeID = [array readUInt8];
                    
                    if (chunk.messageHeaderType == VCRTMPChunkMessageHeaderType1) {
                        break;
                    }
                    message.messageStreamID = [array readUInt32Little];
                } while (0);
                
                NSInteger externTimestampSize = [chunk extendedTimestampSize];
                if (externTimestampSize > 0) {
                    message.timestamp = [array readUInt32];
                }
                
                if (message.messageLength > 0) {
                    chunk.chunkData = [array readBytes:message.messageLength];
                }
            }
        } @catch (NSException *exception) {
            recoveryBlock();
            NSData *restData = [array readBytes:[array bytesAvailable]];
            self.lastData = restData;
            break;
        }
        
        self.lastReadChunk = chunk;
        if (self.delegate &&
            [self.delegate respondsToSelector:@selector(channel:didReceiveFrame:)]) {
            [self.delegate channel:self didReceiveFrame:chunk];
        }
    }
}

- (void)writeFrame:(VCRTMPChunk *)chunk {
    NSMutableData *sendData = [[NSMutableData alloc] init];
    __block VCRTMPChunk *lastChunk = chunk;
    [[self splitChunk:chunk] enumerateObjectsUsingBlock:^(VCRTMPChunk * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [sendData appendData:[obj makeChunk]];
        lastChunk = obj;
    }];
    
    /// 判断 Ack Window Size
    if (self.acknowlegmentWindowSize > 0) {
        /// 判断是否需要ACK重置
        if (self.totalSendByte > self.acknowlegmentWindowSize) {
            return;
        }
        /// TODO: 确认带宽
        if (self.totalSendByte > self.bandwidth) {
            return;
        }
        self.totalSendByte += sendData.length;
    }
    
    [self.socket writeData:sendData];
    self.lastSendChunk = chunk;
}

- (void)resetRecvByteCount {
    self.totalRecvByte = 0;
}

- (void)resetSendByteCount {
    self.totalSendByte = 0;
}

#pragma mark - Split Chunk
- (NSArray<VCRTMPChunk *> *)splitChunk:(VCRTMPChunk *)chunk {
    NSInteger chunkSize = self.localChunkSize;
    NSInteger chunkDataSize = chunk.message.messageLength;
    NSInteger splitChunkCount = chunkDataSize / chunkSize;
    NSInteger lastSplitChunkDataSize = chunkDataSize % chunkSize;
    NSInteger totalSplitChunkCount = splitChunkCount;
    if (lastSplitChunkDataSize > 0) {
        totalSplitChunkCount += 1;
    }
    
    /// 1. 参考上一个发送的Chunk
    [self modifyChunkMessageType:chunk withLastSendChunk:self.lastSendChunk];
    
    /// 2. 分割数据
    if (splitChunkCount == 0) {
        return @[chunk];
    }
    
    /// 3. 第一个拆分包，包含完整messageLength长度
    NSMutableArray<VCRTMPChunk *> *chunks = [[NSMutableArray alloc] init];
    VCByteArray *array = [[VCByteArray alloc] initWithData:chunk.chunkData];
    VCRTMPChunk *firstChunk = [[VCRTMPChunk alloc] initWithType:chunk.messageHeaderType
                                                  chunkStreamID:chunk.chunkStreamID
                                                        message:[chunk.message copy]];
    firstChunk.chunkData = [array readBytes:chunkSize];
    firstChunk.message.messageLength = (uint32_t)chunkDataSize;
    [chunks addObject:firstChunk];
    totalSplitChunkCount -= 1;
    if (totalSplitChunkCount == 0) {
        return chunks;
    }
    
    /// 4. 拆分chunk定长数据包
    for (NSInteger i = totalSplitChunkCount; i > 1; --i) {
        NSData *splitData = [array readBytes:chunkSize];
        VCRTMPChunk *splitChunk = [[VCRTMPChunk alloc] initWithType:VCRTMPChunkMessageHeaderType3
                                                      chunkStreamID:chunk.chunkStreamID
                                                            message:[chunk.message copy]];
        splitChunk.chunkData = splitData;
        [chunks addObject:splitChunk];
    }
    
    /// 5. 补充剩余数据数据包
    if (totalSplitChunkCount == 1) {
        NSData *splitData = [array readBytes:lastSplitChunkDataSize];
        VCRTMPChunk *splitChunk = [[VCRTMPChunk alloc] initWithType:VCRTMPChunkMessageHeaderType3
                                                      chunkStreamID:chunk.chunkStreamID
                                                            message:[chunk.message copy]];
        splitChunk.chunkData = splitData;
        [chunks addObject:splitChunk];
        totalSplitChunkCount -= 1;
    }
    
    return chunks;
}

- (void)modifyChunkMessageType:(VCRTMPChunk *)aChunk withLastSendChunk:(VCRTMPChunk *)lastSendChunk {
    VCRTMPChunkMessageHeaderType newMessageType = aChunk.messageHeaderType;
    uint32_t newTimestamp = aChunk.message.timestamp;
    if (lastSendChunk &&
        lastSendChunk.message.messageStreamID == aChunk.message.messageStreamID) {
        newMessageType = VCRTMPChunkMessageHeaderType1;
        newTimestamp = aChunk.message.timestamp - lastSendChunk.message.timestamp;
        if (lastSendChunk.message.messageLength == aChunk.message.messageLength &&
            lastSendChunk.message.messageTypeID == aChunk.message.messageTypeID) {
            newMessageType = VCRTMPChunkMessageHeaderType2;
            if (lastSendChunk.message.timestamp == aChunk.message.timestamp) {
                newMessageType = VCRTMPChunkMessageHeaderType3;
            }
        }
    }
    aChunk.messageHeaderType = newMessageType;
    aChunk.message.timestamp = newTimestamp;
}

#pragma mark - #pragma mark - TCP Delegate
- (void)tcpSocketEndcountered:(VCTCPSocket *)socket {
    if (self.delegate &&
        [self.delegate respondsToSelector:@selector(channelConnectionDidEnd)]) {
        [self.delegate channelConnectionDidEnd];
    }
}

- (void)tcpSocketErrorOccurred:(VCTCPSocket *)socket stream:(nonnull NSStream *)stream{
    if (self.delegate &&
        [self.delegate respondsToSelector:@selector(channel:connectionHasError:)]) {
        [self.delegate channel:self connectionHasError:stream.streamError];
    }
}

- (void)tcpSocketConnectTimeout:(VCTCPSocket *)socket {
    /// Pass
}

- (void)tcpSocketDidConnected:(nonnull VCTCPSocket *)socket {
    /// Pass
}

- (void)tcpSocketHasByteAvailable:(VCTCPSocket *)socket {
    NSData *recvData = [socket readData];
    if (recvData &&
        recvData.length > 0) {
        [self handleRecvData:recvData];
        
        self.totalRecvByte += recvData.length;
        if (self.acknowlegmentWindowSize > 0 &&
            self.totalRecvByte >= self.acknowlegmentWindowSize) {
            if (self.delegate &&
                [self.delegate respondsToSelector:@selector(channelNeedAck:)]) {
                [self.delegate channelNeedAck:self];
            }
            [self resetRecvByteCount];
        }
    } else {
        if (self.delegate &&
            [self.delegate respondsToSelector:@selector(channelConnectionDidEnd)]) {
            [self.delegate channelConnectionDidEnd];
        }
        [self.socket close];
    }
}

@end
