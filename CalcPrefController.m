//
//  CalcPrefController.m
//  emu48
//
//  Created by Da-Woon Jung on Thu Feb 19 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//
#import "CalcPrefController.h"
#import "pch.h"
#import "EMU48.H"
#import "IO.H"
#import "files.h"
#import "kmlparser.h"
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 30000
#import <MobileCoreServices/MobileCoreServices.h>
#endif

@interface CalcPrefController(Private)
- (void)refreshPort1WithPluggedStatus:(BOOL)isPlugged writeable:(BOOL)isWriteable;
- (void)refreshPort2WithFilename:(NSString *)aFilename;
- (void)refreshCalculators:(id)aArg;
@end


@implementation CalcPrefController

- (id)init
{
    self = [super init];
    if (self)
    {
        calculators = [[NSMutableArray alloc] init];
        standardCalcs = [[[self class] calculatorsAtPath:CALC_RES_PATH relativeToPath:[[NSBundle mainBundle] resourcePath]] retain];
        if (standardCalcs)
        {
            NSEnumerator *standardCalcEnum = [standardCalcs objectEnumerator];
            NSNumber *readonly = [[NSNumber alloc] initWithBool: YES];
            id standardCalc;
            while ((standardCalc = [standardCalcEnum nextObject]))
                [standardCalc setObject:readonly forKey:@"readonly"];
            [readonly release];
//            [self setCalculators: standardCalcs];
        }
        [self refreshCalculators: nil];
    }
    return self;
}

- (void)dealloc
{
    [calculators release];
    [standardCalcs release];
    [super dealloc];
}

+ (void)registerDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults: [CalcPrefController cleanDefaults]];
}

+ (NSDictionary *)cleanDefaults
{
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"defaults" ofType:@"plist"];
    NSData *plistData = [[NSFileManager defaultManager] contentsAtPath:plistPath];
    NSDictionary *defaults = (NSDictionary *)[NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&errorDesc];
    return defaults;
}

+ (void)resetDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *cleanDefaults = [CalcPrefController cleanDefaults];
    NSEnumerator *keyEnum = [cleanDefaults keyEnumerator];
    NSString *key;
    while ((key = [keyEnum nextObject]))
    {
        [defaults setObject:[cleanDefaults objectForKey:key] forKey:key];
    }
}

/*
+ (NSDictionary *)volatileDefaults
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:NO],  @"Port1Plugged",
            [NSNumber numberWithBool:NO],  @"Port1Writeable",
            [NSNumber numberWithBool:NO],  @"Port1Enabled",
            [NSNumber numberWithBool:NO],  @"Port2Enabled",
            nil];
}
*/

- (int)DefaultCalculator
{
    return defaultCalculator;
}

- (void)setDefaultCalculator:(int)aIndex
{
    NSArray *allCalcs = [self calculators];
    int count = [allCalcs count]; 
    NSDictionary *calc;
    if (aIndex < count)
    {
        defaultCalculator = aIndex;
        calc = [allCalcs objectAtIndex: aIndex];
        [[NSUserDefaults standardUserDefaults] setObject:[calc objectForKey: @"path"] forKey: @"DefaultCalculator"];
    }
    else
    {
        defaultCalculator = 0;
        [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"DefaultCalculator"];
    }
}

#define USERDEFAULTS_ACCESSOR_BOOL(n)  -(BOOL)n{return [[NSUserDefaults standardUserDefaults] boolForKey:@#n];} \
    -(void)set##n:(BOOL)value{[[NSUserDefaults standardUserDefaults] setBool:value forKey:@#n];}

#define USERDEFAULTS_ACCESSOR_INT(n)   -(int)n{return [[NSUserDefaults standardUserDefaults] integerForKey:@#n];} \
    -(void)set##n:(int)value{[[NSUserDefaults standardUserDefaults] setInteger:value forKey:@#n];}

USERDEFAULTS_ACCESSOR_BOOL(RealSpeed)
USERDEFAULTS_ACCESSOR_BOOL(Grayscale)
USERDEFAULTS_ACCESSOR_BOOL(AlwaysOnTop)
USERDEFAULTS_ACCESSOR_BOOL(AutoSaveOnExit)
USERDEFAULTS_ACCESSOR_BOOL(ReloadFiles)
USERDEFAULTS_ACCESSOR_BOOL(LoadObjectWarning)
USERDEFAULTS_ACCESSOR_BOOL(AlwaysDisplayLog)
USERDEFAULTS_ACCESSOR_BOOL(RomWriteable)
USERDEFAULTS_ACCESSOR_INT(Mnemonics)
USERDEFAULTS_ACCESSOR_INT(WaveBeep)

- (float)WaveVolume { return [[NSUserDefaults standardUserDefaults] floatForKey: @"WaveVolume"]; }
- (void)setWaveVolume:(float)value { [[NSUserDefaults standardUserDefaults] setFloat:value forKey:@"WaveVolume"]; }

- (BOOL)Port1Plugged
{
    if (cCurrentRomType=='S' || cCurrentRomType=='G' || cCurrentRomType==0)
    {
        return ((Chipset.cards_status & PORT1_PRESENT) != 0);
    }
    return NO;
}
- (BOOL)Port1Writeable
{
    if (cCurrentRomType=='S' || cCurrentRomType=='G' || cCurrentRomType==0)
    {
        return ((Chipset.cards_status & PORT1_WRITE) != 0);
    }
    return NO;
}
- (BOOL)Port2IsShared
{
    return [[NSUserDefaults standardUserDefaults] boolForKey: @"Port2IsShared"];
}
- (NSString *)Port2Filename
{
    return [[NSUserDefaults standardUserDefaults] stringForKey: @"Port2Filename"];
}

- (BOOL)Port1Enabled
{
    if (cCurrentRomType=='S' || cCurrentRomType=='G' || cCurrentRomType==0)
    {
        if (nState != SM_INVALID)		// Invalid State
            return YES;
    }
    return NO;
}
- (BOOL)Port2Enabled
{
    if (cCurrentRomType=='S' || cCurrentRomType=='G' || cCurrentRomType==0)
    {
        return YES;
    }
    return NO;
}
- (void)setPort1Plugged:(BOOL)value
{
    [self refreshPort1WithPluggedStatus:value writeable:[self Port1Writeable]];
}
- (void)setPort1Writeable:(BOOL)value
{
    [self refreshPort1WithPluggedStatus:[self Port1Plugged] writeable:value];
}
- (void)setPort2IsShared:(BOOL)value
{
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"Port2IsShared"];
    [self refreshPort2WithFilename: [self Port2Filename]];
}
- (void)setPort2Filename:(NSString *)value
{
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"Port2Filename"];
    [self refreshPort2WithFilename: value];
}
- (void)setPort1Enabled:(BOOL)value
{
}
- (void)setPort2Enabled:(BOOL)value
{
}
- (void)refreshPort1WithPlugged:(BOOL)isPlugged writeable:(BOOL)isWriteable
{
    if (Chipset.Port1Size && (cCurrentRomType!='X' || cCurrentRomType!='2' || cCurrentRomType!='Q'))   // CdB for HP: add apples
    {
        UINT nOldState = SwitchToState(SM_SLEEP);
        // save old card status
        BYTE bCardsStatus = Chipset.cards_status;

        // port1 disabled?
        Chipset.cards_status &= ~(PORT1_PRESENT | PORT1_WRITE);
        if (isPlugged)
        {
            Chipset.cards_status |= PORT1_PRESENT;
            if (isWriteable)
                Chipset.cards_status |= PORT1_WRITE;
        }

        // changed card status in slot1?
        if (   ((bCardsStatus ^ Chipset.cards_status) & (PORT1_PRESENT | PORT1_WRITE)) != 0
            && (Chipset.IORam[CARDCTL] & ECDT) != 0 && (Chipset.IORam[TIMER2_CTRL] & RUN) != 0
            )
        {
            Chipset.HST |= MP;			// set Module Pulled
            IOBit(SRQ2,NINT,FALSE);		// set NINT to low
            Chipset.SoftInt = TRUE;		// set interrupt
            bInterrupt = TRUE;
        }
        SwitchToState(nOldState);
    }
}
- (void)refreshPort2WithFilename:(NSString *)aFilename
{
    UINT nOldState = SwitchToState(SM_INVALID);

    UnmapPort2();				// unmap port2

    if (cCurrentRomType)		// ROM defined
    {
        MapPort2([aFilename UTF8String]);

        // port2 changed and card detection enabled
        if (   (Chipset.wPort2Crc != wPort2Crc)
            && (Chipset.IORam[CARDCTL] & ECDT) != 0 && (Chipset.IORam[TIMER2_CTRL] & RUN) != 0
            )
        {
            Chipset.HST |= MP;		// set Module Pulled
            IOBit(SRQ2,NINT,FALSE);	// set NINT to low
            Chipset.SoftInt = TRUE;	// set interrupt
            bInterrupt = TRUE;
        }
        // save fingerprint of port2
        Chipset.wPort2Crc = wPort2Crc;
    }
    SwitchToState(nOldState);
}

+ (NSArray *)calculatorsAtPath:(NSString *)aCalcPath
                relativeToPath:(NSString *)base
{
    NSMutableArray *result = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isFolder = NO;
    NSString *calcPath = base ? [base stringByAppendingPathComponent: aCalcPath] : aCalcPath;
    if (![fm fileExistsAtPath:calcPath isDirectory:&isFolder] || !isFolder)
        return nil;
    NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath: calcPath];
    NSString *kmlFile;
    NSString *kmlExt = (NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)@"com.dw.emu48-kml", kUTTagClassFilenameExtension);
    if (nil==kmlExt)
        return nil;
    KmlParser *parser = [[KmlParser alloc] init];
    result = [NSMutableArray array];
    while ((kmlFile = [dirEnum nextObject]))
    {
        if (NSOrderedSame != [[kmlFile pathExtension] caseInsensitiveCompare: kmlExt])
            continue;
        NSString *kmlPath = [calcPath stringByAppendingPathComponent: kmlFile];
        KmlParseResult *kml = [parser LoadKMLGlobal: kmlPath];
        if (nil == kml) continue;
        NSString *title = [kml stringForBlockId:TOK_GLOBAL commandId:TOK_TITLE atIndex:0];
        if (nil == title)
            title = NSLocalizedString(@"Untitled", @"");
        NSString *author = [kml stringForBlockId:TOK_GLOBAL commandId:TOK_AUTHOR atIndex:0];
        if (nil == author)
            author = NSLocalizedString(@"<Unknown Author>", @"");
        NSString *model = [kml stringForBlockId:TOK_GLOBAL commandId:TOK_MODEL atIndex:0];
        if (nil == model)
            model = @"";
        NSString *imagePath = [kml stringForBlockId:TOK_GLOBAL commandId:TOK_BITMAP atIndex:0];

        NSMutableDictionary *calc = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     title,  @"title",
                                     author, @"author",
                                     model,  @"model",
                                     base ? [aCalcPath stringByAppendingPathComponent: kmlFile] : kmlPath, @"path",
                                     nil];
        if (imagePath && [imagePath length]>0)
        {
            [calc setObject:[calcPath stringByAppendingPathComponent: imagePath] forKey:@"imagePath"];
        }
        
        [result addObject: calc];
    }
    [parser release];
    [kmlExt release];
    return result;
}

- (NSMutableArray *)calculators
{
    return calculators;
}

- (void)setCalculators:(NSArray *)aCalculators
{
    [calculators setArray: aCalculators];
}

- (void)refreshCalculators:(id)aArg
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableArray *allCalcs = [NSMutableArray array];
    if (standardCalcs)
        [allCalcs addObjectsFromArray: standardCalcs];
    // First search user's home directory (create calc folder on first run)
    NSArray *systemPaths = NSSearchPathForDirectoriesInDomains(
#if TARGET_OS_IPHONE
        NSDocumentDirectory,
#else
        NSApplicationSupportDirectory,
#endif
        NSUserDomainMask, YES);
    NSString *calcPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isFolder = NO;
    if (systemPaths && [systemPaths count] > 0)
    {
        calcPath = [[[systemPaths objectAtIndex: 0] stringByAppendingPathComponent: CALC_USER_PATH] stringByAppendingPathComponent: CALC_RES_PATH];
        if (![fm fileExistsAtPath:calcPath isDirectory:&isFolder])
        {
            NSArray *pathComponents = [calcPath pathComponents];
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
            return;
        NSArray *userCalcs = [[self class] calculatorsAtPath:calcPath relativeToPath:nil];
        if (userCalcs && [userCalcs count]>0)
        {
            [allCalcs addObjectsFromArray: userCalcs];
        }
    }
#if !TARGET_OS_IPHONE
    // Add all calcs found in system directories too
    systemPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSLocalDomainMask | NSNetworkDomainMask, YES);
    NSEnumerator *dirEnum = [systemPaths objectEnumerator];
    while ((calcPath = [dirEnum nextObject]))
    {
        NSArray *userCalcs = [[self class] calculatorsAtPath:[[calcPath stringByAppendingPathComponent: CALC_USER_PATH] stringByAppendingPathComponent: CALC_RES_PATH] relativeToPath:nil];
        if (userCalcs && [userCalcs count]>0)
        {
            [allCalcs addObjectsFromArray: userCalcs];
        }
    }
#endif

    [self setCalculators: allCalcs];

    int result = 0;
    id path = [[NSUserDefaults standardUserDefaults] objectForKey: @"DefaultCalculator"];
    if (path && [path isKindOfClass: [NSString class]])
    {
        int i;
        int count = [allCalcs count];
        NSDictionary *calc;
        for (i = 0; i < count; ++i)
        {
            calc = [allCalcs objectAtIndex: i];
            if ([[calc objectForKey: @"path"] isEqualToString: path])
            {
                result = i;
                break;
            }
        }
    }
    defaultCalculator = result;

    [pool release];
}
@end
