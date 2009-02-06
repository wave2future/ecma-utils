#import <AudioToolbox/AudioToolbox.h>
#import "AudioPlayer.h"
#import "AudioSession.h"

@interface AudioPlayer ()

- (void)playbackData:(AudioQueueBufferRef)buffer;
- (void)notifyPropertyChange:(AudioQueuePropertyID)propertyID;
- (OSStatus)setupPlayback;

@end


static void playbackCallback (void *inUserData,
                              AudioQueueRef inAudioQueue,
                              AudioQueueBufferRef bufferReference) {
    AudioPlayer *player = (AudioPlayer *) inUserData;
    [player playbackData:bufferReference];
}

static void propertyListenerCallback (void *inUserData,
                                      AudioQueueRef queueObject,
                                      AudioQueuePropertyID propertyID) {
    AudioPlayer *player = (AudioPlayer *) inUserData;
    [player notifyPropertyChange:propertyID];
}


@implementation AudioPlayer

@synthesize delegate;
@synthesize state;

- (id)initWithSoundFile:(CFURLRef)file {
    if(self = [super initWithSoundFile:file]) {
        packetDescriptions = NULL;
        donePlayingFile = NO;
        delegate = nil;
        state = kAudioPlayerStateStopped;
        OSStatus status = [self setupPlayback];
        if(status != noErr) {
            NSLog(@"Failed to create Audio Player: %d", status);
            [self autorelease];
            self = nil;
        } else {
            NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
            [c addObserver:self selector:@selector(interrupt) name:kAudioSessionInterrupted object:nil];
            [c addObserver:self selector:@selector(playIfWasInterrupted) name:kAudioSessionActivated object:nil];
        }
    }
    return self;
}

- (void)dealloc {
    NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
    [c removeObserver:self];
    [self stop];
    [super dealloc];
}

- (void)interrupt {
    if (state == kAudioPlayerStatePlaying) {
        [self pause];
        interrupted = YES;
    }
}

- (void)playIfWasInterrupted {
    if (interrupted) {
        [self play];
        interrupted = NO;
    }
}

- (OSStatus)cleanUp {
    state = kAudioPlayerStateStopped;
    if(packetDescriptions) {
        free(packetDescriptions);
        packetDescriptions = NULL;
    }
    startingPacketNumber = 0;
    AudioQueueRemovePropertyListener (queue,
                                      kAudioQueueProperty_IsRunning,
                                      propertyListenerCallback,
                                      self);
    return [super cleanUp];
}

- (void)notifyPropertyChange:(AudioQueuePropertyID)propertyID {
    if(propertyID == kAudioQueueProperty_IsRunning) {
        if(self.isRunning) {
            state = kAudioPlayerStatePlaying;
            if([delegate respondsToSelector:@selector(playingStarted:)]) {
                [delegate playingStarted:self];
            }
        } else {
            state = kAudioPlayerStateStopped;
            if([delegate respondsToSelector:@selector(playingFinished:)]) {
                [delegate playingFinished:self];
            }
        }
    }
}

- (void)playbackData:(AudioQueueBufferRef)buffer {
    NSLog(@"Buffer received!");
    if(!donePlayingFile) {
        UInt32 numBytes;
        UInt32 numPackets = numPacketsToRead;
        OSStatus status;
        status = AudioFileReadPackets (audioFileID,
                                       NO,
                                       &numBytes,
                                       packetDescriptions,
                                       startingPacketNumber,
                                       &numPackets, 
                                       buffer->mAudioData);
        if(numPackets > 0) {
            buffer->mAudioDataByteSize = numBytes;
            status = AudioQueueEnqueueBuffer (queue,
                                              buffer,
                                              numPackets,
                                              packetDescriptions);
            if(status == noErr) {
                startingPacketNumber += numPackets;
            }
        } else {
            status = AudioQueueStop(queue, FALSE);
            donePlayingFile = YES;
        }
        if(status != noErr) {
            NSLog(@"Playback failed: %d", status);
        }
    }
}


#undef CHECK_STATUS
#define CHECK_STATUS if (status != noErr) { NSLog(@"__FILE__:__LINE__ failed with status: %d", status); [self cleanUp]; return status; }
- (OSStatus)setupPlayback {
    donePlayingFile = NO;
    OSStatus status;
    status = AudioFileOpenURL ((CFURLRef) soundFile,
                               kAudioFileReadPermission,
                               kAudioFileCAFType,
                               &audioFileID);
    CHECK_STATUS;

    UInt32 sizeOfASBD = sizeof (audioFormat);
    status = AudioFileGetProperty (audioFileID, 
                                   kAudioFilePropertyDataFormat,
                                   &sizeOfASBD,
                                   &audioFormat);
    CHECK_STATUS;

    SInt64 bufferByteSize = 0x10000;
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof (maxPacketSize);
		
    status = AudioFileGetProperty (audioFileID, 
                                   kAudioFilePropertyPacketSizeUpperBound,
                                   &propertySize,
                                   &maxPacketSize);
    CHECK_STATUS;

    numPacketsToRead = bufferByteSize/maxPacketSize;
    if(numPacketsToRead <= 0) {
        status = kAudioFormatUnsupportedDataFormatError;
    }
    CHECK_STATUS;
    
    packetDescriptions = (AudioStreamPacketDescription*)calloc(numPacketsToRead, sizeof(AudioStreamPacketDescription));
    if(!packetDescriptions) {
        status = kMemFullError;
    } 
    CHECK_STATUS;

    status = AudioQueueNewOutput (&audioFormat,
                                  playbackCallback,
                                  self, 
                                  CFRunLoopGetCurrent (),
                                  kCFRunLoopCommonModes,
                                  0,
                                  &queue);
    CHECK_STATUS;

    status = AudioQueueSetParameter (queue,
                                     kAudioQueueParam_Volume,
                                     1.0);

    CHECK_STATUS;

    OSStatus levelMeteringStatus = [self enableLevelMetering];
    if (levelMeteringStatus != noErr) {
        NSLog(@"Level metering is not supported: %d", levelMeteringStatus);
    }
    status = AudioQueueAddPropertyListener (queue,
                                            kAudioQueueProperty_IsRunning,
                                            propertyListenerCallback,
                                            self);
    CHECK_STATUS;

    int bufferIndex;
    for (bufferIndex = 0; bufferIndex < kNumberAudioDataBuffers; ++bufferIndex) {
        AudioQueueBufferRef buffer;
        status = AudioQueueAllocateBuffer (queue,
                                           bufferByteSize,
                                           &buffer);
        if(status != noErr) {
            break;
        } else {
            [self playbackData:buffer];
        }
    }
    CHECK_STATUS;
    
    [self writeMagicCookie];
    return status;
}

- (OSStatus) play {
    OSStatus status = AudioQueueStart(queue, NULL);
    if(status == noErr) {
        state = kAudioPlayerStatePlaying;
    }
    return status;
}

- (OSStatus) stop {
    donePlayingFile = YES;
    startingPacketNumber = 0;
    OSStatus status = AudioQueueStop(queue, TRUE);
    if(status == noErr) {
        state = kAudioPlayerStateStopped;
    }
    return status;
}


- (OSStatus) pause {
    OSStatus status = AudioQueuePause (queue);
    if(status == noErr) {
        state = kAudioPlayerStatePaused;
    }
    return status;
}

- (OSStatus) resume {
    OSStatus status = AudioQueueStart(queue, NULL);
    if(status == noErr) {
        state = kAudioPlayerStatePlaying;
    }
    return status;
}

- (long)currentTime {
    AudioTimeStamp stamp;
    stamp.mFlags = kAudioTimeStampSampleTimeValid;
    AudioQueueGetCurrentTime(queue, nil, &stamp, NULL);
    Float64 sampleTime = stamp.mSampleTime;
    return (long) sampleTime/audioFormat.mSampleRate;
}

@end
