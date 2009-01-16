#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

#define kNumberAudioDataBuffers	3

@class AudioRecorder, AudioPlayer;

@interface AudioQueueObject : NSObject {
@protected
	AudioFileID audioFileID;
	AudioQueueRef queue;
	AudioQueueLevelMeterState *levels;
	CFURLRef soundFile;
	
	SInt64 startingPacketNumber;
	AudioStreamBasicDescription audioFormat;
}

@property (readonly, nonatomic) BOOL isRunning;
@property (readwrite, nonatomic) Float32 volume;

- (id)initWithSoundFile:(CFURLRef)soundFile;
- (AudioQueueLevelMeterState*)audioLevels;
- (NSUInteger)channels;

- (OSStatus)cleanUp;
- (OSStatus)writeMagicCookie;
- (OSStatus) enableLevelMetering;

@end