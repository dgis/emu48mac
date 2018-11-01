//
//  CalcPrefPanelController.h
//  emu48
//
//  Created by Da-Woon Jung on 2009-09-04.
//  Copyright 2009 dwj. All rights reserved.
//

@class CalcPrefController;

@interface CalcPrefPanelController : NSWindowController<NSWindowDelegate, NSToolbarDelegate>
{
    IBOutlet NSView *startupView;
    IBOutlet NSView *calculatorsView;
    IBOutlet NSView *settingsView;
    IBOutlet NSView *cardSizeView;
    IBOutlet NSPopUpButton *cardSizePopup;
    IBOutlet CalcPrefController *prefModel;
    NSDictionary *views;
    NSArray *allIdentifiers;
    NSString *selectedIdentifier;
}
- (IBAction)prefBrowsePort2File:(id)sender;
- (IBAction)prefMakeCalculatorDefault:(id)sender;
- (IBAction)prefNewPort2File:(id)sender;
- (IBAction)prefReset:(id)sender;

- (CalcPrefController *)prefModel;
- (void)switchToViewWithIdentifier:(NSString *)aIdentifier;
@end
