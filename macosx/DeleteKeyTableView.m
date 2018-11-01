//
//  DeleteKeyTableView.m
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-14.
//  Copyright 2009 dwj. All rights reserved.
//

#import "DeleteKeyTableView.h"


@implementation DeleteKeyTableView

- (void)bind:(NSString *)binding toObject:(id)observable
 withKeyPath:(NSString *)keyPath options:(NSDictionary *)options
{	
	if ( [binding isEqualToString: @"content"] )
	{
		tableContentController = observable;
	}
	[super bind:binding toObject:observable withKeyPath:keyPath options:options];
}

- (void)unbind:(NSString *)binding
{
	[super unbind:binding];
	
	if ( [binding isEqualToString: @"content"] )
	{
		tableContentController = nil;
	}
}

- (void)keyDown:(NSEvent *)event
{
	unichar key = [[event charactersIgnoringModifiers] characterAtIndex: 0];
    
	// get flags and strip the lower 16 (device dependent) bits
	unsigned int flags = ([event modifierFlags] & 0x00FF);

	if ((NSDeleteCharacter==key || NSDeleteFunctionKey==key) && (flags==0))
	{
		if ([self selectedRow] < 0)
		{
			NSBeep();
		}
		else
		{
			[tableContentController removeObjectsAtArrangedObjectIndexes: [self selectedRowIndexes]];
		}
	}
	else
	{
		[super keyDown:event];
	}
}

- (void)textDidEndEditing:(NSNotification *)aNotification
{
    NSText *textField = [aNotification object];
    NSString *str = [textField string];
    if (0 == [str length])
    {
        int selectedRow = (int)[self selectedRow];
        if (selectedRow >= 0)
            [tableContentController removeObjectAtArrangedObjectIndex: selectedRow];
    }
    else
    {
        [super textDidEndEditing: aNotification];
        if ([self delegate] && [[self delegate] respondsToSelector: @selector(textDidEndEditing:)])
        {
            [[self delegate] performSelector:@selector(textDidEndEditing:) withObject:aNotification];
        }
    }
}
@end
