//
//  CalcBreakpointPanelController.m
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-14.
//  Copyright 2009 dwj. All rights reserved.
//

#import "CalcBreakpointPanelController.h"
#import "CalcDebugger.h"
#import "CalcBackend.h"
#import "CalcAppController.h"


@implementation CalcBreakpointPanelController

- (IBAction)breakpointAdd:(id)sender
{
    id breakpoint = [breakpointController newObject];
    NSNumber *breakpointCount = [breakpointController valueForKeyPath: @"arrangedObjects.@count"];
    [breakpointController insertObject:breakpoint atArrangedObjectIndex:[breakpointCount unsignedIntValue]];
    [breakpointTable editColumn:1 row:[breakpointCount unsignedIntValue] withEvent:nil select:YES];
}

- (void)awakeFromNib
{
    [self setWindowFrameAutosaveName: @"Breakpoints"];
}

- (void)addBreakpoint:(CalcBreakpoint *)aBreakpoint
{
    [breakpointController addObject: aBreakpoint];
}
- (void)disableBreakpoint:(CalcBreakpoint *)aBreakpoint
{
    if ([aBreakpoint address])
    {
        NSArray *breakpoints = [breakpointController arrangedObjects];
        unsigned index = (unsigned int)[breakpoints indexOfObject: aBreakpoint];
        if (NSNotFound != index)
        {
            id breakpoint = [breakpoints objectAtIndex: index];
            [breakpoint setEnabled: NO];
        }
    }
}
- (void)removeBreakpoint:(CalcBreakpoint *)aBreakpoint
{
    [breakpointController removeObject: aBreakpoint];
}

- (void)textDidEndEditing:(NSNotification *)aNotification
{
    id sel = [breakpointController selection];
    id enabled = [sel valueForKeyPath: @"enabled"];

    if (NSNoSelectionMarker != enabled && [enabled boolValue])
    {
        [[NSApp delegate] performSelector:@selector(showDebugger:) withObject:nil];
        [[[CalcBackend sharedBackend] debugModel] performSelectorOnMainThread:@selector(enableDebugger) withObject:nil waitUntilDone:NO];
    }
}
@end
