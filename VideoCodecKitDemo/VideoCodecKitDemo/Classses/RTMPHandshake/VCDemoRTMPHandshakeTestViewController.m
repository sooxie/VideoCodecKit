//
//  VCDemoRTMPHandshakeTestViewController.m
//  VideoCodecKitDemo
//
//  Created by CmST0us on 2019/2/15.
//  Copyright © 2019 eric3u. All rights reserved.
//

#import <VideoCodecKit/VideoCodecKit.h>
#import "VCDemoRTMPHandshakeTestViewController.h"

@interface VCDemoRTMPHandshakeTestViewController ()
@property (nonatomic, strong) VCTCPSocket *socket;
@property (nonatomic, strong) VCRTMPHandshake *handshake;
@property (nonatomic, strong) VCRTMPSession *session;
@property (nonatomic, strong) VCRTMPNetConnection *netConnection;
@property (nonatomic, strong) VCRTMPNetStream *netStream;
@end

@implementation VCDemoRTMPHandshakeTestViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.socket = [[VCTCPSocket alloc] initWithHost:@"127.0.0.1" port:1935];
    self.handshake = [VCRTMPHandshake handshakeForSocket:self.socket];
    __weak typeof(self) weakSelf = self;
    
    [self.handshake startHandshakeWithBlock:^(VCRTMPHandshake * _Nonnull handshake, VCRTMPSession * _Nullable session, BOOL isSuccess, NSError * _Nullable error) {
        if (isSuccess) {
            weakSelf.session = session;
            [weakSelf handleHandshakeSuccess];
        } else {
            NSLog(@"握手失败: %@", error);
        }
    }];
}

- (void)handleHandshakeSuccess {
    __weak typeof(self) weakSelf = self;
    self.netConnection = [self.session makeNetConnection];
    NSDictionary *parm = @{
        @"app": @"stream".asString,
        @"tcUrl": @"rtmp://127.0.0.1/stream".asString,
        @"flashVer": @"FMLE/3.0 (compatible; FMSc/1.0)".asString,
        @"swfUrl": NSNull.asNull,
        @"fpad": @(NO).asBool,
        @"audioCodecs": @(0x0400).asNumber,
        @"videoCodecs": @(0x0080).asNumber,
        @"objectEncodeing": @(0).asNumber,
    };
    [self.netConnection connecWithParam:parm completion:^(VCRTMPCommandMessageResponse * _Nullable response, BOOL isSuccess) {
        if (isSuccess) {
            VCRTMPNetConnectionCommandConnectResult *result = (VCRTMPNetConnectionCommandConnectResult *)response;
            NSLog(@"[RTMP][NetConnection] Success: %@, %@", result.information, result.properties);
            [weakSelf handleNetConnectionSuccess];
        }
    }];
}

- (void)handleNetConnectionSuccess {
    __weak typeof(self) weakSelf = self;
    [self.netConnection releaseStream:@"12345"];
    [self.netConnection createStream:@"12345" completion:^(VCRTMPCommandMessageResponse * _Nullable response, BOOL isSuccess) {
        if (isSuccess) {
            NSLog(@"[RTMP][NetConnection][CreateStream] Success");
            [weakSelf.session setChunkSize:4096];
            VCRTMPNetConnectionCommandCreateStreamResult *result = (VCRTMPNetConnectionCommandCreateStreamResult *)response;
            weakSelf.netStream = [weakSelf.netConnection makeNetStreamWithStreamName:@"12345" streamID:(uint32_t)result.streamID.unsignedIntegerValue];
            [weakSelf.netStream publishWithCompletion:^(VCRTMPCommandMessageResponse * _Nullable response, BOOL isSuccess) {
                [weakSelf.netStream setMetaData:@{
                    @"duration": @(0).asNumber,
                    @"fileSize": @(0).asNumber,
                    @"width": @(1280).asNumber,
                    @"height": @(720).asNumber,
                    @"videocodecid": @"avc1".asString,
                    @"videodatarate": @(2500).asNumber,
                    @"framerate": @(30).asNumber,
                    @"audiocodecid": @"mp4a".asString,
                    @"audiodatarate": @(160).asNumber,
                    @"audiosamplerate": @"44100".asString,
                    @"audiosamplesize": @(16).asNumber,
                    @"audiochannels": @(2).asNumber,
                    @"stereo": @(YES).asBool,
                    @"2.1": @(NO).asBool,
                    @"3.1": @(NO).asBool,
                    @"4.0": @(NO).asBool,
                    @"4.1": @(NO).asBool,
                    @"5.1": @(NO).asBool,
                    @"7.1": @(NO).asBool,
                    @"encoder": @"iOSVT::VideoCodecKit".asString,
                }];
            }];
        }
    }];
}
@end
