//
//  IPMTVSwitcherCommandOperation.h
//  TVSwitcher
//
//  Copyright (c) 2014 Ian McCullough. All rights reserved.
//

extern NSString* const IPMTVSwitcherRemoteHost;
extern NSString* const IPMTVSwitcherRemotePort;
extern NSString* const IPMTVSwitcherRemoteDevice;
extern NSString* const IPMTVSwitcherRemoteBaud;

typedef void (^IPMTVSwitcherCommandOperationCallback)(BOOL success, NSString* response, NSError* error);

@interface IPMTVSwitcherCommandOperation : NSOperation

- (instancetype)initWithCommand: (NSString*)cmd timeout: (NSTimeInterval)duration callback: (IPMTVSwitcherCommandOperationCallback)callback;

@end
