//
//  CalcDocument.h
//  emu48mac
//
//  Created by Da Woon Jung on Wed Feb 18 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

@class CalcView;

@interface CalcDocument : NSDocument
{
    IBOutlet CalcView *calcView;
}
- (IBAction)backupCalc:(id)sender;
- (IBAction)changeKmlDummy:(id)sender;
- (IBAction)openObject:(id)sender;
- (IBAction)restoreCalc:(id)sender;
- (IBAction)saveObject:(id)sender;
- (IBAction)resetCalc:(id)sender;
@end


// Subclassing NSDocumentController to get only-one-document-open-at-a-time functionality
@interface CalcDocumentController : NSDocumentController
@end
