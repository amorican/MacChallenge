//
//  AppDelegate.m
//  MacChallenge
//
//  Created by Frank Le Grand on 4/11/14.
//  Copyright (c) 2014 FrankLeGrand. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

#pragma mark - Application Delegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{

}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    return YES;
}

#pragma mark - Window Delegate

- (void)windowWillClose:(NSNotification *)notification
{
    [self.recorderController cleanup];
}

@end
