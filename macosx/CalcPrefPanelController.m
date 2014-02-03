//
//  CalcPrefPanelController.m
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-04.
//  Copyright 2009 dwj. All rights reserved.
//
#import "CalcPrefPanelController.h"
#import "CalcPrefController.h"
#import "files.h"

#define PREF_TOOLBAR_ID     @"PREF_PANEL"
#define PREF_STARTUP_ID     @"Startup"
#define PREF_CALCS_ID       @"Calculators"
#define PREF_SETTINGS_ID    @"Settings"

@interface CalcPrefPanelController(Private)
- (void)switchTab:(id)aSender;
- (void)setupToolbar;
@end


@implementation CalcPrefPanelController

- (IBAction)prefBrowsePort2File:(id)sender
{
    int result;
    // nil fileTypes => "all files"
    NSArray *fileTypes = nil;
    //[NSArray arrayWithObjects:NSFileTypeForHFSTypeCode('ERAM'), @"", nil];
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    
    [oPanel setResolvesAliases: YES];
    [oPanel setAllowsMultipleSelection: NO];
    [oPanel setAllowedFileTypes: fileTypes];
    result = [oPanel runModal];
    
    if (result == NSOKButton)
    {
        NSArray *filesToOpen = [oPanel URLs];
        NSString *aFile = [filesToOpen objectAtIndex:0];
        [[NSUserDefaults standardUserDefaults] setObject:aFile forKey:@"Port2Filename"];
    }
}

- (IBAction)prefMakeCalculatorDefault:(id)sender
{
    [prefModel setDefaultCalculator: [sender intValue]];
    [calculatorsView setNeedsDisplay: YES];
}

- (IBAction)prefNewPort2File:(id)sender
{
    const int BLOCK_SIZES[] = {32, 128, 256, 512, 1024, 2048, 4096};
    
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setTitle: NSLocalizedString(@"New: HP48SX/GX Memory Card",@"")];
    [panel setPrompt: NSLocalizedString(@"Make",@"")];
    [panel setMessage: NSLocalizedString(@"Note: Actual file size will be twice the chosen size.",@"")];
    [panel setAccessoryView: cardSizeView];
    int result = [panel runModal];
    if (result == NSOKButton)
    {
        int blockIndex = [cardSizePopup indexOfSelectedItem];
        if (blockIndex < 0 || blockIndex >= sizeof(BLOCK_SIZES))
            blockIndex = 0;
        int numBlocks = BLOCK_SIZES[blockIndex];
        if (NewPort2([[panel URL] absoluteString], numBlocks))
        {
            [[NSUserDefaults standardUserDefaults] setObject:[[panel URL] absoluteString] forKey:@"Port2Filename"];
        }
    }
}

- (IBAction)prefReset:(id)sender
{
    [CalcPrefController resetDefaults];
}


- (id)init
{
    self = [super initWithWindowNibName: @"Prefs"];
    if (self)
    {
        allIdentifiers = [[NSArray alloc] initWithObjects:
                          PREF_STARTUP_ID,
                          PREF_CALCS_ID,
                          PREF_SETTINGS_ID,
                          nil];
        [self window];
    }
    return self;
}

- (void)dealloc
{
    [allIdentifiers release];
    [views release];
    [super dealloc];
}

- (CalcPrefController *)prefModel
{
    return prefModel;
}

#pragma mark -
#pragma mark Table view support

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    if ([[aTableColumn identifier] isEqualToString: @"desc"])
    {
        BOOL isActive   = [[self window] isKeyWindow];
        BOOL isSelected = ([aTableView selectedRow] == rowIndex);
        BOOL isDefault  = (rowIndex == [prefModel DefaultCalculator]);
        NSString *descAll = [aCell stringValue];
        NSArray *lines = [descAll componentsSeparatedByString: @"\n"];
        NSMutableAttributedString *descStr;
        NSMutableDictionary *largeAttribs = [NSMutableDictionary dictionaryWithObject:[NSFont systemFontOfSize:13.0] forKey:NSFontAttributeName];
        NSMutableDictionary *smallAttribs = [NSMutableDictionary dictionaryWithObject:[NSFont systemFontOfSize:11.0] forKey:NSFontAttributeName];
        if (!isSelected && isActive)
        {
            [smallAttribs setObject:[NSColor disabledControlTextColor] forKey:NSForegroundColorAttributeName];
        }
        descStr = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", [lines objectAtIndex: 0]] attributes:largeAttribs];
        [descStr beginEditing];
        [descStr appendAttributedString: [[[NSAttributedString alloc] initWithString:[lines objectAtIndex: 1] attributes:smallAttribs] autorelease]];
        if (isDefault)
            [descStr appendAttributedString: [[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@", NSLocalizedString(@"Default",@"")] attributes:smallAttribs] autorelease]];
        [descStr endEditing];
        [aCell setAttributedStringValue: descStr];
        [descStr release];
    }
}

#pragma mark -
#pragma mark Tab support

- (void)switchToViewWithIdentifier:(NSString *)aIdentifier
{
    id view = [views objectForKey: aIdentifier];
    if (view)
    {
        if (![[[[self window] toolbar] selectedItemIdentifier] isEqualToString: aIdentifier])
        {
            [[[self window] toolbar] setSelectedItemIdentifier: aIdentifier];
        }
        
        selectedIdentifier = aIdentifier;
        [[self window] setTitle: NSLocalizedString(aIdentifier,@"")];
        NSPoint origin = [[self window] frame].origin;
        NSRect contentRect = [NSWindow contentRectForFrameRect:[[self window] frame]
                                                     styleMask:[[self window]
                                                                styleMask]];
        NSView *oldContentView = [[self window] contentView];
        float toolbarHeight = oldContentView ? NSHeight(contentRect) - NSHeight([oldContentView frame]) : 0.0;
        NSRect windowFrame = [NSWindow frameRectForContentRect:[view frame]
                                                     styleMask:[[self window] styleMask]];
        windowFrame.size.height += toolbarHeight;
        windowFrame.origin = NSMakePoint(origin.x, origin.y + NSHeight([[self window] frame]) - NSHeight(windowFrame));
        
        [view setHidden: YES];
        [[self window] setContentView: view];
        [[self window] setInitialFirstResponder: view];
        [[self window] setFrame:windowFrame display:YES animate:YES];
        [view setHidden: NO];
        
        NSSize curSize  = [[self window] frame].size;
        curSize.height -= toolbarHeight;
        [[self window] setShowsResizeIndicator: NO];
        [[self window] setMinSize: curSize];
        [[self window] setMaxSize: curSize];
    }
}

- (void)windowDidLoad
{
    NSWindow *window = [self window];
    [window setDelegate: self];
    views = [[NSDictionary alloc] initWithObjectsAndKeys:
             startupView,     PREF_STARTUP_ID,
             calculatorsView, PREF_CALCS_ID,
             settingsView,    PREF_SETTINGS_ID,
             nil];
    if (nil == [window toolbar])
        [self setupToolbar];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    // Forcibly refresh bindings
    [prefModel setPort1Enabled: YES];
    [prefModel setPort2Enabled: YES];
}

- (void)switchTab:(id)aSender
{
    [self switchToViewWithIdentifier: [[[self window] toolbar] selectedItemIdentifier]];
}

- (void) setupToolbar
{
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: PREF_TOOLBAR_ID];
    [toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
    [toolbar setAllowsUserCustomization: NO];
    [toolbar setDelegate: self];
    [[self window] setToolbar: toolbar];
    [toolbar release];
    [self switchToViewWithIdentifier: PREF_STARTUP_ID];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)aToolbar
     itemForItemIdentifier:(NSString *)aId
 willBeInsertedIntoToolbar:(BOOL)aFlag
{
    NSToolbarItem *item = nil;
    if ([views objectForKey: aId])
    {
        item = [[[NSToolbarItem alloc] initWithItemIdentifier: aId] autorelease];
        NSString *label = NSLocalizedString(aId,@"");
        [item setLabel: label]; [item setPaletteLabel: label];
        if ([aId isEqualToString: PREF_STARTUP_ID])
            [item setImage: [NSImage imageNamed: @"startup"]];
        else if ([aId isEqualToString: PREF_CALCS_ID])
            [item setImage: [NSImage imageNamed: @"EM48"]];
        else if ([aId isEqualToString: PREF_SETTINGS_ID])
            [item setImage: [NSImage imageNamed: @"settings"]];
        
        [item setTarget: self]; [item setAction: @selector(switchTab:)];
    }
    return item;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)aToolbar
{
    return allIdentifiers;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)aToolbar
{
    return allIdentifiers;
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)aToolbar
{
    return allIdentifiers;
}
@end
