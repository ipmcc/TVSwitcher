//
//  IPMTVSwitcherCommandOperation.m
//  TVSwitcher
//
//  Copyright (c) 2014 Ian McCullough. All rights reserved.
//

#import "IPMTVSwitcherCommandOperation.h"

@interface IPMTVSwitcherCommandOperation ()

@property (readonly) BOOL isExecuting;
@property (readonly) BOOL isFinished;

@end

@implementation IPMTVSwitcherCommandOperation
{
    NSString* mCmd;
    NSTimeInterval mTimeout;
    NSTask* mTask;
    NSMutableData* mAcc;
    IPMTVSwitcherCommandOperationCallback mCallback;
    dispatch_block_t mCancel;
}

@synthesize isExecuting = mIsExecuting;
@synthesize isFinished = mIsFinished;

- (instancetype)initWithCommand: (NSString*)cmd timeout: (NSTimeInterval)duration callback: (IPMTVSwitcherCommandOperationCallback)callback
{
    if (self = [super init])
    {
        mCmd = [cmd copy];
        mTimeout = duration;
        mCallback = [callback copy];
        //NSLog(@"init: %@", self);
    }
    return self;
}

- (void)dealloc
{
    //NSLog(@"dealloc: %@", self);
    
    [mCmd release];
    [mTask terminate];
    [mTask release];
    [mAcc release];
    [mCallback release];
    [mCancel release];
    
    [super dealloc];
}

- (void)start
{
    //NSLog(@"start: %@", self);
    
    [self willChangeValueForKey:@"isExecuting"];
    mIsExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    mTask = [[NSTask alloc] init];
    mTask.launchPath = @"/usr/bin/ssh";
    mTask.arguments = @[ @"192.168.1.253", @"sudo cu -l /dev/cu.usbserial -s 19200" ];
    NSPipe* inputPipe = [NSPipe pipe];
    NSPipe* outputPipe = [NSPipe pipe];
    NSPipe* errorPipe = [NSPipe pipe];
    
    mTask.standardInput = inputPipe;
    mTask.standardOutput = outputPipe;
    mTask.standardError = errorPipe;
    
    [mTask launch];
    
    [[inputPipe fileHandleForWriting] writeData: [mCmd dataUsingEncoding: NSUTF8StringEncoding]];
    NSLog(@"Sent command: %@", mCmd);
    
    NSMutableData* acc = [[[NSMutableData alloc] init] autorelease];
    __block typeof(self) blockSelf = self;
    
    NSFileHandle* fh = outputPipe.fileHandleForReading;
    
    fh.readabilityHandler = ^(NSFileHandle* fh){
        [acc appendData: fh.availableData];
        NSString* remoteString = [[[NSString alloc] initWithData: acc encoding: NSUTF8StringEncoding] autorelease];
        
        NSString* frontTrimmedString = remoteString;
        
        // strip newlines from the front...
        while ([frontTrimmedString hasPrefix: @"\n"] || [frontTrimmedString hasPrefix: @"\r"])
        {
            frontTrimmedString = [frontTrimmedString substringFromIndex:1];
        }
        
        const BOOL hadLineEnding = frontTrimmedString && [frontTrimmedString rangeOfString: @"\n"].location != NSNotFound;
        
        NSString* trimmedString = [frontTrimmedString stringByReplacingOccurrencesOfString: @"\n" withString: @""];
        trimmedString = [trimmedString stringByReplacingOccurrencesOfString: @"\r" withString: @""];
        
        if (hadLineEnding && trimmedString.length > 0)
        {
            [blockSelf processResponse: trimmedString];
            blockSelf = nil;
        }
    };
    
    double delayInSeconds = mTimeout;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [blockSelf finish: nil];
        blockSelf = nil;
    });
    
    mCancel = [^(){
        IPMTVSwitcherCommandOperation* bSelf = [blockSelf retain];
        blockSelf = nil;
        
        if (!bSelf)
            return;
        IPMTVSwitcherCommandOperationCallback cb = nil;
        @synchronized(bSelf)
        {
            cb = bSelf->mCallback;
            bSelf->mCallback = nil;
        }
        
        if (cb) cb(NO, nil, nil);
        [cb autorelease];
        [bSelf finish: nil];
    } copy];
}

- (void)cancel
{
    @synchronized(self)
    {
        dispatch_block_t block = mCancel;
        mCancel = nil;
        [block autorelease];
        block();
    }
}

- (void)processResponse: (NSString*)response
{
    NSLog(@"Got response: %@", response);
    @synchronized(self)
    {
        IPMTVSwitcherCommandOperationCallback cb = mCallback;
        mCallback = nil;
        cb(YES, response, nil);
        [cb autorelease];
    }
    
    [self finish: nil];
}

- (void)finish: (id)foo
{
    if (self.isFinished)
        return;
    
    [mTask.standardOutput fileHandleForReading].readabilityHandler = nil;
    [mTask terminate];
    [mTask release];
    mTask = nil;
    
    //NSLog(@"finish: %@", self);
    
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    
    mIsExecuting = NO;
    mIsFinished = YES;
    
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

@end

