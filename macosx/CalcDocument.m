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


@implementation CalcDocument

- (IBAction)backupCalc:(id)sender
{
    [[CalcBackend sharedBackend] backup];
}

- (IBAction)changeKmlDummy:(id)sender
{
}

- (IBAction)openObject:(id)sender
{
    int result;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setResolvesAliases: YES];
    [panel setAllowsMultipleSelection: NO];
    result = [panel runModal];
    if (result == NSOKButton)
    {
        NSError *err = nil;
        if (![[CalcBackend sharedBackend] readFromObjectURL:[panel URL] error:&err] && err)
            [self presentError: err];
    }
}

- (IBAction)restoreCalc:(id)sender
{
    [[CalcBackend sharedBackend] restore];
}

- (IBAction)saveObject:(id)sender
{
    int result;
    NSArray *types = [[NSDocumentController sharedDocumentController] fileExtensionsFromType: @"HP Stack Object"];
    if (types && 0==[types count]) types = nil;
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setAllowedFileTypes: types];
    [panel setCanSelectHiddenExtension: YES];
    result = [panel runModal];
    if (result == NSOKButton)
    {
        NSError *err = nil;
        if (![[CalcBackend sharedBackend] saveObjectAsURL:[panel URL] error:&err] && err)
            [self presentError: err];
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
    CalcBackend *backend = [CalcBackend sharedBackend];
    [backend stop];
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
    [backend performSelector:@selector(run) withObject:nil afterDelay:0.0];
    [self updateChangeCount: NSChangeDone];
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)aType error:(NSError **)outError
{
    BOOL result = NO;
    if ([aType isEqualToString: @"Emu48 State"])
    {
        [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] bundlePath]];
        result = [[CalcBackend sharedBackend] readFromState:[absoluteURL path] error:outError];
        if (result)
        {
            [[NSApp delegate] populateChangeKmlMenu];
        }
        else
        {
//            if (outError)
//                *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"State file could not be read because the associated calculator template file contains errors.",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"The chosen calculator template file contains errors.",@""), NSLocalizedFailureReasonErrorKey, nil]];
        }
        return result;
    }
  // TODO: check here
#warning TODO
    else if ([aType isEqualToString: @"KML File"] || [aType isEqualToString: @"com.dw.emu48-kml"])
    {
        result = [[CalcBackend sharedBackend] makeUntitledCalcWithKml: [absoluteURL path] error:outError];
        if (result)
        {
            [[NSApp delegate] populateChangeKmlMenu];
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
    if ([aType isEqualToString: @"Emu48 State"])
    {
        [[NSFileManager defaultManager] changeCurrentDirectoryPath: [[NSBundle mainBundle] bundlePath]];
        result = [[CalcBackend sharedBackend] saveStateAs:[absoluteURL path] error:outError];
        return result;
    }
    
    return [super writeToURL:absoluteURL ofType:aType error:outError];
}

- (BOOL)saveToURL:(NSURL *)absoluteURL ofType:(NSString *)aType forSaveOperation:(NSSaveOperationType)saveOperation error:(NSError **)outError
{
    BOOL result = [super saveToURL:absoluteURL ofType:aType forSaveOperation:saveOperation error:outError];
    if (result)
        [self updateChangeCount: NSChangeDone];
    return result;
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
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey: @"AutoSaveOnExit"])
    {
        BOOL shouldClose = YES;
        NSError *err = nil;
        NSURL *saveURL = [self fileURL];
        if (nil == saveURL)
        {
            saveURL = [[self class] defaultFileURL];
        }
        if (nil == saveURL)
        {
            err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil];
            shouldClose = NO;
        }
        else
        {
            shouldClose = [self saveToURL:saveURL ofType:@"Emu48 State" forSaveOperation:NSSaveOperation error:&err];
        }

        if (!shouldClose)
            [self presentError: err];

        if (delegate)
            objc_msgSend(delegate, shouldCloseSelector, self, shouldClose, contextInfo);
    }
    else
    {
        [super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
    }
}
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
        id doc = [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath: path] display:YES error:&err];
        if (nil == doc && err)
        {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setObject:[[NSString stringWithFormat: NSLocalizedString(@"The document “%@” could not be opened.",@""), [path lastPathComponent]] stringByAppendingFormat: @" %@", [err localizedFailureReason]] forKey:NSLocalizedDescriptionKey];

            [userInfo setObject:[err localizedFailureReason]
                         forKey:NSLocalizedFailureReasonErrorKey];

            NSError *untitledDocError = [NSError errorWithDomain:[err domain] code:[err code] userInfo:userInfo];
            [self presentError: untitledDocError];
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
        if ([type isEqualToString: @"KML File"])
        {
            [doc setFileURL: nil];
            [doc setFileModificationDate: nil];
        }
    }

    return doc;
}

- (void)noteNewRecentDocument:(NSDocument *)aDocument
{
    NSString *type = [aDocument fileType];
    if ([type isEqualToString: @"Emu48 State"])
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
