//
//  CalcDebugger.h
//  emu48
//
//  Created by Da Woon Jung on Thu Feb 19 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

#import "pch.h"
#import "EMU48.H"

@class CalcCheckBreakpointArgument;
@class CalcBreakpoint;


@interface CalcDebugger : NSObject
{
    CHIPSET OldChipset;
    DWORD dbgRefCycles;
    DWORD dbgRstkp;
    INT breakType;
    INT dbgOldState;
    BOOL breakpointsEnabled;
    DWORD disassemblyStartAddress;
    NSMutableArray *registers;
    NSMutableArray *memory;
    NSMutableArray *stack;
    NSMutableArray *breakpoints;
    NSMutableArray *history;
    NSDictionary   *profile;
    NSDictionary   *woRegisters;
    NSMutableDictionary *mmu;
    NSMutableDictionary *misc;
    NSMutableDictionary *regUpdated;
}
- (NSMutableArray *)disassembly;
- (void)setDisassembly:(NSMutableArray *)dummy;
- (void)setDisassemblyStartAddress:(DWORD)aDisassemblyStartAddress;
- (NSMutableArray *)registers;
- (void)setRegisters:(NSMutableArray *)aRegisters;
- (NSMutableArray *)memory;
- (void)setMemory:(NSMutableArray *)aMemory;
- (NSMutableArray *)stack;
- (void)setStack:(NSMutableArray *)aStack;
- (NSMutableArray *)breakpoints;
- (void)setBreakpoints:(NSMutableArray *)aBreakpoints;
- (NSMutableArray *)history;
- (void)setHistory:(NSMutableArray *)aHistory;
- (NSDictionary *)profile;
- (void)setProfile:(NSDictionary *)aProfile;
- (NSDictionary *)woRegisters;
- (void)setWoRegisters:(NSDictionary *)aWoRegisters;

- (void)stackDoubleClicked:(id)frame;

- (NSMutableDictionary *)regUpdated;

- (void)cont;
- (void)pause;
- (void)stepInto;
- (void)stepOut;
- (void)stepOver;
- (void)notifyPausedWithBreakType:(NSNumber *)aBreakType;
- (void)enableDebugger;
- (void)toggleBreakpoints;
#if 0
- (void)breakpointEnabled:(CalcCheckBreakpointArgument *)args;
#else
- (BOOL)breakpointEnabledAtAddress:(DWORD)dwAddr range:(DWORD)dwRange type:(UINT)nType;
#endif
- (void)updateDbgCycleCounter;
- (void)clearHistory;
- (void)setCodeAddress:(DWORD)address;
- (DWORD)getMemoryAddress;
- (void)setMemoryAddress:(DWORD)address;
@end


@interface CalcBreakpoint : NSObject
{
    BOOL enabled;
    NSNumber *address;
    int  type;
}
- (BOOL)isEqual:(id)anObject;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)value;
- (NSNumber *)address;
- (void)setAddress:(NSNumber *)value;
- (int)type;
- (void)setType:(int)value;
@end

@interface CalcCheckBreakpointArgument : NSObject
{
    DWORD address;
    DWORD range;
    UINT  type;
    BOOL  result;
}
- (id)initWithAddress:(DWORD)dwAddr range:(DWORD)dwRange type:(UINT)nType;
- (DWORD)address;
- (DWORD)range;
- (UINT)type;
- (BOOL)result;
- (void)setResult:(BOOL)value;
@end
