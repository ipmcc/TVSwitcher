//
//  NSString+VisEncode.m
//  TVSwitcher
//
//  Copyright (c) 2014 Ian McCullough. All rights reserved.
//

#import "NSString+VisEncode.h"
#import <vis.h>

@implementation NSString (VisEncode)

- (NSString*)visEncodeWithFlags: (int)flags
{
    NSMutableData* encodedStr = [NSMutableData dataWithLength: self.length * 10];
    strvis(encodedStr.mutableBytes, self.UTF8String, flags);
    return [[NSString alloc] initWithUTF8String: encodedStr.bytes];
}

@end
