//
//  CalcPrefController
//  emu48
//
//  Created by Da-Woon Jung on Thu Feb 19 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

#define CALC_RES_PATH       @"Calculators"
#define CALC_USER_PATH      @"Emu48"
#define CALC_STATE_PATH     @"States"
#define CALC_DEFAULT_STATE  @"state.e48"

enum {
    kHPMnemonics, kClassMnemonics
};

enum {
    kBeepSystem, kBeepWave
};


@interface CalcPrefController : NSObject
{
    NSArray *standardCalcs;
    NSMutableArray *calculators;
    int defaultCalculator;
}
+ (void)registerDefaults;
+ (NSDictionary *)cleanDefaults;
+ (void)resetDefaults;

- (int)DefaultCalculator;
- (void)setDefaultCalculator:(int)aIndex;

- (BOOL)RealSpeed;
- (BOOL)Grayscale;
- (BOOL)AlwaysOnTop;
- (BOOL)AutoSaveOnExit;
- (BOOL)ReloadFiles;
- (BOOL)LoadObjectWarning;
- (BOOL)AlwaysDisplayLog;
- (BOOL)RomWriteable;
- (int)Mnemonics;
- (int)WaveBeep;
- (float)WaveVolume;
- (void)setRealSpeed:(BOOL)value;
- (void)setGrayscale:(BOOL)value;
- (void)setAlwaysOnTop:(BOOL)value;
- (void)setAutoSaveOnExit:(BOOL)value;
- (void)setReloadFiles:(BOOL)value;
- (void)setLoadObjectWarning:(BOOL)value;
- (void)setAlwaysDisplayLog:(BOOL)value;
- (void)setRomWriteable:(BOOL)value;
- (void)setMnemonics:(int)value;
- (void)setWaveBeep:(int)value;
- (void)setWaveVolume:(float)value;

- (BOOL)Port1Plugged;
- (BOOL)Port1Writeable;
- (BOOL)Port2IsShared;
- (NSString *)Port2Filename;
- (BOOL)Port1Enabled;
- (BOOL)Port2Enabled;
- (void)setPort1Plugged:(BOOL)value;
- (void)setPort1Writeable:(BOOL)value;
- (void)setPort2IsShared:(BOOL)value;
- (void)setPort2Filename:(NSString *)value;
- (void)setPort1Enabled:(BOOL)value;
- (void)setPort2Enabled:(BOOL)value;

+ (NSArray *)calculatorsAtPath:(NSString *)aPath
                relativeToPath:(NSString *)base;
- (NSMutableArray *)calculators;
- (void)setCalculators:(NSArray *)aCalculators;
- (void)refreshCalculators:(id)aArg;
@end
