//
//  IPMAppDelegate.m
//  TVSwitcher
//
//  Copyright (c) 2014 Ian McCullough. All rights reserved.
//

#import "IPMAppDelegate.h"
#import "IPMTVSwitcherCommandOperation.h"
#import "NSString+VisEncode.h"
#import "NSDate+TimeAgo.h"
#import <objc/runtime.h>
#import <vis.h>

NSString* const kInputListKey = @"Inputs";
NSString* const kOutputListKey = @"Outputs";
NSString* const kStatusItemTitle = @"Title";
NSString* const kPollTime = @"PollTime";

@interface NSMenuItem (CmdToSend)

@property (nonatomic, readwrite, copy) NSString* cmdToSend;

@end

@interface IPMAppDelegate () <NSMenuDelegate>
@end

@implementation IPMAppDelegate
{
    NSOperationQueue* mOpQueue;
    NSMenuItem* mAgoMenuItem;
    NSDate* mLastUpdate;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    mOpQueue = [[NSOperationQueue alloc] init];
    mOpQueue.maxConcurrentOperationCount = 1;
    
    [[NSUserDefaults standardUserDefaults] registerDefaults: @{ kStatusItemTitle : @"📺",
                                                                kOutputListKey : @[ @"Upstairs", @"Downstairs" ],
                                                                kInputListKey : @[ @"TiVo", @"AppleTV", @"BluRay", @"XBOX360" ],
                                                                kPollTime : @(30.0),
                                                                }];
    
    const NSUInteger numInputs = [[[NSUserDefaults standardUserDefaults] arrayForKey: kInputListKey] count];
    
    NSStatusItem* si = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem = si;
    si.highlightMode = YES;
    si.title = [[NSUserDefaults standardUserDefaults] stringForKey: kStatusItemTitle];
    
    NSMenu* menu = [[NSMenu alloc] initWithTitle: @""];
    
    mAgoMenuItem = [[NSMenuItem alloc] initWithTitle: @"Status: Pending..." action:NULL keyEquivalent: @""];
    [mAgoMenuItem setEnabled: NO];
    [menu addItem: mAgoMenuItem];
    [menu addItem: [NSMenuItem separatorItem]];
    
    for (NSString* output in [[NSUserDefaults standardUserDefaults] arrayForKey: kOutputListKey])
    {
        NSMenu* outputMenu = [[NSMenu alloc] initWithTitle: output];
        for (NSString* input in [[NSUserDefaults standardUserDefaults] arrayForKey: kInputListKey])
        {
            NSMenuItem* inputItem = [[NSMenuItem alloc] initWithTitle: input action: @selector(selectInput:) keyEquivalent: @""];
            inputItem.tag = outputMenu.itemArray.count + 1;
            inputItem.cmdToSend = [NSString stringWithFormat: @"%lu\r\n", (unsigned long)numInputs * (menu.itemArray.count - 2) + inputItem.tag];
            [outputMenu addItem: inputItem];
        }
        
        NSMenuItem* outputItem = [[NSMenuItem alloc] initWithTitle: output action: nil keyEquivalent: @""];
        outputItem.submenu = outputMenu;
        outputItem.tag = menu.itemArray.count;
        [menu addItem: outputItem];
    }
    
    si.menu = menu;
    menu.delegate = self;
    
    // Get our first readout...
    [self querySwitcher: nil];
}

- (void)selectInput: (id)sender
{
    NSMenuItem* item = sender;
    if (item.cmdToSend)
    {
        IPMTVSwitcherCommandOperation* op = [[IPMTVSwitcherCommandOperation alloc] initWithCommand: item.cmdToSend timeout: 2.0 callback:^(BOOL success, NSString *response, NSError *error) {
            if (success)
                [self p_processResponse: response];
            
            [self querySwitcher: nil];
        }];
        
        [mOpQueue cancelAllOperations];

        [mOpQueue addOperation: op];
        
        // Optimistically set the menu state...
        for (NSMenuItem* mi in item.menu.itemArray)
        {
            mi.state = (mi == item) ? NSOnState : NSOffState;
        }

        mAgoMenuItem.title = @"Status: Pending...";
        mLastUpdate = nil;
    }
}

- (void)menuNeedsUpdate:(NSMenu*)menu
{
    mAgoMenuItem.title = [@"Status: Last update was " stringByAppendingString: [mLastUpdate timeAgo] ?: @"a while back."];
    [self querySwitcher: nil];
}

- (void)p_processResponse: (NSString*)string
{
    if (![NSThread isMainThread])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self p_processResponse: string];
        });
        return;
    }
    
    string = string ?: @"";
    
    NSMutableData* encodedStr = [NSMutableData dataWithLength: string.length * 10];
    strvis(encodedStr.mutableBytes, string.UTF8String, VIS_CSTYLE | VIS_NL);

    string = [string stringByReplacingOccurrencesOfString: @"\n" withString: @""];
    string = [string stringByReplacingOccurrencesOfString: @"\r" withString: @""];
    
    const NSUInteger numInputs = [[[NSUserDefaults standardUserDefaults] arrayForKey: kInputListKey] count];
    const NSUInteger numOutputs = [[[NSUserDefaults standardUserDefaults] arrayForKey: kOutputListKey] count];
    
    if (string.length >= (1 + numOutputs) && [string hasPrefix: @"Y"])
    {
        for (NSUInteger i = 0; i < numOutputs; i++)
        {
            NSInteger output = -1;
            [[NSScanner scannerWithString: [string substringWithRange: NSMakeRange(1 + i, 1)]] scanInteger: &output];
            if (output > (i * numInputs) && output <= ((i + 1) * numInputs))
            {
                NSInteger selectedIndex = output - (i*numInputs);
                NSMenuItem* outputMenuItem = self.statusItem.menu.itemArray[i + 2];
                NSMenu* inputMenu = outputMenuItem.submenu;
                for (NSMenuItem* mi in inputMenu.itemArray)
                {
                    mi.state = (mi.tag == selectedIndex) ? NSOnState : NSOffState;
                }
            }
        }
    }
    
    mLastUpdate = [[NSDate date] copy];
    mAgoMenuItem.title = @"Last updated: Just now!";
}

- (void)querySwitcher: (id)sender
{
    IPMTVSwitcherCommandOperation* op = [[IPMTVSwitcherCommandOperation alloc] initWithCommand: @"S\r\n" timeout:5.0 callback:^(BOOL success, NSString *response, NSError *error) {
        if (success)
            [self p_processResponse: response];
    }];
    
    [mOpQueue addOperation: op];
}

@end

@implementation NSMenuItem (CmdToSend)

static void * const key = (void*)&key;

- (NSString *)cmdToSend
{
    return objc_getAssociatedObject(self, key);
}

- (void)setCmdToSend:(NSString *)cmdToSend
{
    objc_setAssociatedObject(self, key, cmdToSend, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end


