//
//  CalcDebugPanelController.h
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-04.
//  Copyright 2009 dwj. All rights reserved.
//

enum {
    kDebugToolPause,
    kDebugToolCont,
    kDebugToolStepOver,
    kDebugToolStepInto,
    kDebugToolStepOut,
    kDebugToolToggleBreakpoints
};

@class CalcDebugger;
@class CalcBreakpointPanelController;
@class ToggleToolbarItem;


@interface CalcDebugPanelController : NSWindowController <NSToolbarDelegate>
{
    IBOutlet NSObjectController *debugController;
    IBOutlet NSArrayController *breakpointArrayController;
    IBOutlet NSArrayController *disassemblyController;
    IBOutlet CalcBreakpointPanelController *breakpointController;
    IBOutlet NSPanel *historyPanel;
    IBOutlet NSPanel *profilerPanel;
    IBOutlet NSPanel *woRegistersPanel;
    IBOutlet NSTableView *disassemblyTable;
    CalcDebugger *debugModel;
    ToggleToolbarItem *toggleBreakpointsToolbarItem;
    NSArray *toolbarIdList;
    NSArray *toolbarLabelList;
    NSArray *toolbarTooltipList;
    NSArray *toolbarImageList;
}
- (IBAction)cont:(id)sender;
- (IBAction)editBreakpoints:(id)sender;
- (IBAction)fullResetCalc:(id)sender;
- (IBAction)pauseDebug:(id)sender;
//- (IBAction)resetCalc:(id)sender;
- (IBAction)setBreakpoint:(id)sender;
- (IBAction)stepInto:(id)sender;
- (IBAction)stepOut:(id)sender;
- (IBAction)stepOver:(id)sender;
- (IBAction)showHistory:(id)sender;
- (IBAction)showProfiler:(id)sender;
- (IBAction)showWoRegisters:(id)sender;
- (IBAction)toggleBreakpoints:(id)sender;
- (IBAction)breakpointClicked:(id)sender;
- (IBAction)clearHistory:(id)sender;

- (CalcDebugger *)debugModel;
- (void)setDebugModel:(CalcDebugger *)aDebugModel;

// Toolbar support
- (void)setDebuggerToolbar;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag;
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar;
@end
