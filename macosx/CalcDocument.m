//
//  CalcDocument.m
//  emu48mac
//
//  Created by Da Woon Jung on Wed Feb 18 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

#import "CalcDocument.h"
#import "CalcAppController.h"
#import "CalcPrefController.h"
#import "CalcBackend.h"
#import "CalcView.h"
#import "rawlcd.h"
#import "engine.h"
#import "EMU48.H"
#import <objc/message.h>

@implementation CalcDocument {
    bool mustClose;
}

- (IBAction)backupCalc:(id)sender
{
    [[CalcBackend sharedBackend] backup];
}

- (IBAction)changeKmlDummy:(id)sender
{
}

- (void)openObjectCore
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setResolvesAliases: YES];
    [panel setAllowsMultipleSelection: NO];
    NSInteger result = [panel runModal];
    if (result == NSModalResponseOK)
    {
        NSError *err = nil;
        if (![[CalcBackend sharedBackend] readFromObjectURL:[panel URL] error:&err] && err)
            [self presentError: err];
    }
}

- (IBAction)openObject:(id)sender
{
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"LoadObjectWarning"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setInformativeText:@"Warning: Trying to load an object while the emulator is busy will certainly result in a memory lost. Before loading an object you should be sure that the calculator is not doing anything.\n"
         @"Do you want to see this warning next time you try to load an object ?"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert addButtonWithTitle:@"No"];
        [alert addButtonWithTitle:@"Yes"];
        [alert setAlertStyle:NSAlertStyleWarning];
        NSModalResponse returnCode = [alert runModal];
        if (returnCode == NSAlertFirstButtonReturn)
            return;
        else if(returnCode == NSAlertSecondButtonReturn)
            [[NSUserDefaults standardUserDefaults] setBool:false forKey:@"LoadObjectWarning"];
    }
    [self openObjectCore];
}

- (IBAction)restoreCalc:(id)sender
{
    [[CalcBackend sharedBackend] restore];
}

- (IBAction)saveObject:(id)sender
{
    int result;
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes: @[@"com.dw.emu48-stack"]];
    [panel setCanSelectHiddenExtension: YES];
    result = (int)[panel runModal];
    if (result == NSModalResponseOK)
    {
        NSError *err = nil;
        if (![[CalcBackend sharedBackend] saveObjectAsURL:[panel URL] error:&err] && err)
            [self presentError: err];
    }
}

- (IBAction)resetCalc:(id)sender
{
    if (nState != SM_RUN)
        return;
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setInformativeText:@"Are you sure you want to press the Reset Button ?"];
    [alert addButtonWithTitle:@"No"];
    [alert addButtonWithTitle:@"Yes"];
    [alert setAlertStyle:NSAlertStyleWarning];
    if ([alert runModal] == NSAlertSecondButtonReturn)
    {
        SwitchToState(SM_SLEEP);
        CpuReset();                            // register setting after Cpu Reset
        SwitchToState(SM_RUN);
    }
}

- (id)init
{
    self = [super init];
    if (self)
    {
        [self setHasUndoManager: NO];
    }
    return self;
}

- (void)dealloc
{
    [[CalcBackend sharedBackend] stop];
    [super dealloc];
}


- (NSString *)windowNibName
{
    return @"CalcWindow";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib: controller];
    CalcBackend *backend = [CalcBackend sharedBackend];
    [backend setCalcView: calcView];
    [backend finishInitWithViewContainer:[controller window]
                                lcdClass:[CalcRawLCD class]];
    //[backend performSelector:@selector(run) withObject:nil afterDelay:10.0];
    [backend run];
    [self updateChangeCount: NSChangeDone];
    
    NSWindow * window = [calcView window];
    if(window) {
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"AlwaysOnTop"])
            [window setLevel:NSFloatingWindowLevel];
        else
            [window setLevel:NSNormalWindowLevel];
    
        if(Chipset.nPosX == 0 && Chipset.nPosY == 0) {
            [window center];
        } else {
            NSPoint pos;
            pos.x = Chipset.nPosX;
            pos.y = Chipset.nPosY;
            [window setFrameOrigin:pos];
        }
    }
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)aType error:(NSError **)outError
{
    // Needed for the revert!!! SwitchToState(SM_INVALID);
    BOOL result = NO;
    if ([aType hasPrefix: @"com.dw.emu48-state"])
    {
        [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] bundlePath]];
        result = [[CalcBackend sharedBackend] readFromState:[absoluteURL path] error:outError];
        if (result)
        {
            CalcAppController * appDelegate = [NSApp delegate];
            [appDelegate populateChangeKmlMenu];
        }
        else
        {
//            if (outError)
//                *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"State file could not be read because the associated calculator template file contains errors.",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"The chosen calculator template file contains errors.",@""), NSLocalizedFailureReasonErrorKey, nil]];
        }
        return result;
    }
    else if ([aType isEqualToString: @"com.dw.emu48-kml"])
    {
        result = [[CalcBackend sharedBackend] makeUntitledCalcWithKml: [absoluteURL path] error:outError];
        if (result)
        {
            CalcAppController * appDelegate = [NSApp delegate];
            [appDelegate populateChangeKmlMenu];
        }
        else
        {
//            if (outError)
//                *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Calculator template file could not be read because it contained error(s).",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"The chosen calculator template file contains errors.",@""), NSLocalizedFailureReasonErrorKey, nil]];
        }
        return result;
    }

    // Default action for other types
    return [super readFromURL:absoluteURL ofType:aType error:outError];
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)aType error:(NSError **)outError
{
    BOOL result = NO;
    if ([aType hasPrefix: @"com.dw.emu48-state"])
    {
        NSWindow * window = [calcView window];
        if(window) {
            Chipset.nPosX = window.frame.origin.x;
            Chipset.nPosY = window.frame.origin.y;
        }
        [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] bundlePath]];
        result = [[CalcBackend sharedBackend] saveStateAs:[absoluteURL path] error:outError];
        return result;
    }
    return result;
    //return [super writeToURL:absoluteURL ofType:aType error:outError];
}

//- (BOOL)saveToURL:(NSURL *)absoluteURL ofType:(NSString *)aType forSaveOperation:(NSSaveOperationType)saveOperation error:(NSError **)outError
//{
//    BOOL result = [super saveToURL:absoluteURL ofType:aType forSaveOperation:saveOperation error:outError];
//    if (result)
//        [self updateChangeCount: NSChangeDone];
//    return result;
//}

- (void)saveToURL:(NSURL *)absoluteURL ofType:(NSString *)aType forSaveOperation:(NSSaveOperationType)saveOperation completionHandler:(void (^)(NSError *errorOrNil))completionHandler
{
    [super saveToURL:absoluteURL ofType:aType forSaveOperation:saveOperation completionHandler:^(NSError *errorOrNil) {
        if (errorOrNil == nil) {
            [self updateChangeCount: NSChangeDone];
            if(self->mustClose) {
                [[CalcBackend sharedBackend] stop];
                [self close];
            }
        }
        self->mustClose = false;
        if(completionHandler)
            completionHandler(errorOrNil);
    }];
}

+ (NSURL *)defaultFileURL
{
    NSArray *systemPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (systemPaths && [systemPaths count] > 0)
    {
        NSString *statePath = [[[systemPaths objectAtIndex: 0] stringByAppendingPathComponent: CALC_USER_PATH] stringByAppendingPathComponent: CALC_STATE_PATH];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isFolder = NO;
        if (![fm fileExistsAtPath:statePath isDirectory:&isFolder])
        {
            NSArray *pathComponents = [statePath pathComponents];
            NSString *parentPath = @"";
            NSString *pathComp;
            NSEnumerator *pathEnum = [pathComponents objectEnumerator];
            while ((pathComp = [pathEnum nextObject]))
            {
                parentPath = [parentPath stringByAppendingPathComponent: pathComp];
                if (![fm fileExistsAtPath:parentPath isDirectory:&isFolder])
                {
                    NSError *error = nil;
                    [fm createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error];
                    if (error)
                        NSLog(@"%@", [error localizedDescription]);
                }
            }
        }
        else if (!isFolder)
        {
            return nil;
        }
        statePath = [statePath stringByAppendingPathComponent: CALC_DEFAULT_STATE];
        return [NSURL fileURLWithPath: statePath];
    }
    return nil;
}

// Support saving to a fixed file on exit
- (void)canCloseDocumentWithDelegate:(id)delegate
                 shouldCloseSelector:(SEL)shouldCloseSelector
                         contextInfo:(void *)contextInfo
{
    void (*callback)(id, SEL, NSDocument *, BOOL, void *) = (void (*)(id, SEL, NSDocument *, BOOL, void *))objc_msgSend;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey: @"AutoSaveOnExit"])
    {
        //BOOL shouldClose = YES;
        NSError *err = nil;
        NSURL *saveURL = [self fileURL];
        if (nil == saveURL)
        {
            saveURL = [[self class] defaultFileURL];
        }
        if (nil == saveURL)
        {
            err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil];
            //shouldClose = NO;
            [self presentError: err];
            if (delegate)
                //objc_msgSend(delegate, shouldCloseSelector, self, NO, contextInfo);
                (callback)(delegate, shouldCloseSelector, self, NO, contextInfo);
        }
        else
        {
            //NSString * currentModel = [[CalcBackend sharedBackend] currentModel];
            //[currentModel isEqualToString:@"6"]
            NSString * fileType = @"com.dw.emu48-state-e48"; // HP48SX/GX
            if (cCurrentRomType=='6' || cCurrentRomType=='A') // HP38G
                fileType = @"com.dw.emu48-state-e38";
            if (cCurrentRomType=='E')                // HP39/40G
                fileType = @"com.dw.emu48-state-e39";
            if (cCurrentRomType=='X')                // HP49G
                fileType = @"com.dw.emu48-state-e49";

            //shouldClose = [self saveToURL:saveURL ofType:@"Emu48 State" forSaveOperation:NSSaveOperation error:&err];
            [self saveToURL:saveURL ofType:fileType forSaveOperation:NSSaveOperation completionHandler:^(NSError *errorOrNil) {
                if (errorOrNil == nil) {
                    if (delegate)
                        //objc_msgSend(delegate, shouldCloseSelector, self, YES, contextInfo);
                        (callback)(delegate, shouldCloseSelector, self, YES, contextInfo);
                } else {
                    [self presentError: err];
                    if (delegate)
                        //objc_msgSend(delegate, shouldCloseSelector, self, NO, contextInfo);
                        (callback)(delegate, shouldCloseSelector, self, NO, contextInfo);
                }
            }];
            return;
        }

//        if (!shouldClose)
//            [self presentError: err];
//
//        if (delegate)
//            objc_msgSend(delegate, shouldCloseSelector, self, shouldClose, contextInfo);
    }
    else
    {
        self->mustClose = true;
        [super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
//        if (delegate)
//            //objc_msgSend(delegate, shouldCloseSelector, self, NO, contextInfo);
//            (callback)(delegate, shouldCloseSelector, self, YES, contextInfo);
//        [super canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:contextInfo];
    }
}

//- (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
//{
//    if(shouldClose) {
//        //[self updateChangeCount: NSChangeDone];
//        //[self updateChangeCount: NSChangeCleared];
//        //SwitchToState(SM_INVALID);
//        CalcBackend *backend = [CalcBackend sharedBackend];
//        [backend stop];
//        [self close];
//    }
//}

@end


@implementation CalcDocumentController

// Overriding newDocument: to implement new document from stationery
- (IBAction)newDocument:(id)sender
{
    NSString *path = nil;
    NSError *err = nil;
    if ([sender respondsToSelector: @selector(representedObject)])
    {
        path = [sender representedObject];
    }
    if (path)
    {
        CalcDocument * doc = [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath: path] display:YES error:&err];
        //id doc = [self makeUntitledDocumentOfType:@"com.dw.emu48-state" error:&err];
        if (nil == doc && err)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setObject:[[NSString stringWithFormat: NSLocalizedString(@"The document “%@” could not be opened.",@""), [path lastPathComponent]] stringByAppendingFormat: @" %@", [err localizedFailureReason]] forKey:NSLocalizedDescriptionKey];

            [userInfo setObject:[err localizedFailureReason]
                         forKey:NSLocalizedFailureReasonErrorKey];

            NSError *untitledDocError = [NSError errorWithDomain:[err domain] code:[err code] userInfo:userInfo];
            [self presentError: untitledDocError];
        }
        if(doc) {
            NSString * fileType = @"com.dw.emu48-state-e48"; // HP48SX/GX
            if (cCurrentRomType=='6' || cCurrentRomType=='A') // HP38G
                fileType = @"com.dw.emu48-state-e38";
            if (cCurrentRomType=='E')                // HP39/40G
                fileType = @"com.dw.emu48-state-e39";
            if (cCurrentRomType=='X')                // HP49G
                fileType = @"com.dw.emu48-state-e49";
            doc.fileType = fileType;
        }
    }
}

- (id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)aOutError
{
    NSError *outError = nil;
    id doc = [super openDocumentWithContentsOfURL:absoluteURL display:displayDocument error:&outError];
    if (aOutError)
        *aOutError = outError;

    if (doc)
    {
        NSString *type = [doc fileType];
        if ([type isEqualToString: @"com.dw.emu48-kml"])
        {
            [doc setFileURL: nil];
            [doc setFileModificationDate: nil];
        }
    }

    return doc;
}


//// Overriding newDocument: to implement new document from stationery
//- (IBAction)newDocument:(id)sender
//{
//    NSString *path = nil;
//    if ([sender respondsToSelector: @selector(representedObject)])
//    {
//        path = [sender representedObject];
//    }
//    if (path)
//    {
//        //CalcDocument * doc = [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath: path] display:YES error:&err];
//        //id doc = [self makeUntitledDocumentOfType:@"com.dw.emu48-state" error:&err];
//        [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath: path] display:YES completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *err) {
//            if (nil == document && err)
//            {
//                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
//                [userInfo setObject:[[NSString stringWithFormat: NSLocalizedString(@"The document “%@” could not be opened.",@""), [path lastPathComponent]] stringByAppendingFormat: @" %@", [err localizedFailureReason]] forKey:NSLocalizedDescriptionKey];
//
//                [userInfo setObject:[err localizedFailureReason]
//                             forKey:NSLocalizedFailureReasonErrorKey];
//
//                NSError *untitledDocError = [NSError errorWithDomain:[err domain] code:[err code] userInfo:userInfo];
//                [self presentError: untitledDocError];
//            }
//            if(document) {
//                NSString * fileType = @"com.dw.emu48-state-e48"; // HP48SX/GX
//                if (cCurrentRomType=='6' || cCurrentRomType=='A') // HP38G
//                    fileType = @"com.dw.emu48-state-e38";
//                if (cCurrentRomType=='E')                // HP39/40G
//                    fileType = @"com.dw.emu48-state-e39";
//                if (cCurrentRomType=='X')                // HP49G
//                    fileType = @"com.dw.emu48-state-e49";
//                document.fileType = fileType;
//            }
//        }];
//    }
//}
//
//
////- (void)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument completionHandler:(void (^)(NSDocument * _Nullable, BOOL, NSError * _Nullable))completionHandler
//- (void)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument
//                    completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler;
////- (id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)aOutError
//{
//    //SwitchToState(SM_INVALID);
//
//    if([[self documents] count] > 0) {
//        // Only one document is allowed
//        CalcDocument * openedDocument = [[self documents] objectAtIndex:0];
//        if(openedDocument) {
//            [openedDocument canCloseDocumentWithDelegate:self shouldCloseSelector:nil contextInfo:nil];
//            //SEL newCalcAction = @selector(newDocument:);
//
//        }
//    } else
//        [self internalOpenDocumentWithContentsOfURL:absoluteURL display:displayDocument completionHandler:completionHandler];
//}
//
////- (id)internalOpenDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)aOutError
//- (void)internalOpenDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument
//                            completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler
//{
////    NSError *outError = nil;
////    id doc = [super openDocumentWithContentsOfURL:absoluteURL display:displayDocument error:&outError];
////    if (aOutError)
////        *aOutError = outError;
//    [super openDocumentWithContentsOfURL:absoluteURL display:displayDocument completionHandler:^(NSDocument *doc, BOOL documentWasAlreadyOpen, NSError *error) {
//        if (doc)
//        {
//            NSString *type = [doc fileType];
//            if ([type isEqualToString: @"com.dw.emu48-kml"])
//            {
//                [doc setFileURL: nil];
//                [doc setFileModificationDate: nil];
//            }
//        }
//    }];
//}

- (void)noteNewRecentDocument:(NSDocument *)aDocument
{
    NSString *type = [aDocument fileType];
    if ([type hasPrefix: @"com.dw.emu48-state"])
    {
        [super noteNewRecentDocument: aDocument];
    }
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
    // TODO: Don't use hack for dimming recent items
    if ([anItem action] == @selector(newDocument:)  ||
        [anItem action] == @selector(openDocument:) ||
        [anItem action] == @selector(_openRecentDocument:))
    {
        return ([[self documents] count] < 1);
    }
    return [super validateUserInterfaceItem: anItem];
}
@end
