//
//  AppDelegate.h
//  MacChallenge
//
//  Created by Frank Le Grand on 4/11/14.
//  Copyright (c) 2014 FrankLeGrand. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "RecorderViewController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (weak, nonatomic) IBOutlet RecorderViewController *recorderController;

@end
