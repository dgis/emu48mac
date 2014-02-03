//
//  CalcAppController.m
//  emu48
//
//  Created by Da Woon Jung on 2009-01-22.
//  Copyright (c) 2009 dwj. All rights reserved.
//

#import "CalcAppController.h"
#import "CalcBackend.h"
#import "CalcDocument.h"
#import "KmlLogController.h"
#import "CalcPrefPanelController.h"
#import "CalcPrefController.h"
#import "CalcDebugPanelController.h"

VOID UpdateWindowStatus(VOID){}

@interface CalcAppController(Private)
- (CalcPrefPanelController *)prefController;
@end


@implementation CalcAppController

- (IBAction)openROM:(id)sender
{
    int result;
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setResolvesAliases: YES];
    [oPanel setAllowsMultipleSelection: NO];
    result = [oPanel runModal];
}

- (IBAction)showDebugger:(id)sender
{
    if (nil==debugger)
        debugger = [[CalcDebugPanelController alloc] init];
    [debugger showWindow: sender];
}

- (IBAction)editBreakpoints:(id)sender
{
    if (nil==debugger)
        debugger = [[CalcDebugPanelController alloc] init];
    [debugger editBreakpoints: sender];
}

- (IBAction)showHistory:(id)sender
{
    if (nil==debugger)
        debugger = [[CalcDebugPanelController alloc] init];
    [debugger showHistory: sender];
}

- (IBAction)showPrefs:(id)sender
{
    [[self prefController] showWindow: sender];
}

- (IBAction)showProfiler:(id)sender
{
    if (nil==debugger)
        debugger = [[CalcDebugPanelController alloc] init];
    [debugger showProfiler: sender];
}

- (IBAction)showWoRegisters:(id)sender
{
    if (nil==debugger)
        debugger = [[CalcDebugPanelController alloc] init];
    [debugger showWoRegisters: sender];
}

- (IBAction)turnOnCalc:(id)sender
{
    [[CalcBackend sharedBackend] onPowerKey];
}


- (void) dealloc
{
    [debugger release];
    [filesToOpen release];
    [kmlLogController release];
    [prefController release];
    [documentController release];
    [super dealloc];
}


- (CalcPrefPanelController *)prefController
{
    if (nil==prefController)
        prefController = [[CalcPrefPanelController alloc] init];
    return prefController;
}

- (KmlLogController *)kmlLogController;
{
    if (nil == kmlLogController)
    {
        kmlLogController = [[KmlLogController alloc] init];
        [kmlLogController window];
    }
    return kmlLogController;
}


#pragma mark -
#pragma mark NSApplication delegate methods

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
    [CalcPrefController registerDefaults];
    documentController = [[CalcDocumentController alloc] init];
    [self populateNewCalcMenu];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    [[[self prefController] prefModel] performSelector:@selector(refreshCalculators:) withObject:nil afterDelay:0.0];
    [self populateNewCalcMenu];
}

- (void)reviewChangesAndQuitEnumeration:(NSNumber *)cont
{
    [NSApp replyToApplicationShouldTerminate: [cont boolValue]];
}

- (void)reviewChangesAndOpenEnumeration:(NSNumber *)cont
{
    if ([cont boolValue] && filesToOpen)
    {
        [self application:NSApp openFiles:filesToOpen];
    }
    [filesToOpen release]; filesToOpen = nil;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)app
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL reloadFiles = [defaults boolForKey: @"ReloadFiles"];
    if (reloadFiles)
    {
        id dc = [NSDocumentController sharedDocumentController];
        NSArray *recentFiles = [dc recentDocumentURLs];
        if (recentFiles && [recentFiles count] > 0)
        {
            NSURL *path = [recentFiles objectAtIndex: 0];
            if (path)
            {
                NSError *err = nil;
                id doc = [dc openDocumentWithContentsOfURL:path display:YES error:&err];
                if (nil == doc && err)
                {
                    [dc presentError: err];
                }
            }
        }
    }
    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app
                    hasVisibleWindows:(BOOL)flag
{
    return NO;
}


#pragma mark -
#pragma mark Dynamic menus

- (void)populateNewCalcMenu
{
    SEL newCalcAction = @selector(newDocument:);
    [newCalcMenu setMenuChangedMessagesEnabled: NO];
    int i;
    int calcCount = [newCalcMenu numberOfItems];
    for (i = 0; i < calcCount; ++i)
        [newCalcMenu removeItemAtIndex: 0];
    NSArray *calculators = [[[self prefController] prefModel] calculators];
    int defaultCalc = [[[self prefController] prefModel] DefaultCalculator];
    NSDictionary *calc;
    NSString *calcPath;
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSMenuItem *mi;
    calcCount = [calculators count];
    if (calcCount > 0)
    {
        calc = [calculators objectAtIndex: defaultCalc];
        calcPath = [calc objectForKey: @"path"];
        if (![calcPath isAbsolutePath])
        {
            calcPath = [resourcePath stringByAppendingPathComponent: calcPath];
        }
        mi = [[NSMenuItem alloc] init];
        [mi setTitle: [calc objectForKey: @"title"]];
        [mi setAction: newCalcAction];
        [mi setKeyEquivalent: @"n"];
        [mi setRepresentedObject: calcPath];
//        [mi setEnabled: canNew];
        [newCalcMenu addItem: mi];
        [mi release];
        if (calcCount > 1)
            [newCalcMenu addItem: [NSMenuItem separatorItem]];
    }
    for (i = 0; i < calcCount; ++i)
    {
        if (i == defaultCalc)
            continue;
        calc = [calculators objectAtIndex: i];
        calcPath = [calc objectForKey: @"path"];
        if (![calcPath isAbsolutePath])
        {
            calcPath = [resourcePath stringByAppendingPathComponent: calcPath];
        }
        mi = [[NSMenuItem alloc] init];
        [mi setTitle: [calc objectForKey: @"title"]];
        [mi setAction: newCalcAction];
        [mi setRepresentedObject: calcPath];
//        [mi setEnabled: canNew];
        [newCalcMenu addItem: mi];
        [mi release];
    }
    [newCalcMenu setMenuChangedMessagesEnabled: YES];
}

- (void)populateChangeKmlMenu
{
    CalcBackend *backend = [CalcBackend sharedBackend];
    [kmlMenu setMenuChangedMessagesEnabled: NO];
    int i;
    int kmlCount = [kmlMenu numberOfItems];
    for (i = 0; i < kmlCount; ++i)
        [kmlMenu removeItemAtIndex: 0];
    NSArray *calculators = [[[self prefController] prefModel] calculators];
    NSDictionary *calc;
    id model;
    NSString *currentModel = [backend currentModel];
    NSString *calcPath;
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    SEL changeKmlAction = @selector(changeKml:);
    kmlCount = [calculators count];
    for (i = 0; i < kmlCount; ++i)
    {
        calc  = [calculators objectAtIndex: i];
        model = [calc objectForKey: @"model"];
        if (![model isEqualToString: currentModel])
            continue;
        calcPath = [calc objectForKey: @"path"];
        if (![calcPath isAbsolutePath])
        {
            calcPath = [resourcePath stringByAppendingPathComponent: calcPath];
        }
        NSMenuItem *mi = [[NSMenuItem alloc] init];
        [mi setTitle: [calc objectForKey: @"title"]];
        [mi setTarget: backend];
        [mi setAction: changeKmlAction];
        [mi setRepresentedObject: calcPath];
        [kmlMenu addItem: mi];
        [mi release];
    }
    [kmlMenu setMenuChangedMessagesEnabled: YES];
}

- (BOOL)validateMenuItem:(NSMenuItem *)sender
{
    if ([sender action] == @selector(openROM:) ||
        [sender action] == @selector(openObject:) ||
        [sender action] == @selector(saveObject:))
    {
        NSArray *docs = [[NSDocumentController sharedDocumentController] documents];
        BOOL canNew = !(docs && [docs count] > 0);

        if ([sender action] == @selector(openROM:))
        {
            if (!canNew)
                return NO;	// dim if calc already newed
        }
        else if ([sender action] == @selector(openObject:) ||
                 [sender action] == @selector(saveObject:))
        {
            if (canNew)
                return NO;	// dim if there is no calc window
        }
    }

    return YES;
}
@end
