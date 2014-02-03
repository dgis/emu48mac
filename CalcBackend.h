//
//  CalcBackend.h
//  emu48
//
//  Created by Da Woon Jung on 2009-01-23
//  Copyright 2009 dwj. All rights reserved.
//

#import "kmlparser.h"

@class CalcEngine;
@class CalcTimer;
@class CalcState;
@class CalcView;
@class CalcDebugger;
@class CalcToneGenerator;


@interface CalcBackend : NSObject
{
    CalcView   *calcView;
    CalcEngine *engine;
    CalcTimer  *timer;
    CalcDebugger *debugModel;
    CalcToneGenerator *toneGenerator;

    CalcState *state;
    NSMutableArray *backups;
//    KmlParseResult *kml;
    // Keep pointers to avoid calling accessors every button/keypress
    KmlBlock **pVKey;
    KmlButton *pButton;
    unsigned nButtons;
    DWORD    nKMLFlags;
    unsigned char byVKeyMap[256];
    BOOL bClicking;
    BOOL bPressed;
    UINT uButtonClicked;
    UINT uLastPressedKey;
    KmlButton *drawingButton;

    BOOL initDone;
    BOOL isRunning;
}
+ (CalcBackend *)sharedBackend;
- (BOOL)makeUntitledCalcWithKml:(NSString *)aFilename error:(NSError **)outError;
- (void)changeKml:(id)sender;
- (void)run;
- (void)stop;
- (BOOL)isRunning;
- (NSString *)currentModel;

- (CalcTimer *)timer;
- (CalcView *)calcView;
- (void)setCalcView:(CalcView *)aView;
- (CalcDebugger *)debugModel;
- (void)playToneWithFrequency:(DWORD)freq duration:(DWORD)duration;
#if TARGET_OS_IPHONE
- (void)interruptToneWithState:(UInt32)aInterruptState;
#endif

- (KmlLine *)If:(KmlLine *)pLine condition:(BOOL)bCondition;
- (KmlLine *)RunLine:(KmlLine *)pLine;

- (void)mouseDownAt:(CalcPoint)aPoint;
- (void)rightMouseDownAt:(CalcPoint)aPoint;
- (void)mouseUpAt:(CalcPoint)aPoint;
- (void)runKey:(BYTE)nId pressed:(BOOL)aPressed;

- (BOOL)ClipButton:(CalcPoint)aPoint forId:(unsigned)nId;
- (void)DrawButton:(unsigned)nId;
- (void)PressButton:(unsigned)nId;
- (void)ReleaseButton:(unsigned)nId;
- (void)PressButtonById:(unsigned)nId;
- (void)ReleaseButtonById:(unsigned)nId;
- (void)ReleaseAllButtons;
- (BOOL)drawingButtonPressed;
- (UINT)drawingButtonType;
- (CalcRect)drawingButtonRect;
- (CalcRect)drawingButtonRectPressed;

- (void)onPowerKey;

- (BOOL)initDone;
- (void)setInitDone:(BOOL)aDone;

- (void)finishInitWithViewContainer:(CalcViewContainer *)aViewContainer
                           lcdClass:(Class)aLcdClass;

- (BOOL)readFromState:(NSString *)aStateFile error:(NSError **)outError;
- (BOOL)saveStateAs:(NSString *)aStateFile error:(NSError **)outError;

- (BOOL)readFromObject:(NSString *)aObjectFile error:(NSError **)outError DEPRECATED_ATTRIBUTE;
- (BOOL)readFromObjectURL:(NSURL *)aObjectURL error:(NSError **)outError;
- (BOOL)saveObjectAs:(NSString *)aObjectFile error:(NSError **)outError DEPRECATED_ATTRIBUTE;
- (BOOL)saveObjectAsURL:(NSURL *)aObjectURL error:(NSError **)outError;

- (void)backup;
- (void)restore;
@end
