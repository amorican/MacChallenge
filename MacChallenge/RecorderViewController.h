//
//  RecorderViewController.h
//  MacChallenge
//
//  Created by Frank Le Grand on 4/11/14.
//  Copyright (c) 2014 FrankLeGrand. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>

@interface RecorderViewController : NSViewController <NSWindowDelegate, AVCaptureFileOutputDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (weak, nonatomic) IBOutlet NSPopUpButton *videoDevicesPopupButton;
@property (weak, nonatomic) IBOutlet NSPopUpButton *audioDevicesPopupButton;
@property (weak, nonatomic) IBOutlet NSTextField *captionTextField;
@property (weak, nonatomic) IBOutlet NSView *captureView;
@property (weak, nonatomic) IBOutlet NSProgressIndicator *progressIndicator;

@property (strong, nonatomic) NSArray *videoDevices;
@property (strong, nonatomic) NSArray *audioDevices;
@property (assign, nonatomic) AVCaptureDevice *selectedVideoDevice;
@property (assign, nonatomic) AVCaptureDevice *selectedAudioDevice;

@property (strong, nonatomic) AVCaptureSession *captureSession;

@property (assign, getter = isRecording) BOOL recording;
@property (readwrite) NSTimeInterval stopWatchStartTime;
@property (strong, nonatomic) NSString *stopWatchTimeText;
@property (readwrite) CGFloat audioInputLevel;

- (void)cleanup;

@end
