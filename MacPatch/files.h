//
//  files.h
//  emu48
//
//  Created by Da-Woon Jung on 2009-03-27.
//  Copyright (c) 2009 dwj. All rights reserved.
//
#import "MacTypePatch.h"
#import "TYPES.H"
#import "kmlparser.h"

typedef struct tnode
{
    BOOL   bPatch;							// TRUE = ROM address patched
    DWORD  dwAddress;						// patch address
    BYTE   byROM;							// original ROM value
    BYTE   byPatch;							// patched ROM value
    struct tnode *next;						// next node
} TREENODE;

extern BOOL NewPort2(NSString *filename, int numBlocks);
extern BOOL IsDataPacked(VOID *pMem, DWORD dwSize);

@interface CalcState : NSObject
{
    KmlParseResult *kml;
}
- (id)initWithKml:(NSString *)kmlPath error:(NSError **)outError;
- (id)initWithFile:(NSString *)aStateFile error:(NSError **)outError;
- (BOOL)setKmlFile:(NSString *)kmlPath error:(NSError **)outError;
- (BOOL)setKmlFileWithStop:(NSString *)aFilename error:(NSError **)outError;
- (BOOL)saveAs:(NSString *)aStateFile error:(NSError **)outError;
- (KmlParseResult *)kml;
@end

@interface CalcBackup : NSObject
{
    CHIPSET backupChipset;
    NSString *backupKmlPath;
}
- (id)initWithState:(CalcState *)aState;
- (BOOL)restoreToState:(CalcState *)aState;
@end
