//
//  CalcDebugger.m
//  emu48
//
//  Created by Da Woon Jung on Thu Feb 19 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//
#import "CalcDebugger.h"
#import "DEBUGGER.H"
#import "OPS.H"
#import "CalcBackend.h"

//#define MAXCODELINES     15                    // number of lines in code window
#define MAXCODELINES     22                    // number of lines in code window
#define MAXMEMLINES       6					// number of lines in memory window
#define MAXMEMITEMS      16					// number of address items in a memory window line
#define MAXBREAKPOINTS  256					// max. number of breakpoints
#define MAXREGISTERS     22
#define INSTRSIZE  256						// size of last instruction buffer

static const char cHex[] =
{ '0','1','2','3',
  '4','5','6','7',
  '8','9','A','B',
  'C','D','E','F' };

static NSString *RegToStr(BYTE *pReg, WORD wNib)
{
	char szBuffer[32];

	WORD i;

	for (i = 0;i < wNib;++i)
		szBuffer[i] = cHex[pReg[wNib-i-1]];
	szBuffer[i] = 0;

	return [NSString stringWithUTF8String: szBuffer];
}


@interface CalcDebugger(Private)
- (void)setRegUpdated:(BOOL)aUpdated forReg:(NSString *)aRegName;
- (void)UpdateDisassemblyAtAddress:(DWORD)addr;
- (void)UpdateRegisters;
- (void)UpdateMemory;
- (void)UpdateStack;
- (void)UpdateHistory;
- (void)UpdateMmu;
- (void)UpdateMisc;
- (void)UpdateProfile;
- (void)UpdateWoRegisters;
- (void)update;
- (void)updateExceptDisassembly;
- (int)checkBreakpointAtAddress:(DWORD)dwAddr range:(DWORD)dwRange type:(UINT)nType;
@end


@implementation CalcDebugger{
    DWORD  dwAdrMem;
}

#if TARGET_OS_IPHONE || (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5)
+ (NSSet *)keyPathsForValuesAffectingDisassembly
{
    return [NSSet setWithObject: @"breakpoints"];
}
#else
+ (void)initialize
{
    [self setKeys:[NSArray arrayWithObject: @"breakpoints"] triggerChangeNotificationsForDependentKey:@"disassembly"];

//    [self setKeys:[NSArray arrayWithObject: @"disassembly"] triggerChangeNotificationsForDependentKey:@"breakpoints"];
    ;
}
#endif

- (id)init
{
    self = [super init];
    if (self)
    {
//        disassembly = [[NSMutableArray alloc] init];
        registers   = [[NSMutableArray alloc] init];
        memory      = [[NSMutableArray alloc] init];
        stack       = [[NSMutableArray alloc] init];
        breakpoints = [[NSMutableArray alloc] init];
        history     = [[NSMutableArray alloc] init];
//        profile     = [[NSDictionary alloc] init];
        mmu         = [[NSMutableDictionary alloc] init];
        misc        = [[NSMutableDictionary alloc] init];
        regUpdated  = [[NSMutableDictionary alloc] init];
        dbgOldState = DBG_RUN;
        breakpointsEnabled = YES;
        dwAdrMem = 0;
    }
    return self;
}

- (void)dealloc
{
    DisableDebugger();
    [regUpdated release];
    [misc release];
    [mmu release];
    [breakpoints release];
    [history release];
    [profile release];
    [woRegisters release];
    if (pdwInstrArray)					// free last instruction circular buffer
    {
        HeapFree(hHeap,0,pdwInstrArray);
        pdwInstrArray = NULL;
    }
    [stack release];
    [memory release];
    [registers release];
//    [disassembly release];
    [super dealloc];
}

- (NSMutableArray *)disassembly
{
    DWORD addr = disassemblyStartAddress;
    int i, j;
	char szAddress[64];
    int breakpointStatus = -1;
    NSMutableDictionary *codeLine;
    
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity: MAXCODELINES];
    
	for (i = 0; i < MAXCODELINES; ++i)
	{
		j = sprintf(szAddress,
                    (addr == Chipset.pc) ? "%05X-%c " : "%05X   ",
                    addr,breakType ? 'R' : '>');
        breakpointStatus = [self checkBreakpointAtAddress:addr range:1 type:BP_EXEC];
		addr = disassemble(addr,&szAddress[j],VIEW_SHORT);
        codeLine = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                    [NSNumber numberWithInt: breakpointStatus], @"breakpointStatus",
                    [NSString stringWithUTF8String: szAddress], @"code",
                    nil];
        [result addObject: codeLine];
        [codeLine release];
	}

//    [disassembly release];
//    disassembly = result;
    return [result autorelease]; //disassembly;
}
- (void)setDisassembly:(NSMutableArray *)dummy
{
//    [disassembly release];
//    disassembly = [aDissassembly retain];
}
- (void)setDisassemblyStartAddress:(DWORD)aDisassemblyStartAddress
{
    disassemblyStartAddress = aDisassemblyStartAddress;
}
- (NSMutableArray *)registers
{
    return registers;
}
- (void)setRegisters:(NSMutableArray *)aRegisters
{
    [registers release];
    registers = [aRegisters retain];
}
- (NSMutableArray *)memory
{
    return memory;
}
- (void)setMemory:(NSMutableArray *)aMemory
{
    [memory release];
    memory = [aMemory retain];
}
- (NSMutableArray *)stack
{
    return stack;
}
- (void)setStack:(NSMutableArray *)aStack
{
    [stack release];
    stack = [aStack retain];
}
- (NSMutableArray *)breakpoints
{
    return breakpoints;
}
- (void)setBreakpoints:(NSMutableArray *)aBreakpoints
{
    [breakpoints release];
    breakpoints = [aBreakpoints retain];
}
- (NSMutableArray *)history
{
    return history;
}
- (void)setHistory:(NSMutableArray *)aHistory
{
    [history release];
    history = [aHistory retain];
}
- (NSDictionary *)profile
{
    return profile;
}
- (void)setProfile:(NSDictionary *)aProfile
{
    [profile release];
    profile = [aProfile retain];
}
- (NSDictionary *)woRegisters
{
    return woRegisters;
}
- (void)setWoRegisters:(NSDictionary *)aWoRegisters
{
    [woRegisters release];
    woRegisters = [aWoRegisters retain];
}

- (void)stackDoubleClicked:(id)frame
{
    DWORD addr = [frame unsignedIntValue];
    [self UpdateDisassemblyAtAddress: addr];
}

- (void)UpdateDisassemblyAtAddress:(DWORD)addr
{
    [self setDisassemblyStartAddress: addr];
    [self setDisassembly: nil];
}

- (void)UpdateRegisters
{
    NSString *buf = @"";
    BOOL isUpdated = NO;
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity: MAXREGISTERS];
#if !TARGET_OS_IPHONE
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
#endif

#if TARGET_OS_IPHONE
    #define RegAddStr(s)    [result addObject:s]
#else
    #define RegAddStr(s)    [result addObject:[[[NSAttributedString alloc] initWithString:s attributes:(isUpdated?attributes:nil)] autorelease]]
#endif

#define RegCaseMem(x,f,w)  isUpdated=memcmp(x,Old##x,sizeof(x))!=0;\
    buf=[NSString stringWithFormat:f,RegToStr(x,w)];\
    RegAddStr(buf)
#define RegCaseVal(x,f)    isUpdated=x!=Old##x;\
    buf=[NSString stringWithFormat:f,x];\
    RegAddStr(buf)
#define RegCaseBit(x)      isUpdated=((Chipset.HST^OldChipset.HST)&x)!=0;\
    buf=[NSString stringWithFormat:@"%s=%d",#x,(Chipset.HST&x)!=0];\
    RegAddStr(buf)

    RegCaseMem(Chipset.A,@"A= %@",16);
    RegCaseMem(Chipset.B,@"B= %@",16);
    RegCaseMem(Chipset.C,@"C= %@",16);
    RegCaseMem(Chipset.D,@"D= %@",16);
    RegCaseMem(Chipset.R0,@"R0=%@",16);
    RegCaseMem(Chipset.R1,@"R1=%@",16);
    RegCaseMem(Chipset.R2,@"R2=%@",16);
    RegCaseMem(Chipset.R3,@"R3=%@",16);
    RegCaseMem(Chipset.R4,@"R4=%@",16);
    RegCaseVal(Chipset.d0,@"D0=%05X");
    RegCaseVal(Chipset.d1,@"D1=%05X");
    RegCaseVal(Chipset.P,@"P=%X");
    RegCaseVal(Chipset.pc,@"PC=%05X");
    RegCaseVal(Chipset.out,@"OUT=%03X");
    RegCaseVal(Chipset.in,@"IN=%04X");
    RegCaseMem(Chipset.ST,@"ST=%@",4);
    RegCaseVal(Chipset.carry,@"CY=%d");
    isUpdated = Chipset.mode_dec != OldChipset.mode_dec;
    buf=[NSString stringWithFormat:@"Mode=%c",Chipset.mode_dec ? 'D' : 'H'];
    RegAddStr(buf);
    RegCaseBit(MP);
    RegCaseBit(SR);
    RegCaseBit(SB);
    RegCaseBit(XM);
    [self setRegisters: result];
    [result release];
}

- (void)UpdateMemory
{
    int  i,j,k;
    BYTE byLineData[MAXMEMITEMS];
    char szBuffer[16], szItem[4];
    BYTE cChar;
    NSMutableDictionary *memline;
    NSMutableArray *bytes;
    NSMutableArray *result = [[NSMutableArray alloc] init];

	szItem[2] = 0;							// end of string
    DWORD addr = dwAdrMem; //aIndex * (MAXMEMITEMS & (512*2048 - 1));

	for (i = 0; i < MAXMEMLINES; ++i)
	{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        memline = [NSMutableDictionary dictionaryWithCapacity: 3];
        bytes = [NSMutableArray arrayWithCapacity: MAXMEMITEMS];

        Npeek(byLineData, addr, MAXMEMITEMS);
        [memline setObject:[NSString stringWithFormat:@"%05X", addr] forKey:@"address"];
        for (k = 0, j = 0; j < MAXMEMITEMS; ++j)
        {
            // read from fetched data line
            szItem[j&0x1] = cHex[byLineData[j]];
            // characters are saved in LBS, MSB order
            cChar = (cChar >> 4) | (byLineData[j] << 4);
            
            if ((j&0x1) != 0)
            {
                // byte field
                [bytes addObject: [NSString stringWithUTF8String: szItem]];
                
                // text field
                szBuffer[j/2] = (isprint(cChar) != 0) ? cChar : '.';
            }
        }
        szBuffer[j/2] = 0;					// end of text string
        [memline setObject:[bytes componentsJoinedByString: @" "] forKey:@"bytes"];
        [memline setObject:[NSString stringWithUTF8String: szBuffer] forKey:@"text"];
        [result addObject: memline];
        addr = (addr + MAXMEMITEMS) & 0xFFFFF; //(512*2048 - 1);
        [pool release];
    }
    [self setMemory: result];
    [result release];
}

- (void)UpdateStack
{
    int i;
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity: ARRAYSIZEOF(Chipset.rstk)];
    for (i = 1; i <= ARRAYSIZEOF(Chipset.rstk); ++i)
    {
        [result addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSString stringWithFormat: @"%d: %05X", i, Chipset.rstk[(Chipset.rstkp-i)&7]], @"displayString",
                            [NSNumber numberWithUnsignedInt: Chipset.rstk[(Chipset.rstkp-i)&7]], @"address",
                            nil]];
    }
    [self setStack: result];
    [result release];
}

- (void)UpdateHistory
{
    int i, j;
	char szBuffer[64];
    NSString *addr;
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity: INSTRSIZE];
    if (nil == pdwInstrArray)
    {
		pdwInstrArray = HeapAlloc(hHeap,0,INSTRSIZE*sizeof(*pdwInstrArray));
		wInstrSize = INSTRSIZE;				// size of last instruction array
		wInstrWp = wInstrRp = 0;			// write/read pointer
    }

    for (i = wInstrRp; i != wInstrWp; i = (i + 1) % wInstrSize)
    {
        j = sprintf(szBuffer, "%05X   ", pdwInstrArray[i]);
        disassemble(pdwInstrArray[i],&szBuffer[j],VIEW_SHORT);
        addr = [[NSString alloc] initWithUTF8String: szBuffer];
        [result addObject: addr];
        [addr release];
    }
    [self setHistory: result];
    [result release];
}

- (void)UpdateMmu
{
	if (Chipset.IOCfig)
		[mmu setObject:[NSString stringWithFormat: @"%05X", Chipset.IOBase]
                forKey:@"MMU_IO_A"];
	if (Chipset.P0Cfig)
		[mmu setObject:[NSString stringWithFormat: @"%05X",Chipset.P0Base<<12]
                forKey:@"MMU_NCE2_A"];
	if (Chipset.P0Cfg2)
		[mmu setObject:[NSString stringWithFormat: @"%05X",(Chipset.P0Size^0xFF)<<12]
                forKey:@"MMU_NCE2_S"];
	if (Chipset.P1Cfig)
		[mmu setObject:[NSString stringWithFormat:@"%05X",Chipset.P1Base<<12]
                forKey:(cCurrentRomType=='S') ? @"MMU_CE1_A" : @"MMU_CE2_A"];
    if (Chipset.P1Cfg2)
        [mmu setObject:[NSString stringWithFormat:@"%05X",(Chipset.P1Size^0xFF)<<12]
                forKey:(cCurrentRomType=='S') ? @"MMU_CE1_S" : @"MMU_CE2_S"];
    if (Chipset.P2Cfig)
        [mmu setObject:[NSString stringWithFormat:@"%05X",Chipset.P2Base<<12]
                forKey:(cCurrentRomType=='S') ? @"MMU_CE2_A" : @"MMU_NCE3_A"];
    if (Chipset.P2Cfg2)
        [mmu setObject:[NSString stringWithFormat:@"%05X",(Chipset.P2Size^0xFF)<<12]
                forKey:(cCurrentRomType=='S') ? @"MMU_CE2_S" : @"MMU_NCE3_S"];
    if (Chipset.BSCfig)
        [mmu setObject:[NSString stringWithFormat:@"%05X",Chipset.BSBase<<12]
                forKey:(cCurrentRomType=='S') ? @"MMU_NCE3_A" : @"MMU_CE1_A"];
    if (Chipset.BSCfg2)
        [mmu setObject:[NSString stringWithFormat:@"%05X",(Chipset.BSSize^0xFF)<<12]
                forKey:(cCurrentRomType=='S') ? @"MMU_NCE3_S" : @"MMU_CE1_S"];
}

- (void)UpdateMisc
{
    [self setRegUpdated:(Chipset.inte != OldChipset.inte) forReg:@"MISC_INT"];
	[misc setObject:Chipset.inte ? @"On " : @"Off" forKey:@"MISC_INT"];

    [self setRegUpdated:(Chipset.intk != OldChipset.intk) forReg:@"MISC_KEY"];
	[misc setObject:Chipset.intk ? @"On " : @"Off" forKey:@"MISC_KEY"];

    [self setRegUpdated:NO forReg:@"MISC_BS"];
	// not 38/48S // CdB for HP: add Apples type
	if (cCurrentRomType!='A' && cCurrentRomType!='S')
    {
        [self setRegUpdated:((Chipset.Bank_FF & 0x7F) != (OldChipset.Bank_FF & 0x7F)) forReg:@"MISC_BS"];
        [misc setObject:[NSString stringWithFormat: @"%02X",Chipset.Bank_FF & 0x7F]
                 forKey:@"MISC_BS"];
    }
    else
    {
        [misc removeObjectForKey: @"MISC_BS"];
    }
}

- (void)UpdateProfile
{
#define CPU_FREQ 524288					// base CPU frequency
#define SX_RATE  0x0E
#define GX_RATE  0x1B
#define GP_RATE  0x1B*3 // CdB for HP: add high speed apples
#define G2_RATE  0x1B*2 // CdB for HP: add low speed apples
    NSDictionary *result;
    NSString *lastCycles;
    NSString *lastTime;

    LPCTSTR pcUnit[] = { _T("s"),_T("ms"),_T("us"),_T("ns") };

    DWORD lVar;
    INT   i;
    DWORD dwFreq, dwEndFreq;

    // 64 bit cpu cycle counter
    lVar = Chipset.cycles - OldChipset.cycles;

    // cycle counts
    lastCycles = [[NSString alloc] initWithFormat:@"%u", lVar];

    // CPU frequency
    switch (cCurrentRomType) // CdB for HP: add apples speed selection
    {
        case 'S': dwFreq= ((SX_RATE + 1) * CPU_FREQ / 4); break;
        case 'X': case 'G': case 'E': case 'A': dwFreq= ((GX_RATE + 1) * CPU_FREQ / 4); break;
        case 'P': case 'Q': dwFreq= ((GP_RATE + 1) * CPU_FREQ / 4); break;
        case '2': dwFreq= ((G2_RATE + 1) * CPU_FREQ / 4); break;
    }
    dwEndFreq = ((999 * 2 - 1) * dwFreq) / (2 * 1000);

    // search for unit
    for (i = 0; i < ARRAYSIZEOF(pcUnit) - 1; ++i)
    {
        if (lVar > dwEndFreq) break;		// found ENG unit
        lVar *= 1000;						// next ENG unit
    }

    // calculate rounded time
    lVar = (2 * lVar + dwFreq) / (2 * dwFreq);
    
    _ASSERT(i < ARRAYSIZEOF(pcUnit));
    lastTime = [[NSString alloc] initWithFormat:@"%u %s", lVar,pcUnit[i]];
    result = [[NSDictionary alloc] initWithObjectsAndKeys:
               lastCycles, @"lastCycles",
               lastTime,   @"lastTime",
               nil];
    [lastCycles release];
    [lastTime   release];
    [self setProfile: result];
    [result release];
#undef SX_CLK
#undef GX_CLK
#undef GP_RATE
#undef G2_RATE
#undef CPU_FREQ
}

- (void)UpdateWoRegisters
{
    NSDictionary *result = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSString stringWithFormat: @"%05X", Chipset.start1], @"ADDR20_24",
        [NSString stringWithFormat: @"%05X", Chipset.loffset], @"ADDR25_27",
        [NSString stringWithFormat: @"%05X", Chipset.lcounter], @"ADDR28_29",
        [NSString stringWithFormat: @"%05X", Chipset.start2], @"ADDR30_34",
    nil];
    [self setWoRegisters: result];
    [result release];
}

- (NSMutableDictionary *)regUpdated
{
    return regUpdated;
}
- (void)setRegUpdated:(BOOL)aUpdated forReg:(NSString *)aRegName
{
#if TARGET_OS_IPHONE
    [regUpdated setObject:aRegName forKey:aRegName];
#else
    [regUpdated setObject:(aUpdated ? [NSColor redColor] : [NSColor textColor]) forKey:aRegName];
#endif
}

- (void)update
{
    [self UpdateDisassemblyAtAddress: Chipset.pc];
    [self updateExceptDisassembly];
}

- (void)updateExceptDisassembly
{
    [self UpdateRegisters];
    [self UpdateMemory];
    [self UpdateStack];
    [self UpdateHistory];
    [self UpdateMmu];
    [self UpdateMisc];
    [self UpdateProfile];
    [self UpdateWoRegisters];
}

- (void)cont
{
    if (nDbgState != DBG_RUN)				// emulation stopped
    {
        if ([breakpoints count] > 0)
            nDbgState = DBG_RUN;			// state "run"
        else
            nDbgState = DBG_OFF;
        [self update];
		OldChipset = Chipset;				// save chipset values
		SetEvent(hEventDebug);				// run emulation
    }
}
- (void)pause
{
    dwDbgStopPC = -1;					// no stop address for goto cursor
    dwDbgRplPC = -1;					// no stop address for RPL breakpoint

    // init reference cpu cycle counter for 64 bit debug cycle counter
    dbgRefCycles = (DWORD) (Chipset.cycles & 0xFFFFFFFF);
    
	nDbgState = DBG_STEPINTO;				// state "step into"
    if (Chipset.Shutdn)					// cpu thread stopped
        SetEvent(hEventShutdn);			// goto debug session
    [self update];
    OldChipset = Chipset;				// save chipset values
}
- (void)stepInto
{
	if (nDbgState != DBG_RUN)				// emulation stopped
	{
        //		if (bDbgSkipInt)					// skip code in interrupt handler
        //			DisableMenuKeys(hDlg);			// disable menu keys
        
		nDbgState = DBG_STEPINTO;			// state "step into"
        [self update];
		OldChipset = Chipset;				// save chipset values
		SetEvent(hEventDebug);				// run emulation
	}
}
- (void)stepOut
{
	if (nDbgState != DBG_RUN)				// emulation stopped
	{
        //		DisableMenuKeys(hDlg);				// disable menu keys
		dbgRstkp = (Chipset.rstkp-1)&7;	// save stack data
		dwDbgRstk  = Chipset.rstk[dbgRstkp];
		nDbgState = DBG_STEPOUT;			// state "step out"
        [self update];
		OldChipset = Chipset;				// save chipset values
		SetEvent(hEventDebug);				// run emulation
	}
}
- (void)stepOver
{
	if (nDbgState != DBG_RUN)				// emulation stopped
	{
		LPBYTE I = FASTPTR(Chipset.pc);
        
        //		if (bDbgSkipInt)					// skip code in interrupt handler
        //			DisableMenuKeys(hDlg);			// disable menu keys
        
		dbgRstkp = Chipset.rstkp;			// save stack level
        
		// GOSUB 7aaa, GOSUBL 8Eaaaa, GOSBVL 8Faaaaa
		if (I[0] == 0x7 || (I[0] == 0x8 && (I[1] == 0xE || I[1] == 0xF)))
		{
			nDbgState = DBG_STEPOVER;		// state "step over"
		}
		else
		{
			nDbgState = DBG_STEPINTO;		// state "step into"
		}
        [self update];
		OldChipset = Chipset;				// save chipset values
		SetEvent(hEventDebug);				// run emulation
	}
}

- (void)notifyPausedWithBreakType:(NSNumber *)aBreakType
{
	nDbgState = DBG_STEPINTO;				// state "step into"
	dwDbgStopPC = -1;						// disable "cursor stop address"
    breakType = [aBreakType intValue];
    [self update];
}

- (void)enableDebugger
{
    if (DBG_OFF == nDbgState)
    {
        nDbgState = DBG_RUN;
        [self UpdateDisassemblyAtAddress: Chipset.pc];
    }
    else
    {
        [self setDisassembly: nil];
    }
    [self updateExceptDisassembly];
}

- (void)toggleBreakpoints
{
    breakpointsEnabled = !breakpointsEnabled;
    [self enableDebugger];
}

- (int)checkBreakpointAtAddress:(DWORD)dwAddr range:(DWORD)dwRange type:(UINT)nType
{
    static int BREAKPOINT_TYPE[] = { BP_EXEC, BP_RPL, BP_ACCESS, BP_READ, BP_WRITE };
    NSEnumerator *e;
    id breakpoint;

    e = [breakpoints objectEnumerator];
    while ((breakpoint = [e nextObject]))
	{
		// check address range and type
		if (   [[breakpoint valueForKey: @"address"] intValue] >= dwAddr 
            && [[breakpoint valueForKey: @"address"] intValue] < dwAddr + dwRange
			&& (BREAKPOINT_TYPE[[[breakpoint valueForKey: @"type"] intValue]] & nType) != 0)
        {
            return [[breakpoint valueForKey: @"enabled"] boolValue] && breakpointsEnabled;
        }
	}
    return -1;
}

- (BOOL)breakpointEnabledAtAddress:(DWORD)dwAddr range:(DWORD)dwRange type:(UINT)nType
{
    return (1 == [self checkBreakpointAtAddress:dwAddr range:dwRange type:nType]); 
}

- (void)updateDbgCycleCounter
{
	// update 64 bit cpu cycle counter
	if (Chipset.cycles < dbgRefCycles) ++Chipset.cycles_reserved;
	dbgRefCycles = (DWORD) (Chipset.cycles & 0xFFFFFFFF);
}

- (void)clearHistory
{
    if (pdwInstrArray)					// free last instruction circular buffer
    {
        HeapFree(hHeap,0,pdwInstrArray);
        pdwInstrArray = NULL;
    }
    [self setHistory: nil];
}

- (void)setCodeAddress:(DWORD)address {
    [self UpdateDisassemblyAtAddress: address];
    [self updateExceptDisassembly];
}

- (DWORD)getMemoryAddress {
    return dwAdrMem;
}
- (void)setMemoryAddress:(DWORD)address {
    dwAdrMem = address;
    [self UpdateMemory];
}
@end


@implementation CalcBreakpoint

- (id)init
{
    self = [super init];
    if (self)
    {
        [self setEnabled: YES];
        [self setType:    0];
    }
    return self;
}

- (void)dealloc
{
    [address release];
    [super dealloc];
}

- (BOOL)isEqual:(id)anObject
{
#if TARGET_OS_IPHONE
    return [[self address] isEqualToNumber: [anObject address]];
#else
    return [[self address] isEqualTo: [(CalcBreakpoint*)anObject address]];
#endif
}

- (BOOL)enabled { return enabled; }
- (void)setEnabled:(BOOL)value { enabled = value; }
- (NSNumber *)address  { return address; }
- (void)setAddress:(NSNumber *)value
{
    [address release];
    address = [value retain];
}
- (int)type     { return type;    }
- (void)setType:(int)value     { type = value; }
@end

@implementation CalcCheckBreakpointArgument
- (id)initWithAddress:(DWORD)dwAddr range:(DWORD)dwRange type:(UINT)nType
{
    self = [super init];
    address = dwAddr;
    range   = dwRange;
    type    = nType;
    return self;
}
- (DWORD)address { return address; }
- (DWORD)range   { return range; }
- (UINT)type   { return type; }
- (BOOL)result { return result; }
- (void)setResult:(BOOL)value { result = value; }
@end


VOID UpdateDbgCycleCounter(VOID)
{
    // Currently not used
#if 0
    [[[CalcBackend sharedBackend] debugModel] performSelectorOnMainThread:@selector(updateDbgCycleCounter) withObject:nil waitUntilDone:YES];
#endif
}

BOOL CheckBreakpoint(DWORD dwAddr, DWORD dwRange, UINT nType)
{
    return [[[CalcBackend sharedBackend] debugModel] breakpointEnabledAtAddress:dwAddr range:dwRange type:nType];
}

VOID NotifyDebugger(INT nType)
{
    [[[CalcBackend sharedBackend] debugModel] performSelectorOnMainThread:@selector(notifyPausedWithBreakType:) withObject:[NSNumber numberWithInt: nType] waitUntilDone:YES];
}

VOID DisableDebugger(VOID)
{
    nDbgState = DBG_OFF;				// debugger inactive
    bInterrupt = TRUE;					// exit opcode loop
    SetEvent(hEventDebug);
}
