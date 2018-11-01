//
//  HexNumberFormatter.m
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-14.
//  Copyright 2009 dwj. All rights reserved.
//

#import "HexNumberFormatter.h"


@implementation HexNumberFormatter

- (NSString *)stringForObjectValue:(id)anObject
{
    if (![anObject isKindOfClass:[NSNumber class]])
        return nil;
    return [NSString stringWithFormat:@"%05dX", [anObject intValue]];
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error
{
    unsigned hexResult;
    NSScanner *scanner;
    BOOL returnValue = NO;
    
    scanner = [NSScanner scannerWithString: string];
    if ([scanner scanHexInt: &hexResult] && ([scanner isAtEnd]))
    {
        returnValue = YES;
        if (anObject)
            *anObject = [NSNumber numberWithUnsignedInt: hexResult];
    }
    else
    {
        if (error)
            *error = NSLocalizedString(@"Could not convert hexadecimal value.", @"Error converting.");
    }
    return returnValue;
}
@end
