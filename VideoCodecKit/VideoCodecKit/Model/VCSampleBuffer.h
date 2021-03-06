//
//  VCSampleBuffer.h
//  VideoCodecKit
//
//  Created by CmST0us on 2019/1/19.
//  Copyright © 2019 eric3u. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCSampleBuffer : NSObject
@property (nonatomic, assign) CMSampleBufferRef sampleBuffer;
@property (nonatomic, readonly) CMMediaType mediaType;
@property (nonatomic) CMBlockBufferRef dataBuffer;
@property (nonatomic, readonly) CVImageBufferRef imageBuffer;
@property (nonatomic, readonly) CMItemCount numberOfSamples;
@property (nonatomic, readonly) CMTime duration;
@property (nonatomic, readonly) CMFormatDescriptionRef formatDescription;
@property (nonatomic, readonly) CMTime decodeTimeStamp;
@property (nonatomic, readonly) CMTime presentationTimeStamp;
@property (nonatomic, readonly) BOOL keyFrame;
@property (nonatomic, readonly) AudioStreamBasicDescription audioStreamBasicDescription;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSampleBuffer:(CMSampleBufferRef)aSampleBuffer;
- (instancetype)initWithSampleBuffer:(CMSampleBufferRef)aSampleBuffer freeWhenDone:(BOOL)shouldFreeWhenDone NS_DESIGNATED_INITIALIZER;

- (nullable NSData *)h264ParameterSetData;
- (nullable NSData *)dataBufferData;

- (AVAudioBuffer *)audioBuffer;
- (AVAudioFormat *)audioFormat;
@end

NS_ASSUME_NONNULL_END
