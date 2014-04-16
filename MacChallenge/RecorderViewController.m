//
//  RecorderViewController.m
//  MacChallenge
//
//  Created by Frank Le Grand on 4/11/14.
//  Copyright (c) 2014 FrankLeGrand. All rights reserved.
//

#import "RecorderViewController.h"
#import "AVCaptureDeviceFormat_AVRecorderAdditions.h"

@interface RecorderViewController ()


// AVFoundation Capture Input

@property (strong, nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (strong, nonatomic) AVCaptureDeviceInput *audioDeviceInput;


// AVFoundation Capture Output

@property (strong, nonatomic) AVCaptureMovieFileOutput *movieFileOutput;
@property (strong, nonatomic) AVCaptureAudioPreviewOutput *audioPreviewOutput;


// AVFoundation Session

@property (strong, nonatomic) AVCaptureSession *captureSession;


// Misc

@property (strong, nonatomic) NSTimer *audioLevelsTimer;
@property (strong, nonatomic) NSArray *observers;

- (void)setupNotifications;

@end



@implementation RecorderViewController

@synthesize videoDevices;
@synthesize audioDevices;
@synthesize captureSession;

@synthesize observers;

#pragma mark - House Keeping

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.captureSession = [[AVCaptureSession alloc] init];
        
        [self setupOutputs];
        [self setupNotifications];
    }
    return self;
}

- (void)awakeFromNib
{
    [self.progressIndicator setHidden:YES];
    [self.captureView setWantsLayer:YES];
	CALayer *previewViewLayer = [self.captureView layer];
	[previewViewLayer setBackgroundColor:[NSColor darkGrayColor].CGColor];
    
    
	AVCaptureVideoPreviewLayer *newPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
	[newPreviewLayer setFrame:[previewViewLayer bounds]];
	[newPreviewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
	[previewViewLayer addSublayer:newPreviewLayer];

    
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!videoDevice && (self.videoDevices.count > 0))
        videoDevice = [self.videoDevices objectAtIndex:0];

    // Select a default device if any is found
    if (videoDevice)
    {
        [self setSelectedVideoDevice:videoDevice];
        [self setSelectedAudioDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio]];
    }
    else
    {
        [self setSelectedVideoDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeMuxed]];
    }

    [self refreshDevices];
    
    
    // Start the session
    // As per Apple (https://developer.apple.com/library/mac/documentation/AVFoundation/Reference/AVCaptureSession_Class/Reference/Reference.html#//apple_ref/occ/instm/AVCaptureSession/beginConfiguration):
    //
    // The startRunning method is a blocking call which can take some time, therefore
    // you should perform session setup on a serial queue so that the main queue isn't blocked
    //
    
    dispatch_queue_t toggleCaptureQueue = dispatch_queue_create("self.franklegrand.togglecapture.queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(toggleCaptureQueue, ^{
        [self.captureSession startRunning];
    });

	
	// Start updating the audio level meter
	self.audioLevelsTimer = [NSTimer scheduledTimerWithTimeInterval:0.1f
                                                             target:self
                                                           selector:@selector(updateAudioLevels:)
                                                           userInfo:nil
                                                            repeats:YES];
    
}

- (void)setupNotifications
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    id runtimeErrorObserver = [notificationCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification
                                                              object:captureSession
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                                                              dispatch_async(dispatch_get_main_queue(), ^(void) {
                                                                  [self presentError:[[note userInfo] objectForKey:AVCaptureSessionErrorKey]];
                                                              });
                                                          }];
    id didStartRunningObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStartRunningNotification
                                                                 object:captureSession
                                                                  queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(NSNotification *note) {
                                                                 NSLog(@"did start running");
                                                             }];
    id didStopRunningObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStopRunningNotification
                                                                object:captureSession
                                                                 queue:[NSOperationQueue mainQueue]
                                                            usingBlock:^(NSNotification *note) {
                                                                NSLog(@"did stop running");
                                                            }];
    id deviceWasConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *note) {
                                                                    [self refreshDevices];
                                                                }];
    id deviceWasDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification
                                                                       object:nil
                                                                        queue:[NSOperationQueue mainQueue]
                                                                   usingBlock:^(NSNotification *note) {
                                                                       [self refreshDevices];
                                                                   }];
    
    observers = [[NSArray alloc] initWithObjects:runtimeErrorObserver
                 , didStartRunningObserver
                 , didStopRunningObserver
                 , deviceWasConnectedObserver
                 , deviceWasDisconnectedObserver, nil];

}

- (void)setupOutputs
{
    // Attach outputs to session
    self.movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    [self.movieFileOutput setDelegate:self];
    [self.captureSession addOutput:self.movieFileOutput];
    
    self.audioPreviewOutput = [[AVCaptureAudioPreviewOutput alloc] init];
    [self.audioPreviewOutput setVolume:0.f];
    [self.captureSession addOutput:self.audioPreviewOutput];

}

- (void)cleanup
{
	// Invalidate the level meter timer here to avoid a retain cycle
    [self.audioLevelsTimer invalidate];
	
	// Stop the session
    dispatch_queue_t toggleCaptureQueue = dispatch_queue_create("self.franklegrand.togglecapture.queue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(toggleCaptureQueue, ^{
        [self.captureSession stopRunning];
    });

	
	// Set movie file output delegate to nil to avoid a dangling pointer
    [[self movieFileOutput] setDelegate:nil];
	
	// Remove Observers
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	for (id observer in observers)
		[notificationCenter removeObserver:observer];
}


#pragma mark - Device selection

- (void)refreshDevices
{
    // Reload our connected video and audio devices:
    //
    
	[self setVideoDevices:[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]
                           arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]]];
    
	[self setAudioDevices:[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]];
	
    
    // If a device that was selected is no longer there, un-select it
    //
    
	[self.captureSession beginConfiguration];
	
	if (![[self videoDevices] containsObject:[self selectedVideoDevice]])
		[self setSelectedVideoDevice:nil];
	
	if (![[self audioDevices] containsObject:[self selectedAudioDevice]])
		[self setSelectedAudioDevice:nil];
	
	[self.captureSession commitConfiguration];
}

- (AVCaptureDevice *)selectedVideoDevice
{
	return [self.videoDeviceInput device];
}

- (void)setSelectedVideoDevice:(AVCaptureDevice *)selectedVideoDevice
{
	[self.captureSession beginConfiguration];
	
	if ([self videoDeviceInput]) {
		// Remove the old device input from the session
		[self.captureSession removeInput:self.videoDeviceInput];
        self.videoDeviceInput = nil;
	}
	
	if (selectedVideoDevice) {
		NSError *error = nil;
		
		// Create a device input for the device and add it to the session
		AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedVideoDevice error:&error];
		if (newVideoDeviceInput == nil) {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		} else {
			if (![selectedVideoDevice supportsAVCaptureSessionPreset:[self.captureSession sessionPreset]])
				[self.captureSession setSessionPreset:AVCaptureSessionPresetHigh];
			
			[self.captureSession addInput:newVideoDeviceInput];
			[self setVideoDeviceInput:newVideoDeviceInput];
		}
	}
	
	// If this video device also provides audio, don't use another audio device
	if ([self selectedVideoDeviceProvidesAudio])
		[self setSelectedAudioDevice:nil];
	
	[self.captureSession commitConfiguration];
}

- (AVCaptureDevice *)selectedAudioDevice
{
	return [self.audioDeviceInput device];
}

- (void)setSelectedAudioDevice:(AVCaptureDevice *)selectedAudioDevice
{
	[self.captureSession beginConfiguration];
	
	if ([self audioDeviceInput]) {
		// Remove the old device input from the session
		[self.captureSession removeInput:[self audioDeviceInput]];
		[self setAudioDeviceInput:nil];
	}
	
	if (selectedAudioDevice && ![self selectedVideoDeviceProvidesAudio]) {
		NSError *error = nil;
		
		// Create a device input for the device and add it to the session
		AVCaptureDeviceInput *newAudioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedAudioDevice error:&error];
		if (newAudioDeviceInput == nil) {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		} else {
			if (![selectedAudioDevice supportsAVCaptureSessionPreset:[self.captureSession sessionPreset]])
				[self.captureSession setSessionPreset:AVCaptureSessionPresetHigh];
			
			[self.captureSession addInput:newAudioDeviceInput];
			[self setAudioDeviceInput:newAudioDeviceInput];
		}
	}
	
	[self.captureSession commitConfiguration];
}

- (BOOL)selectedVideoDeviceProvidesAudio
{
	return ([[self selectedVideoDevice] hasMediaType:AVMediaTypeMuxed] || [[self selectedVideoDevice] hasMediaType:AVMediaTypeAudio]);
}

#pragma mark - Recording

- (BOOL)isRecording
{
	return [self.movieFileOutput isRecording];
}

- (void)setRecording:(BOOL)flag
{
	if (flag)
    {
		// Record to a temporary file, which the user will relocate when recording is finished
        NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString] ;
        NSString *uniqueFileName = [NSString stringWithFormat:@"%@_%@", @"MacChallenge_", guid];
        NSString *tempName = [NSTemporaryDirectory() stringByAppendingPathComponent:uniqueFileName];
        tempName = [tempName stringByAppendingPathExtension:@"mov"];
        
        [self.movieFileOutput addObserver:self
                               forKeyPath:@"recording"
                                  options:NSKeyValueObservingOptionOld
                                  context:NULL];
        
		[self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:tempName]
                                          recordingDelegate:self];
	}
    else
    {
		[[self movieFileOutput] stopRecording];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ((object == self.movieFileOutput)
        && ([keyPath isEqualToString:@"recording"]))
    {
        if ([self isRecording])
        {
            self.stopWatchStartTime = [NSDate timeIntervalSinceReferenceDate];
        }
        [self updateStopWatchTime];
    }
}

- (void)updateStopWatchTime
{
    if (![self isRecording])
        return;
    
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = currentTime - self.stopWatchStartTime;
    
    NSInteger minutes = (NSInteger)(elapsed / 60);
    elapsed -= minutes *60;
    NSInteger seconds = elapsed;
    elapsed -= seconds;
    NSInteger milliSeconds = elapsed * 100.0;
    
    NSString *text = [NSString stringWithFormat:@"%.2ld:%.2ld:%.2ld", (long)minutes, (long)seconds, (long)milliSeconds];
    self.stopWatchTimeText = text;
    [self performSelector:@selector(updateStopWatchTime) withObject:self afterDelay:0.01];
}

#pragma mark - Recording Delegate methods

#pragma mark AVCaptureFileOutputRecordingDelegate Implementation

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
//	NSLog(@"Did start recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
//	NSLog(@"Did pause recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
//	NSLog(@"Did resume recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections dueToError:(NSError *)error
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self presentError:error];
	});
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)recordError
{
	if (recordError != nil && [[[recordError userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey] boolValue] == NO)
    {
		[[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self presentError:recordError];
		});
	}
    else
    {
		// Compose and move the video from its temporary location to the user-chosen location:
		NSSavePanel *savePanel = [NSSavePanel savePanel];
		[savePanel setAllowedFileTypes:[NSArray arrayWithObject:AVFileTypeQuickTimeMovie]];
		[savePanel setCanSelectHiddenExtension:YES];
        
		[savePanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result)
         {
             if (result == NSOKButton)
             {
                 [[NSFileManager defaultManager] removeItemAtURL:[savePanel URL] error:nil];
                 [self compose:outputFileURL andExport:[savePanel URL]];
                 
             }
             else
             {
                 [[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
             }
         }];
	}
}

#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate Implementation

// Not used here
//- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
//{
//    
//}

#pragma mark - Video Editing & Exporting

#define degreesToRadians(x) (M_PI * x / 180.0)

- (void)compose:(NSURL *)sourceURL andExport:(NSURL *)outputURL
{
    NSProgressIndicator *progressIndicator = [[NSProgressIndicator alloc] initWithFrame:self.progressIndicator.frame];
    [progressIndicator setIndeterminate:YES];
    [self.view addSubview:progressIndicator];
    [progressIndicator startAnimation:nil];
    
    AVURLAsset *videoAsset = [AVURLAsset assetWithURL:sourceURL];
    
    
    NSError* error = NULL;
    AVMutableComposition* mixComposition = [AVMutableComposition composition];
    
    
    AVAssetTrack *clipVideoTrack = nil;
    AVAssetTrack *audioTrack = nil;
    NSArray *videoTracks = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
    NSArray *audioTracks = [videoAsset tracksWithMediaType:AVMediaTypeAudio];
    
    if (videoTracks.count > 0)
    {
        clipVideoTrack = [videoTracks objectAtIndex:0];
        
        AVMutableCompositionTrack *compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                       preferredTrackID:kCMPersistentTrackID_Invalid];
        
        [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration)
                                       ofTrack:clipVideoTrack
                                        atTime:kCMTimeZero error:nil];
        
        [compositionVideoTrack setPreferredTransform:[clipVideoTrack preferredTransform]];
    }
    
    
    if (audioTracks.count > 0)
    {
        audioTrack = [audioTracks objectAtIndex:0];
        
        AVMutableCompositionTrack *compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                       preferredTrackID:kCMPersistentTrackID_Invalid];
        
        [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero,videoAsset.duration)
                                       ofTrack:audioTrack
                                        atTime:kCMTimeZero
                                         error:&error];
    }
    
    CGSize videoSize = [clipVideoTrack naturalSize];
    
    CATextLayer *captionLayer = [[CATextLayer alloc] init];
    [captionLayer setFont:@"Helvetica-Bold"];
    [captionLayer setFontSize:36];
    [captionLayer setFrame:CGRectMake(0, videoSize.height/8, videoSize.width, 100)];
    [captionLayer setString:self.captionTextField.stringValue];
    [captionLayer setAlignmentMode:kCAAlignmentCenter];
    [captionLayer setForegroundColor:[[NSColor whiteColor] CGColor]];
    
//    CALayer *sublayer = [CALayer layer];
//    sublayer.backgroundColor = [NSColor blueColor].CGColor;
//    sublayer.shadowOffset = CGSizeMake(0, 3);
//    sublayer.shadowRadius = 5.0;
//    sublayer.shadowColor = [NSColor blackColor].CGColor;
//    sublayer.shadowOpacity = 0.8;
//    sublayer.frame = CGRectMake(30, 30, 128, 192);
    
    CALayer *parentLayer = [CALayer layer];
    CALayer *videoLayer = [CALayer layer];
    parentLayer.frame = CGRectMake(0, 0, videoSize.width, videoSize.height);
    videoLayer.frame = CGRectMake(0, 0, videoSize.width, videoSize.height);
    [parentLayer addSublayer:videoLayer];
    [parentLayer addSublayer:captionLayer];
//    [parentLayer addSublayer:sublayer];
    
    AVMutableVideoComposition *videoComp = [AVMutableVideoComposition videoComposition];
    videoComp.renderSize = videoSize;
    videoComp.frameDuration = CMTimeMake(1, 30);
    videoComp.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer
                                                                                                                           inLayer:parentLayer];
    
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, [mixComposition duration]);
    
    AVMutableVideoCompositionLayerInstruction* layerInstruction =
    [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:clipVideoTrack];
    
    instruction.layerInstructions = [NSArray arrayWithObject:layerInstruction];
    videoComp.instructions = [NSArray arrayWithObject: instruction];
    
    AVAssetExportSession *assetExport = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPreset1280x720];
    assetExport.videoComposition = videoComp;
    assetExport.outputFileType = AVFileTypeQuickTimeMovie;
    assetExport.outputURL = outputURL;
    assetExport.shouldOptimizeForNetworkUse = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [assetExport exportAsynchronouslyWithCompletionHandler: ^(void )
         {
             [progressIndicator stopAnimation:nil];
             [progressIndicator removeFromSuperview];
             if (assetExport.status == AVAssetExportSessionStatusCompleted)
             {
                 NSLog(@"Export done; video exported at %@", outputURL);
                 dispatch_async(dispatch_get_main_queue(),^(void)
                                {
                                    [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:nil];
                                    [[NSWorkspace sharedWorkspace] openURL:outputURL];
                                });
             }
             else
             {
                 NSLog(@"Error: in %s expected to received status AVAssetExportSessionStatusCompleted, read %ld instead.", __PRETTY_FUNCTION__, (long)assetExport.status);
             }
         }];
    });
}

#pragma mark - AVCaptureFileOutputDelegate Implementation

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput
{
    return NO;
}

#pragma mark - Audio Input Level

- (void)updateAudioLevels:(NSTimer *)timer
{
	NSInteger channelCount = 0;
	float decibels = 0.f;
	
	// Sum all of the average power levels and divide by the number of channels
	for (AVCaptureConnection *connection in [[self movieFileOutput] connections]) {
		for (AVCaptureAudioChannel *audioChannel in [connection audioChannels]) {
			decibels += [audioChannel averagePowerLevel];
			channelCount += 1;
		}
	}
	
	decibels /= channelCount;
    CGFloat linear = (pow(10.f, 0.05f * decibels) * 40.0f);
//    NSLog(@"Decibels: %f - %f", decibels, linear);
	self.audioInputLevel = linear;
}

#pragma mark Multi Files

// Select & open multiple movie files to append them to each other and
// save the output into one file

- (IBAction)openFilesClicked:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
     
     [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            self.selectedFiles = [panel URLs];
            [self mergeVideosAndSave];
        }
        
    }];
}

- (void)mergeVideosAndSave
{
    AVMutableComposition* mixComposition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compositionVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                   preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *compositionAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                   preferredTrackID:kCMPersistentTrackID_Invalid];
    

    for (NSURL *aURL in self.selectedFiles)
    {
        AVURLAsset *videoAsset = [AVURLAsset assetWithURL:aURL];
        NSError* error = nil;
        CMTime runningDuration = mixComposition.duration;
        
        
        AVAssetTrack *clipVideoTrack = nil;
        AVAssetTrack *audioTrack = nil;
        NSArray *videoTracks = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
        NSArray *audioTracks = [videoAsset tracksWithMediaType:AVMediaTypeAudio];

        if (videoTracks.count > 0)
        {
            clipVideoTrack = [videoTracks objectAtIndex:0];
            
            
            [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration)
                                           ofTrack:clipVideoTrack
                                            atTime:runningDuration
                                             error:&error];
            if (error)
            {
                NSLog(@"ERROR: %@", error);
            }
        }
        
        
        if (audioTracks.count > 0)
        {
            audioTrack = [audioTracks objectAtIndex:0];
            
            [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero,videoAsset.duration)
                                           ofTrack:audioTrack
                                            atTime:runningDuration
                                             error:&error];
        }

    }

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    [savePanel setAllowedFileTypes:[NSArray arrayWithObject:AVFileTypeQuickTimeMovie]];
    [savePanel setCanSelectHiddenExtension:YES];
    
    [savePanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result)
     {
         if (result == NSOKButton)
         {
             [[NSFileManager defaultManager] removeItemAtURL:[savePanel URL] error:nil];
             NSURL *outputURL = [savePanel URL];
             
             AVAssetExportSession *assetExport = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPreset1280x720];
             assetExport.outputFileType = AVFileTypeQuickTimeMovie;
             assetExport.outputURL = outputURL;
             assetExport.shouldOptimizeForNetworkUse = YES;
             
             dispatch_async(dispatch_get_main_queue(), ^(void) {
                 [assetExport exportAsynchronouslyWithCompletionHandler: ^(void )
                  {
                      if (assetExport.status == AVAssetExportSessionStatusCompleted)
                      {
                          NSLog(@"Export done; video exported at %@", outputURL);
                          dispatch_async(dispatch_get_main_queue(),^(void)
                                         {
                                             [[NSWorkspace sharedWorkspace] openURL:outputURL];
                                         });
                      }
                      else
                      {
                          NSLog(@"Error: in %s expected to received status AVAssetExportSessionStatusCompleted, read %ld instead.", __PRETTY_FUNCTION__, (long)assetExport.status);
                      }
                  }];
             });
         }
         else
         {
         }
     }];

}

@end
