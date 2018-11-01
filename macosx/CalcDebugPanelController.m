//
//  CalcDebugPanelController.m
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-04.
//  Copyright 2009 dwj. All rights reserved.
//

#import "CalcDebugPanelController.h"
#import "CalcBreakpointPanelController.h"
#import "CalcDebugger.h"
#import "CalcBackend.h"
#import "ToggleToolbarItem.h"
#include "debugger.h"


@implementation CalcDebugPanelController

- (IBAction)cont:(id)sender
{
    [[self debugModel] cont];
}

- (IBAction)editBreakpoints:(id)sender
{
    [self debugModel];
    [breakpointController showWindow: sender];
}

- (IBAction)fullResetCalc:(id)sender
{
}

- (IBAction)pauseDebug:(id)sender
{
    [[self debugModel] pause];
}

//- (IBAction)resetCalc:(id)sender
//{
//}

- (IBAction)setBreakpoint:(id)sender
{
    id sel = [disassemblyController selection];
    id breakpointStatus = [sel valueForKeyPath: @"breakpointStatus"];
    id code = [sel valueForKeyPath: @"code"];
    NSScanner *scanner = [NSScanner scannerWithString: code];
    unsigned hexResult = 0;
    if ([scanner scanHexInt: &hexResult])
    {
        CalcBreakpoint *breakpoint = [[[CalcBreakpoint alloc] init] autorelease];
        [breakpoint setAddress: [NSNumber numberWithUnsignedInt: hexResult]];
        switch ([breakpointStatus intValue])
        {
            case NSControlStateValueOn:
            case NSControlStateValueOff:
                break;
            default:
                [breakpointController addBreakpoint: breakpoint];
                break;
        }
    }
}

- (IBAction)stepInto:(id)sender
{
	[[self debugModel] stepInto];
}

- (IBAction)stepOut:(id)sender
{
	[[self debugModel] stepOut];
}

- (IBAction)stepOver:(id)sender
{
    [[self debugModel] stepOver];
}

- (IBAction)showHistory:(id)sender
{
    [historyPanel makeKeyAndOrderFront: sender];
}

- (IBAction)showProfiler:(id)sender
{
    [profilerPanel makeKeyAndOrderFront: sender];
}

- (IBAction)showWoRegisters:(id)sender
{
    [woRegistersPanel makeKeyAndOrderFront: sender];
}

- (IBAction)toggleBreakpoints:(id)sender
{
    [toggleBreakpointsToolbarItem toolbarItemToggled];
    [[self debugModel] toggleBreakpoints];
}

// Translate clicks in first column of disassembly table to
// set/disable/remove breakpoint for an address
- (IBAction)breakpointClicked:(id)sender
{
    int row = (int)[disassemblyTable selectedRow];
    if (row >= 0)
    {
        CalcBreakpoint *breakpoint;
        [disassemblyController setSelectionIndex: row];
        id sel = [disassemblyController selection];
        id breakpointStatus = [sel valueForKeyPath: @"breakpointStatus"];
        id code = [sel valueForKeyPath: @"code"];
        NSScanner *scanner = [NSScanner scannerWithString: code];
        unsigned hexResult = 0;
        if ([scanner scanHexInt: &hexResult])
        {
            breakpoint = [[[CalcBreakpoint alloc] init] autorelease];
            [breakpoint setAddress: [NSNumber numberWithUnsignedInt: hexResult]];
            switch ([breakpointStatus intValue])
            {
                case NSControlStateValueOn:
                    [breakpointController addBreakpoint: breakpoint];
                    break;
                case NSControlStateValueOff:
                    [breakpointController disableBreakpoint: breakpoint];
                    break;
                default:
                    [breakpointController removeBreakpoint: breakpoint];
                    break;
            }
        }
    }
}

- (IBAction)clearHistory:(id)sender
{
    [[self debugModel] clearHistory];
}


- (id)init
{
    self = [super initWithWindowNibName: @"Debugger"];
    if (self)
    {
        [self window];
        [breakpointArrayController addObserver:self forKeyPath:@"arrangedObjects.enabled" options:0 context:nil];
        [self setWindowFrameAutosaveName: @"Debugger"];
        [historyPanel     setFrameAutosaveName: @"History"];
        [profilerPanel    setFrameAutosaveName: @"Profiler"];
        [woRegistersPanel setFrameAutosaveName: @"WoRegisters"];
        [self setDebuggerToolbar];
    }
    return self;
}

- (void)dealloc
{
    [breakpointArrayController removeObserver:self forKeyPath:@"arrangedObjects.enabled"];
    [toolbarIdList release];
    [toolbarLabelList release];
    [toolbarTooltipList release];
    [toolbarImageList release];
    [super dealloc];
}

- (CalcDebugger *)debugModel
{
    if (nil==debugModel)
        [self setDebugModel: [[CalcBackend sharedBackend] debugModel]];
    return debugModel;
}

- (void)setDebugModel:(CalcDebugger *)aDebugModel
{
    debugModel = aDebugModel;
    [debugController setContent: aDebugModel];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    id sel = [object valueForKeyPath: @"selection"];
    if ([keyPath isEqualToString: @"arrangedObjects.enabled"])
    {
        id enabled = [sel valueForKeyPath: @"enabled"];
        id address = [sel valueForKeyPath: @"address"];
        if (NSNoSelectionMarker != enabled && address)
        {
            [[self debugModel] performSelectorOnMainThread:@selector(enableDebugger) withObject:nil waitUntilDone:NO];
;
        }
    }
}


#pragma mark -
#pragma mark Toolbar support

- (void)setDebuggerToolbar
{
    // Fill out constants
    toolbarIdList = [NSArray arrayWithObjects:
                     @"Pause", @"Cont", @"StepOver", @"StepInto", @"StepOut", @"ToggleBreakpoints",
                     nil];
    [toolbarIdList retain];
    toolbarLabelList = [NSArray arrayWithObjects:
                        @"Pause", @"Continue", @"Step Over", @"Step Into", @"Step Out", @"Disable Breakpoints",
                        nil];
    [toolbarLabelList retain];
    toolbarTooltipList = [NSArray arrayWithObjects:
                          @"Pause execution", @"Continue execution", @"Step over subroutine", @"Single step execution", @"Step out of current subroutine", @"Activate/Deactivate breakpoints",
                          nil];
    [toolbarTooltipList retain];
    toolbarImageList = [NSArray arrayWithObjects:
                        @"pause", @"continue", @"step_over", @"step_in", @"step_out", @"breakpoints_enabled",
                        nil];
    [toolbarImageList retain];

    NSToolbar *toolbar = [[NSToolbar alloc]initWithIdentifier:@"DebuggerToolbar"];
    [toolbar autorelease];
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    // Following will be overriden if a previous config exists
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [[self window] setToolbar:toolbar];
}


- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
    id item = [[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier];

    NSString *toolid;
    NSString *tool_label;
    NSString *tool_tooltip;
    NSImage *tool_image;
    int i, toolcount=(int)[toolbarIdList count];

    for (i=0; i<toolcount; ++i)
    {
        toolid = [toolbarIdList objectAtIndex: i];
        if ([itemIdentifier isEqualToString: toolid])
        {
            switch(i)
            {
                case kDebugToolPause:
                    [item setAction: @selector(pauseDebug:)];
                    break;
                case kDebugToolCont:
                    [item setAction: @selector(cont:)];
                    break;
                case kDebugToolStepOver:
                    [item setAction: @selector(stepOver:)];
                    break;
                case kDebugToolStepInto:
                    [item setAction: @selector(stepInto:)];
                    break;
                case kDebugToolStepOut:
                    [item setAction: @selector(stepOut:)];
                    break;
                case kDebugToolToggleBreakpoints:
                    [item release];
                    item = [[ToggleToolbarItem alloc] initWithItemIdentifier: itemIdentifier];
                    [item setAlternateImage: [NSImage imageNamed: @"breakpoints_disabled"]];
                    [item setAlternateLabel: NSLocalizedString(@"Enable Breakpoints",@"")];
                    [item setAction: @selector(toggleBreakpoints:)];
                    if (flag)
                        toggleBreakpointsToolbarItem = item;
                    break;
            }
            tool_label   = NSLocalizedString([toolbarLabelList objectAtIndex: i],@"");
            tool_tooltip = NSLocalizedString([toolbarTooltipList objectAtIndex: i],@"");
            tool_image   = [NSImage imageNamed:[toolbarImageList objectAtIndex: i]];
            if(nil!=tool_label)
                [item setLabel:tool_label];
            if(nil!=tool_tooltip)
                [item setToolTip:tool_tooltip];
            if(nil!=tool_image)
                [item setImage:tool_image];
            [item setTarget:self];
            [item setPaletteLabel:[item label]];
            break;
        }
    }
    
    return [item autorelease];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    NSMutableArray *idlist = [[NSMutableArray alloc] initWithArray:toolbarIdList];
    [idlist addObject:NSToolbarSeparatorItemIdentifier];
    [idlist addObject:NSToolbarSpaceItemIdentifier];
    [idlist addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [idlist addObject:NSToolbarCustomizeToolbarItemIdentifier];
    [idlist autorelease];
    return idlist;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    NSMutableArray *idlist = [[NSMutableArray alloc] initWithArray:toolbarIdList];
    [idlist insertObject:NSToolbarFlexibleSpaceItemIdentifier
                 atIndex:kDebugToolToggleBreakpoints];
    [idlist autorelease];

    return idlist;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
    if([item.itemIdentifier isEqualToString:@"Pause"]) {
        return nDbgState == DBG_RUN || nDbgState == DBG_OFF;
    } else if([item.itemIdentifier isEqualToString:@"Cont"] || [item.itemIdentifier isEqualToString:@"StepOver"]
              || [item.itemIdentifier isEqualToString:@"StepInto"] || [item.itemIdentifier isEqualToString:@"StepOut"]) {
        return nDbgState == DBG_STEPINTO || nDbgState == DBG_STEPOVER || nDbgState == DBG_STEPOUT;
    } else if([item.itemIdentifier isEqualToString:@"ToggleBreakpoints"]) {
    }
    return YES;
}

- (IBAction)codeGotoAddress:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Enter address (hexadecimal)"];
    [alert addButtonWithTitle:@"Ok"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:@""];
    
    [alert setAccessoryView:input];
    [[alert window] setInitialFirstResponder: input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        NSString * addressText = [input stringValue];
        unsigned int address = 0;
        NSScanner * scanner = [NSScanner scannerWithString:addressText];
        if([scanner scanHexInt:&address]) {
            [[self debugModel] setCodeAddress:address];
        }
    }
}
- (IBAction)codeGotoPC:(id)sender {
    [[self debugModel] setCodeAddress:Chipset.pc];
}

- (IBAction)memoryGotoAddress:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Enter address (hexadecimal)"];
    [alert addButtonWithTitle:@"Ok"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:@""];
    
    [alert setAccessoryView:input];
    [[alert window] setInitialFirstResponder: input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        NSString * addressText = [input stringValue];
        unsigned int address = 0;
        NSScanner * scanner = [NSScanner scannerWithString:addressText];
        if([scanner scanHexInt:&address]) {
            [[self debugModel] setMemoryAddress:address];
        }
    }
}

- (IBAction)memoryGotoPC:(id)sender {
    [[self debugModel] setMemoryAddress:Chipset.pc];
}

- (IBAction)memoryGotoD0:(id)sender {
    [[self debugModel] setMemoryAddress:Chipset.d0];
}

- (IBAction)memoryGotoD1:(id)sender {
    [[self debugModel] setMemoryAddress:Chipset.d1];
}

- (IBAction)memoryGotoStack:(id)sender {
    [[self debugModel] setMemoryAddress:Chipset.rstk[(Chipset.rstkp-1)&7]];
}

@end
