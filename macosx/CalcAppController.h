/*
 *  CalcAppController
 *  emu48
 *
 *  This is the application (NSApp) delegate class.
 *
 *  Created by Da Woon Jung on Sat Feb 21 2004.
 *  Copyright (c) 2004 dwj. All rights reserved.
 */

enum {
//    kCmdNewMemCard = 128,
//    kCmdOpenROM,
//    kCmdSaveObject,
//    kCmdSaveFlash,
//    kCmdShowDebugger,
    kCmdFullReset = 142
};

@class CalcBackend;
@class CalcDebugPanelController;
@class CalcDocumentController;
@class CalcPrefPanelController;
@class KmlLogController;


@interface CalcAppController : NSObject <NSApplicationDelegate>
{
//    CalcDebugger *debugger;
    IBOutlet NSMenu *newCalcMenu;
    IBOutlet NSMenu *kmlMenu;
    CalcDocumentController   *documentController;
    CalcPrefPanelController  *prefController;
    CalcDebugPanelController *debugger;
    KmlLogController *kmlLogController;
//    NSArray *filesToOpen;
}
- (IBAction)openROM:(id)sender;
- (IBAction)showDebugger:(id)sender;
- (IBAction)editBreakpoints:(id)sender;
- (IBAction)showHistory:(id)sender;
- (IBAction)showPrefs:(id)sender;
- (IBAction)showProfiler:(id)sender;
- (IBAction)showWoRegisters:(id)sender;
- (IBAction)turnOnCalc:(id)sender;

- (KmlLogController *)kmlLogController;
- (void)populateNewCalcMenu;
- (void)populateChangeKmlMenu;

- (void)reviewChangesAndQuitEnumeration:(NSNumber *)cont;
//- (void)reviewChangesAndOpenEnumeration:(NSNumber *)cont;
@end
