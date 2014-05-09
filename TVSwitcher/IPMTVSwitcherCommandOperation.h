//
//  IPMTVSwitcherCommandOperation.h
//  TVSwitcher
//
//  Copyright (c) 2014 Ian McCullough. All rights reserved.
//

typedef void (^IPMTVSwitcherCommandOperationCallback)(BOOL success, NSString* response, NSError* error);

@interface IPMTVSwitcherCommandOperation : NSOperation

- (instancetype)initWithCommand: (NSString*)cmd timeout: (NSTimeInterval)duration callback: (IPMTVSwitcherCommandOperationCallback)callback;

@end
