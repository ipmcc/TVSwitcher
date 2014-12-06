//
//  IPMTVSwitcherCommandOperation.m
//  TVSwitcher
//
//  Copyright (c) 2014 Ian McCullough. All rights reserved.
//

#import "IPMTVSwitcherCommandOperation.h"
#import <libextobjc/EXTScope.h>

NSString* const IPMTVSwitcherRemoteHost = @"RemoteHost";
NSString* const IPMTVSwitcherRemotePort = @"RemotePort";
NSString* const IPMTVSwitcherRemoteDevice = @"RemoteSerialDevice";
NSString* const IPMTVSwitcherRemoteBaud = @"RemoteSerialSpeed";

BOOL gLog = YES;

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

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSUserDefaults standardUserDefaults] registerDefaults: @{ IPMTVSwitcherRemoteHost : @"192.168.1.253",
                                                                    IPMTVSwitcherRemotePort : @"22",
                                                                    IPMTVSwitcherRemoteDevice : @"/dev/cu.usbserial",
                                                                    IPMTVSwitcherRemoteBaud : @"19200" }];
    });
}

- (instancetype)initWithCommand: (NSString*)cmd timeout: (NSTimeInterval)duration callback: (IPMTVSwitcherCommandOperationCallback)callback
{
    if (self = [super init])
    {
        mCmd = [cmd copy];
        mTimeout = duration;
        mCallback = [callback copy];
        if (gLog)
            NSLog(@"init: %@", self);
    }
    return self;
}

- (void)dealloc
{
    if (gLog)
        NSLog(@"dealloc: %@", self);

    [mTask terminate];
}

- (void)start
{
    if (gLog)
        NSLog(@"start: %@", self);
    
    [self willChangeValueForKey:@"isExecuting"];
    mIsExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    mTask = [NSTask new];
    mTask.launchPath = @"/usr/bin/ssh";

    NSString* host = [[NSUserDefaults standardUserDefaults] stringForKey: IPMTVSwitcherRemoteHost];
    NSString* port = [[NSUserDefaults standardUserDefaults] stringForKey: IPMTVSwitcherRemotePort];
    NSString* dev = [[NSUserDefaults standardUserDefaults] stringForKey: IPMTVSwitcherRemoteDevice];
    NSString* baud = [[NSUserDefaults standardUserDefaults] stringForKey: IPMTVSwitcherRemoteBaud];
    NSString* remoteCommand = [NSString stringWithFormat: @"sudo cu -l \"%@\" -s %@", dev, baud];
    NSArray* args = @[ host, @"-p", port, remoteCommand];

    mTask.arguments = args;
    NSPipe* inputPipe = [NSPipe pipe];
    NSPipe* outputPipe = [NSPipe pipe];
    NSPipe* errorPipe = [NSPipe pipe];
    
    mTask.standardInput = inputPipe;
    mTask.standardOutput = outputPipe;
    mTask.standardError = errorPipe;
    
    [mTask launch];
    
    [[inputPipe fileHandleForWriting] writeData: [mCmd dataUsingEncoding: NSUTF8StringEncoding]];
    if (gLog)
        NSLog(@"Sent command: %@", mCmd);
    
    NSMutableData* acc = [NSMutableData new];

    @weakify(self);

    NSFileHandle* fh = outputPipe.fileHandleForReading;
    
    fh.readabilityHandler = ^(NSFileHandle* fh){
        @strongify(self);
        [acc appendData: fh.availableData];
        NSString* remoteString = [[NSString alloc] initWithData: acc encoding: NSUTF8StringEncoding];
        
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
            [self processResponse: trimmedString];
        }
    };
    
    double delayInSeconds = mTimeout;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        @strongify(self);
        [self finish: nil];
    });

    mCancel = [^{
        @strongify(self);

        IPMTVSwitcherCommandOperationCallback cb = [self consumeCallback];
        if (cb)
        {
            cb(NO, nil, nil);
        }
        [self finish: nil];

    } copy];
}

- (IPMTVSwitcherCommandOperationCallback)consumeCallback
{
    @synchronized(self)
    {
        IPMTVSwitcherCommandOperationCallback callback = mCallback;
        mCallback = nil;
        return callback;
    }
}

- (dispatch_block_t)consumeCancelHandler
{
    @synchronized(self)
    {
        dispatch_block_t cancelHandler = mCancel;
        mCancel = nil;
        return cancelHandler;
    }
}

- (void)cancel
{
    dispatch_block_t cancelHandler = [self consumeCancelHandler];
    if (cancelHandler)
    {
        cancelHandler();
    }
}

- (void)processResponse: (NSString*)response
{
    if (gLog)
        NSLog(@"Got response: %@", response);

    IPMTVSwitcherCommandOperationCallback callback = [self consumeCallback];

    if (callback)
    {
        callback(YES, response, nil);
    }

    [self finish: nil];
}

- (void)finish: (id)sender
{
    if (self.isFinished)
        return;
    
    [mTask.standardOutput fileHandleForReading].readabilityHandler = nil;
    [mTask terminate];
    mTask = nil;
    
    if (gLog)
        NSLog(@"finish: %@", self);
    
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    
    mIsExecuting = NO;
    mIsFinished = YES;
    
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];

    [self consumeCallback];
    [self consumeCancelHandler];
}

- (NSString*)description
{
    NSMutableString* str = [[super description] mutableCopy];
    [str setString: @""];
    [str appendFormat: @"<%@ %p", NSStringFromClass([self class]), self];
    if (self.name)
    {
        [str appendFormat: @" name: '%@'", self.name];
    }
    [str appendFormat: @" isExecuting: %@", self.isExecuting ? @"YES" : @"NO"];
    [str appendFormat: @" isFinished: %@", self.isFinished ? @"YES" : @"NO"];

    [str appendString: @">"];
    return str;
}

@end

