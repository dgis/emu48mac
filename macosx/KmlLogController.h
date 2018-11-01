/*
 *  KmlLogController.h
 *  emu48
 *
 *  Created by Da Woon Jung on 2009-01-21.
 *  Copyright (c) 2009 dwj. All rights reserved.
 *
 */

#import <Cocoa/Cocoa.h>

@interface KmlLogController : NSWindowController<NSToolbarDelegate>
{
//    IBOutlet NSTextField *kmlAuthor;
    IBOutlet NSTextView *kmlLog;
//    IBOutlet NSTextField *kmlTitle;
}
//- (void)setTitle:  (NSString *)aTitle;
//- (void)setAuthor: (NSString *)aAuthor;
- (void)clearLog:(id)aSender;
- (void)appendLog: (NSString *)aLogmsg;
@end
