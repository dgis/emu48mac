//
//  stack.m
//  emu48
//
//  Adapted from stack.c by Da-Woon Jung on 2009-07-16.
//

#import "pch.h"
#import "EMU48.H"
#import "IO.H"
#import "stack.h"

#define fnRadix		51			// fraction mark
#define fnApprox	105			// exact / approx. mode (HP49G)

#define DOINT		0x02614		// Precision Integer (HP49G)
#define DOREAL		0x02933		// Real
#define DOCSTR		0x02A2C		// String

NSString *Emu48ObjectPBoardType = @"com.dw.emu48-stack";

//################
//#
//#    Low level subroutines
//#
//################

static INT RPL_GetZInt(BYTE CONST *pbyNum,INT nIntLen,LPTSTR cp,INT nSize)
{
	INT i = 0;								// character counter
    
	_ASSERT(nSize > 0);						// target buffer size
    
	if (nIntLen > 1)						// has sign nibble
	{
		--nIntLen;							// remove sign from digit length
        
		// check for valid sign
		_ASSERT(pbyNum[nIntLen] == 0 || pbyNum[nIntLen] == 9);
		if (pbyNum[nIntLen] == 9)			// negative number
		{
			*cp++ = _T('-');				// add sign
			--nSize;						// dec dest buffer size
			++i;							// wrote one character
		}
	}
    
	if (nIntLen >= nSize) return 0;			// dest buffer overflow
	i += nIntLen;							// adjust character counter
    
	while (nIntLen-- > 0)					// write all digits
	{
		// check for valid digit
		_ASSERT(pbyNum[nIntLen] >= 0 && pbyNum[nIntLen] <= 9);
		*cp++ = _T('0') + pbyNum[nIntLen];	// and write
	}
	*cp = 0;								// set EOS
	return i;
}

static INT RPL_SetZInt(LPCTSTR cp,LPBYTE pbyNum,INT nSize)
{
	BYTE bySign;
	INT  nStrLen,nNumSize;
    
	_ASSERT(nSize > 0);						// target buffer size
    
	nStrLen = (int)lstrlen(cp);					// source string length
    
	if (   nStrLen == 0						// empty string
		// precisition integer contain only these numbers
		|| _tcsspn(cp,_T("0123456789+-")) != (SIZE_T) nStrLen)
		return 0;
    
	bySign = (*cp != _T('-')) ? 0 : 9;		// set sign nibble
	if (*cp == _T('-') || *cp == _T('+'))	// skip sign character
	{
		++cp;
		--nStrLen;
	}
    
	if (nStrLen == 1 && *cp == _T('0'))		// special code for zero
	{
		*pbyNum = 0;						// zero data
		return 1;							// finish
	}
    
	// nStrLen = no. of digits without sign
    if (nStrLen >= nSize)					// destination buffer too small
		return 0;
    
	nNumSize = nStrLen + 1;					// no. of written data
    
	while (--nStrLen >= 0)					// eval all digits
	{
		TCHAR c = cp[nStrLen];
        
		// only '0' .. '9' are valid here
		if (!((c >= _T('0')) || (c <= _T('9'))))
			return 0;
        
		c -= _T('0');		
		*pbyNum++ = (BYTE) c;
	}
	*pbyNum = bySign;						// add sign
    
	return nNumSize;
}

static INT RPL_GetBcd(BYTE CONST *pbyNum,INT nMantLen,INT nExpLen,CONST TCHAR cDec,LPTSTR cp,INT nSize)
{
	BYTE byNib;
	LONG v,lExp;
	BOOL bPflag,bExpflag;
	INT  i;
    
	lExp = 0;
	for (v = 1; nExpLen--; v *= 10)			// fetch exponent
	{
		lExp += (LONG) *pbyNum++ * v;		// calc. exponent
	}
    
	if (lExp > v / 2) lExp -= v;			// negative exponent
    
	lExp -= nMantLen - 1;					// set decimal point to end of mantissa
    
	i = 0;									// first character
	bPflag = FALSE;							// show no decimal point
    
	// scan mantissa
	for (v = (LONG) nMantLen - 1; v >= 0 || bPflag; v--)
	{
		if (v >= 0L)						// still mantissa digits left
			byNib = *pbyNum++;
		else
			byNib = 0;						// zero for negativ exponent
        
		if (!i)								// still delete zeros at end
		{
			if (byNib == 0 && lExp && v > 0) // delete zeros
			{
				lExp++;						// adjust exponent
				continue;
			}
            
			// TRUE at x.E
			bExpflag = v + lExp > 14 || v + lExp < -nMantLen;
			bPflag = !bExpflag && v < -lExp; // decimal point flag at neg. exponent
		}
        
		// set decimal point
		if ((bExpflag && v == 0) || (!lExp && i))
		{
			if (i >= nSize) return 0;		// dest buffer overflow
			cp[i++] = cDec;					// write decimal point
			if (v < 0)						// no mantissa digits any more
			{
				if (i >= nSize) return 0;	// dest buffer overflow
				cp[i++] = _T('0');			// write heading zero
			}
			bPflag = FALSE;					// finished with negativ exponents
		}
        
		if (v >= 0 || bPflag)
		{
			if (i >= nSize) return 0;		// dest buffer overflow
			cp[i++] = (TCHAR) byNib + _T('0'); // write character
		}
        
		lExp++;								// next position
	}
    
	if (*pbyNum == 9)						// negative number
	{
		if (i >= nSize) return 0;			// dest buffer overflow
		cp[i++] = _T('-');					// write sign
	}
    
	if (i >= nSize) return 0;				// dest buffer overflow
	cp[i] = 0;								// set EOS
    
	for (v = 0; v < (i / 2); v++)			// reverse string
	{
		TCHAR cNib = cp[v];					// swap chars
		cp[v] = cp[i-v-1];
		cp[i-v-1] = cNib;
	}
    
	// write number with exponent
	if (bExpflag)
	{
		if (i + 5 >= nSize) return 0;		// dest buffer overflow
        i += wsprintf(&cp[i],_T("E%l"),lExp-1);
	}
	return i;
}

static INT RPL_SetBcd(LPCTSTR cp,INT nMantLen,INT nExpLen,CONST TCHAR cDec,LPBYTE pbyNum,INT nSize)
{
	TCHAR cVc[] = _T(".0123456789eE+-");
    
	BYTE byNum[80];
	INT  i,nIp,nDp,nMaxExp;
	LONG lExp;
    
	cVc[0] = cDec;							// replace decimal char
    
	if (   nMantLen + nExpLen >= nSize		// destination buffer too small
		|| !*cp								// empty string
		|| _tcsspn(cp,cVc) != (SIZE_T) lstrlen(cp) // real contain only these numbers
		|| lstrlen(cp) >= ARRAYSIZEOF(byNum)) // ignore too long reals
		return 0;
    
	byNum[0] = (*cp != _T('-')) ? 0 : 9;	// set sign nibble
	if (*cp == _T('-') || *cp == _T('+'))	// skip sign character
		cp++;
    
	// only '.', '0' .. '9' are valid here
	if (!((*cp == cDec) || (*cp >= _T('0')) || (*cp <= _T('9'))))
		return 0;
    
	nIp = 0;								// length of integer part
	if (*cp != cDec)						// no decimal point
	{
		// count integer part
	    while (*cp >= _T('0') && *cp <= _T('9'))
			byNum[++nIp] = *cp++ - _T('0');
		if (!nIp) return 0;
	}
    
	// only '.', 'E', 'e' or end are valid here
	if (!(!*cp || (*cp == cDec) || (*cp == _T('E')) || (*cp == _T('e'))))
		return 0;
    
	nDp = 0;								// length of decimal part
	if (*cp == cDec)						// decimal point
	{
		cp++;								// skip '.'
        
		// count decimal part
		while (*cp >= _T('0') && *cp <= _T('9'))
			byNum[nIp + ++nDp] = *cp++ - _T('0');
	}
    
	// count number of heading zeros in mantissa
	for (i = 0; byNum[i+1] == 0 && i + 1 < nIp + nDp; ++i) { }
    
	if (i > 0)								// have to normalize
	{
		INT j;
        
		nIp -= i;							// for later ajust of exponent
		for (j = 1; j <= nIp + nDp; ++j)	// normalize mantissa
			byNum[j] = byNum[j + i];
	}
    
	if(byNum[1] == 0)						// number is 0
	{
		ZeroMemory(pbyNum,nMantLen + nExpLen + 1);
		return nMantLen + nExpLen + 1;
	}
    
	for (i = nIp + nDp; i < nMantLen;)		// fill rest of mantissa with 0
		byNum[++i] = 0;
    
	// must be 'E', 'e' or end
	if (!(!*cp || (*cp == _T('E')) || (*cp == _T('e'))))
		return 0;
    
	lExp = 0;
	if (*cp == _T('E') || *cp == _T('e'))
	{
		cp++;								// skip 'E'
        
		i = FALSE;							// positive exponent
		if (*cp == _T('-') || *cp == _T('+'))
		{
			i = (*cp++ == _T('-'));			// adjust exponent sign
		}
        
		// exponent symbol must be followed by number
		if (*cp < _T('0') || *cp > _T('9')) return 0;
        
		while (*cp >= _T('0') && *cp <= _T('9'))
			lExp = lExp * 10 + *cp++ - _T('0');
        
		if(i) lExp = -lExp;
	}
    
	if (*cp != 0) return 0;
    
	// adjust exponent value with exponent from normalized mantissa
	lExp += nIp - 1;
    
	// calculate max. posive exponent
	for (nMaxExp = 5, i = 1; i < nExpLen; ++i)
		nMaxExp *= 10;
    
	// check range of exponent
	if ((lExp < 0 && -lExp >= nMaxExp) || (lExp >= nMaxExp))
		return 0;
    
	if (lExp < 0) lExp += 2 * nMaxExp;		// adjust negative offset
    
	for (i = nExpLen; i > 0; --i)			// convert number into digits
	{
		byNum[nMantLen + i] = (BYTE) (lExp % 10);
		lExp /= 10;
	}
    
	// copy to target in reversed order
	for (i = nMantLen + nExpLen; i >= 0; --i)
		*pbyNum++ = byNum[i];
    
	return nMantLen + nExpLen + 1;
}

//################
//#
//#    Object subroutines
//#
//################

static TCHAR GetRadix(VOID)
{
	// get locale decimal point
	// GetLocaleInfo(LOCALE_USER_DEFAULT,LOCALE_SDECIMAL,&cDecimal,1);
    
	return RPL_GetSystemFlag(fnRadix) ? _T(',') : _T('.');
}

static INT DoInt(DWORD dwAddr,LPTSTR cp,INT nSize)
{
	LPBYTE lpbyData;
	INT    nLength,nIntLen;
    
	nIntLen = Read5(dwAddr) - 5;			// no. of digits
	if (nIntLen <= 0) return 0;				// error in calculator object
    
	nLength = 0;
	if ((lpbyData = HeapAlloc(hHeap,0,nIntLen)))
	{
		// get precisition integer object content and decode it
		Npeek(lpbyData,dwAddr+5,nIntLen);
		nLength = RPL_GetZInt(lpbyData,nIntLen,cp,nSize);
		HeapFree(hHeap,0,lpbyData);
	}
	return nLength;
}

static INT DoReal(DWORD dwAddr,LPTSTR cp,INT nSize)
{
	BYTE byNumber[16];

	// get real object content and decode it
	Npeek(byNumber,dwAddr,ARRAYSIZEOF(byNumber));
	return RPL_GetBcd(byNumber,12,3,GetRadix(),cp,nSize);
}


//################
//#
//#    Load and Save HP48 Objects
//#
//################

WORD WriteStack(UINT nStkLevel,LPBYTE lpBuf,DWORD dwSize)	// separated from LoadObject()
{
	BOOL   bBinary;
	DWORD  dwAddress, i;
    
	bBinary =  ((lpBuf[dwSize+0]=='H')
                &&  (lpBuf[dwSize+1]=='P')
                &&  (lpBuf[dwSize+2]=='H')
                &&  (lpBuf[dwSize+3]=='P')
                &&  (lpBuf[dwSize+4]=='4')
                &&  (lpBuf[dwSize+5]==((cCurrentRomType=='X' || cCurrentRomType=='2' || cCurrentRomType=='Q') ? '9' : '8'))  // CdB for HP: add apples
                &&  (lpBuf[dwSize+6]=='-'));
    
	for (dwAddress = 0, i = 0; i < dwSize; i++)
	{
		BYTE byTwoNibs = lpBuf[i+dwSize];
		lpBuf[dwAddress++] = (BYTE)(byTwoNibs&0xF);
		lpBuf[dwAddress++] = (BYTE)(byTwoNibs>>4);
	}
    
	dwSize = dwAddress;						// unpacked buffer size
    
	if (bBinary == TRUE)
	{ // load as binary
		dwSize = RPL_ObjectSize(lpBuf+16,dwSize-16);
		if (dwSize == BAD_OB) return S_ERR_OBJECT;
		dwAddress = RPL_CreateTemp(dwSize,TRUE);
		if (dwAddress == 0) return S_ERR_BINARY;
		Nwrite(lpBuf+16,dwAddress,dwSize);
	}
	else
	{ // load as string
		dwAddress = RPL_CreateTemp(dwSize+10,TRUE);
		if (dwAddress == 0) return S_ERR_ASCII;
		Write5(dwAddress,0x02A2C);			// String
		Write5(dwAddress+5,dwSize+5);		// length of String
		Nwrite(lpBuf,dwAddress+10,dwSize);	// data
	}
	RPL_Push(nStkLevel,dwAddress);
	return S_ERR_NO;
}


//################
//#
//#    Stack routines
//#
//################

@interface CalcStack(Private)
- (BOOL)copyObjectRepresentation:(NSError **)outError;
- (BOOL)copyStringRepresentation;
@end

@implementation CalcStack

- (id)initWithError:(NSError **)outError
{
    self = [super init];
    if (self)
    {
        NSString *errDesc   = nil;
        NSString *errReason = nil;

        do
        {
            if (nState != SM_RUN)
            {
                errDesc = NSLocalizedString(@"The emulator must be running to copy the stack.",@"");
                errReason = NSLocalizedString(@"The emulator is not running.",@"");
                break;
            }

            if (WaitForSleepState())
            {
                errDesc = NSLocalizedString(@"Could not copy stack because the emulator is busy.",@"");
                errReason = NSLocalizedString(@"The emulator is busy.",@"");
                break;
            }

            _ASSERT(nState == SM_SLEEP);
            [self copyObjectRepresentation: outError];
            [self copyStringRepresentation];
            SwitchToState(SM_RUN);
            return self;
        } while (NO);

        if (errDesc && errReason && outError && nil==*outError)
            *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:errDesc, NSLocalizedDescriptionKey, errReason, NSLocalizedFailureReasonErrorKey, nil]];
        [self release]; self = nil;
    }

    return self;
}

- (id)initWithObject:(NSData *)aData
{
    self = [super init];
    if (self)
    {
        [self setObjectRepresentation: aData];
    }
    return self;
}

- (id)initWithString:(NSString *)aString
{
    self = [super init];
    if (self)
    {
        [self setStringRepresentation: aString];
    }
    return self;
}

- (void)dealloc
{
    [objectRepresentation release];
    [stringRepresentation release];
    [super dealloc];
}

- (NSData *)objectRepresentation
{
    return objectRepresentation;
}
- (NSString *)stringRepresentation
{
    return stringRepresentation;
}

- (void)setObjectRepresentation:(NSData *)aObjectRepresentation
{
    [objectRepresentation release];
    objectRepresentation = [aObjectRepresentation retain];
}
- (void)setStringRepresentation:(NSString *)aStringRepresentation
{
    [stringRepresentation release];
    stringRepresentation = [aStringRepresentation retain];
}

- (BOOL)copyObjectRepresentation:(NSError **)outError	// separated stack reading part
{
	LPBYTE  pbyHeader;
	//DWORD	lBytesWritten;
	DWORD   dwAddr;
	DWORD   dwLength;
    NSMutableData *data = nil;

	dwAddr = RPL_Pick(1);
	if (dwAddr == 0)
	{
        if (outError)
            *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Stack could not be copied because there are two few arguments.",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"Too Few Arguments.",@""), NSLocalizedFailureReasonErrorKey, nil]];
		return NO;
	}
	dwLength = (RPL_SkipOb(dwAddr) - dwAddr + 1) / 2;
    data = [NSMutableData data];

	pbyHeader = ((Chipset.type=='X' || Chipset.type=='2' || Chipset.type=='Q'))
			  ? (LPBYTE)BINARYHEADER49
			  : (LPBYTE)BINARYHEADER48;
    [data appendBytes:pbyHeader length:8];

	while (dwLength--)
	{
		BYTE byByte = Read2(dwAddr);
        [data appendBytes:&byByte length:1];
		dwAddr += 2;
	}

    [self setObjectRepresentation: data];
	return YES;
}

- (BOOL)copyStringRepresentation			// copy data from stack
{
	TCHAR  cBuffer[128];
	LPBYTE lpbyData;
	DWORD  dwAddr,dwObject,dwSize;
    BOOL result = NO;
    LPBYTE strStart;
    NSString *str = nil;

	if ((dwAddr = RPL_Pick(1)) == 0)		// pick address of level1 object
	{
//		MessageBeep(MB_OK);					// error beep
		goto error;
	}
    
	switch (dwObject = Read5(dwAddr))	// select object
	{
        case DOINT:  // Precision Integer (HP49G)
        case DOREAL: // real object
            dwAddr += 5;						// object content
            
            switch (dwObject)
            {
                case DOINT: // Precision Integer (HP49G)
                    // get precision integer object content and decode it
                    dwSize = DoInt(dwAddr,cBuffer,ARRAYSIZEOF(cBuffer));
                    break;
                case DOREAL: // real object
                    // get real object content and decode it
                    dwSize = DoReal(dwAddr,cBuffer,ARRAYSIZEOF(cBuffer));
                    break;
            }

            str = [NSString stringWithUTF8String: cBuffer];
            result = YES;
            break;
        case DOCSTR: // string
            dwAddr += 5;						// address of string length
            dwSize = (Read5(dwAddr) - 5) / 2; // length of string
            lpbyData = malloc(dwSize + 1);

            // memory allocation for clipboard data
            if (lpbyData == NULL)
                goto error;

            strStart = lpbyData;
            // copy data into clipboard buffer
            for (dwAddr += 5;dwSize-- > 0;dwAddr += 2,++lpbyData)
                *lpbyData = Read2(dwAddr);
            *lpbyData = 0;					// set EOS
            str = [NSString stringWithUTF8String: (char *)strStart];
            free(strStart);
            result = YES;
            break;
        default:
//            MessageBeep(MB_OK);					// error beep
            goto error;
	}

error:
    [self setStringRepresentation: str];
	return result;
}

- (void)pasteObjectRepresentation:(NSError **)outError
{
	DWORD  dwFileSizeLow;
	LPBYTE lpBuf;
	WORD wError;
    NSString *errDesc   = nil;
    NSString *errReason = nil;

	SuspendDebugger();						// suspend debugger
	bDbgAutoStateCtrl = FALSE;				// disable automatic debugger state control

	// calculator off, turn on
	if (!(Chipset.IORam[BITOFFSET]&DON))
	{
		KeyboardEvent(TRUE,0,0x8000);
		KeyboardEvent(FALSE,0,0x8000);

		// wait for sleep mode
		while (Chipset.Shutdn == FALSE) Sleep(0);
	}
    
	if (nState != SM_RUN)
	{
        errDesc = NSLocalizedString(@"The emulator must be running to load an object.",@"");
        errReason = NSLocalizedString(@"The emulator is not running.",@"");
		goto cancel;
	}
    
	if (WaitForSleepState())				// wait for cpu SHUTDN then sleep state
	{
        errDesc = NSLocalizedString(@"Could not load object because the emulator is busy.",@"");
        errReason = NSLocalizedString(@"The emulator is busy.",@"");
		goto cancel;
	}
    
	_ASSERT(nState == SM_SLEEP);
    
#if 0
    // TODO: Implement object load warning
	if (bLoadObjectWarning)
	{
		UINT uReply = YesNoCancelMessage(
                                         _T("Warning: Trying to load an object while the emulator is busy\n")
                                         _T("will certainly result in a memory lost. Before loading an object\n")
                                         _T("you should be sure that the calculator is not doing anything.\n")
                                         _T("Do you want to see this warning next time you try to load an object ?"),0);
		switch (uReply)
		{
            case IDYES:
                break;
            case IDNO:
                bLoadObjectWarning = FALSE;
                break;
            case IDCANCEL:
                SwitchToState(SM_RUN);
                goto cancel;
		}
	}
#endif

    dwFileSizeLow = (unsigned int)[objectRepresentation length];
	lpBuf = calloc(1, dwFileSizeLow*2);
    memcpy(lpBuf+dwFileSizeLow, [objectRepresentation bytes], dwFileSizeLow);
    wError = WriteStack(1,lpBuf,dwFileSizeLow);
    
	if (wError == S_ERR_OBJECT)
    {
//		AbortMessage(_T("This isn't a valid binary file."));
        errDesc = NSLocalizedString(@"Binary object could not be loaded because it isn't valid.",@"");
        errReason = NSLocalizedString(@"This isn't a valid binary object.",@"");
    }

	if (wError == S_ERR_BINARY)
    {
//		AbortMessage(_T("The calculator does not have enough\nfree memory to load this binary file."));
        errDesc = NSLocalizedString(@"Binary object could not be loaded because the calculator does not have enough free memory.",@"");
        errReason = NSLocalizedString(@"The calculator does not have enough free memory to load this binary object.",@"");
    }

	if (wError == S_ERR_ASCII)
    {
//		AbortMessage(_T("The calculator does not have enough\nfree memory to load this text file."));
        errDesc = NSLocalizedString(@"Text object could not be loaded because the calculator does not have enough free memory.",@"");
        errReason = NSLocalizedString(@"The calculator does not have enough free memory to load this text object.",@"");
    }

	if (wError != S_ERR_NO)
	{
		SwitchToState(SM_RUN);
		goto cancel;
	}

	SwitchToState(SM_RUN);					// run state
	while (nState!=nNextState) Sleep(0);
	_ASSERT(nState == SM_RUN);
	KeyboardEvent(TRUE,0,0x8000);
	Sleep(200);
	KeyboardEvent(FALSE,0,0x8000);
	while (Chipset.Shutdn == FALSE) Sleep(0);
    return;

cancel:
    if (outError && nil==*outError)
        *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:errDesc, NSLocalizedDescriptionKey, errReason, NSLocalizedFailureReasonErrorKey, nil]];
    bDbgAutoStateCtrl = TRUE;				// enable automatic debugger state control
	ResumeDebugger();
}

- (void)pasteStringRepresentation:(NSError **)outError
{
	BOOL bSuccess = NO;
    LPCTSTR lpstrClipdata;
    LPBYTE  lpbyData;

	SuspendDebugger();						// suspend debugger
	bDbgAutoStateCtrl = FALSE;				// disable automatic debugger state control
    
	// calculator off, turn on
	if (!(Chipset.IORam[BITOFFSET]&DON))
	{
		KeyboardEvent(TRUE,0,0x8000);
		KeyboardEvent(FALSE,0,0x8000);

		// wait for sleep mode
		while(Chipset.Shutdn == FALSE) Sleep(0);
	}

	_ASSERT(nState == SM_RUN);				// emulator must be in RUN state
	if (WaitForSleepState())				// wait for cpu SHUTDN then sleep state
	{
//		InfoMessage(_T("The emulator is busy."));
		goto cancel;
	}

	_ASSERT(nState == SM_SLEEP);

    if ((lpstrClipdata = [stringRepresentation UTF8String]))
    {
        BYTE  byNumber[128];
        DWORD dwAddr;
        INT   s;

        do
        {
            // HP49G or HP49G+ in exact mode
            if (   (cCurrentRomType == 'X' || cCurrentRomType == 'Q')
                && !RPL_GetSystemFlag(fnApprox))
            {
                // try to convert string to HP49 precision integer
                s = RPL_SetZInt(lpstrClipdata,byNumber,sizeof(byNumber));
                
                if (s > 0)			// is a real number for exact mode
                {
                    // get TEMPOB memory for HP49 precision integer object
                    dwAddr = RPL_CreateTemp(s+5+5,TRUE);
                    if ((bSuccess = (dwAddr > 0)))
                    {
                        Write5(dwAddr,DOINT); // prolog
                        Write5(dwAddr+5,s+5); // size
                        Nwrite(byNumber,dwAddr+10,s); // data
                        
                        // push object to stack
                        RPL_Push(1,dwAddr);
                    }
                    break;
                }
            }

            // try to convert string to real format
            s = RPL_SetBcd(lpstrClipdata,12,3,GetRadix(),byNumber,sizeof(byNumber));
            
            if (s > 0)				// is a real number
            {
                // get TEMPOB memory for real object
                dwAddr = RPL_CreateTemp(16+5,TRUE);
                if ((bSuccess = (dwAddr > 0)))
                {
                    Write5(dwAddr,DOREAL); // prolog
                    Nwrite(byNumber,dwAddr+5,s); // data
                    
                    // push object to stack
                    RPL_Push(1,dwAddr);
                }
                break;
            }

            // any other format
            {
                DWORD dwSize = (unsigned int)lstrlen(lpstrClipdata);
                if ((lpbyData = HeapAlloc(hHeap,0,dwSize * 2)))
                {
                    LPBYTE lpbySrc,lpbyDest;
                    DWORD  dwLoop;
                    
                    // copy data
                    memcpy(lpbyData+dwSize,lpstrClipdata,dwSize);
                    
                    // unpack data
                    lpbySrc = lpbyData+dwSize;
                    lpbyDest = lpbyData;
                    dwLoop = dwSize;
                    while (dwLoop-- > 0)
                    {
                        BYTE byTwoNibs = *lpbySrc++;
                        *lpbyDest++ = (BYTE) (byTwoNibs & 0xF);
                        *lpbyDest++ = (BYTE) (byTwoNibs >> 4);
                    }
                    
                    dwSize *= 2;	// size in nibbles

                    // get TEMPOB memory for string object
                    dwAddr = RPL_CreateTemp(dwSize+10,TRUE);
                    if ((bSuccess = (dwAddr > 0)))
                    {
                        Write5(dwAddr,DOCSTR); // String
                        Write5(dwAddr+5,dwSize+5); // length of String
                        Nwrite(lpbyData,dwAddr+10,dwSize); // data

                        // push object to stack
                        RPL_Push(1,dwAddr);
                    }
                    HeapFree(hHeap,0,lpbyData);
                }
            }
        }
        while(FALSE);
    }
    
	SwitchToState(SM_RUN);					// run state
	while (nState!=nNextState) Sleep(0);
	_ASSERT(nState == SM_RUN);
    
	if (bSuccess == FALSE)					// data not copied
		goto cancel;
    
	KeyboardEvent(TRUE,0,0x8000);
	Sleep(200);
	KeyboardEvent(FALSE,0,0x8000);

	// wait for sleep mode
	while(Chipset.Shutdn == FALSE) Sleep(0);

cancel:
	bDbgAutoStateCtrl = TRUE;				// enable automatic debugger state control
	ResumeDebugger();
}

#if !TARGET_OS_IPHONE || (__IPHONE_OS_VERSION_MIN_REQUIRED >= 30000)
+ (NSArray *)copyableTypes
{
    return [NSArray arrayWithObjects:
            Emu48ObjectPBoardType,
#if TARGET_OS_IPHONE
            kUTTypeUTF8PlainText,
#else
            NSPasteboardTypeString,
            NSFilenamesPboardType,
            NSPasteboardTypeURL,
            NSFileContentsPboardType,
#endif
            nil];
}
+ (NSString *)bestTypeFromPasteboard:(CalcPasteboard *)pb
{
#if TARGET_OS_IPHONE
    NSArray *pbTypes = [pb pasteboardTypes];
    NSArray *allowed = [CalcStack copyableTypes];
    NSString *foundType = nil;
    for (NSString *type in allowed)
    {
        if ([pbTypes containsObject: type])
        {
            foundType = type;
            break;
        }
    }
    return foundType;
#else
    return [pb availableTypeFromArray: [CalcStack copyableTypes]];
#endif
}

- (BOOL)copyToPasteboard:(CalcPasteboard *)pb
{
    BOOL result = NO;
    NSMutableArray *types = [[NSMutableArray alloc] init];
    if (objectRepresentation)
        [types addObject: Emu48ObjectPBoardType];
    if (stringRepresentation)
        [types addObject:
#if TARGET_OS_IPHONE
         (NSString *)kUTTypeUTF8PlainText
#else
         NSPasteboardTypeString
#endif
        ];
    if ([types count] > 0)
    {
#if TARGET_OS_IPHONE
        if (objectRepresentation)
            [pb setData:objectRepresentation forPasteboardType:Emu48ObjectPBoardType];
        if (stringRepresentation)
            [pb setData:[stringRepresentation dataUsingEncoding: NSUTF8StringEncoding] forPasteboardType:(NSString *)kUTTypeUTF8PlainText];
#else
        [pb declareTypes:types owner:self];
        if (objectRepresentation)
            [pb setData:objectRepresentation forType:Emu48ObjectPBoardType];
        if (stringRepresentation)
            [pb setData:[stringRepresentation dataUsingEncoding: NSUTF8StringEncoding] forType:NSPasteboardTypeString];
#endif
        result = YES;
    }
    [types release];
    return result;
}

- (BOOL)pasteFromPasteboard:(CalcPasteboard *)pb
{
    NSString *type = [CalcStack bestTypeFromPasteboard: pb];
    NSError *err = nil;
    NSString *str = nil;
    NSData *data  = nil;
#if !TARGET_OS_IPHONE
    NSArray *files = nil;

    if ([type isEqualToString: NSFilenamesPboardType])
    {
        files = [pb propertyListForType: NSFilenamesPboardType];
    }
    else if ([type isEqualToString: NSPasteboardTypeURL])
    {
        NSURL *fileURL = [NSURL URLFromPasteboard: pb];
        if (fileURL)
            data = [NSData dataWithContentsOfURL:fileURL options:0 error:&err];
    }
    else if ([type isEqualToString: NSFileContentsPboardType])
    {
        NSFileWrapper *fileContents = [pb readFileWrapper];
        if (fileContents)
        {
            if ([fileContents isRegularFile])
            {
                data = [fileContents regularFileContents];
            }
            else if ([fileContents isSymbolicLink])
            {
                //files = [NSArray arrayWithObject: [fileContents symbolicLinkDestination]];
                files = [NSArray arrayWithObject: [[fileContents symbolicLinkDestinationURL] path]];
            }
        }
    }
    else
#endif
        if ([type isEqualToString: Emu48ObjectPBoardType])
    {
#if TARGET_OS_IPHONE
        data = [pb dataForPasteboardType: Emu48ObjectPBoardType];
#else
        data = [pb dataForType: Emu48ObjectPBoardType];
#endif
    }
    else if ([type isEqualToString: 
#if TARGET_OS_IPHONE
              (NSString *)kUTTypeUTF8PlainText
#else
              NSPasteboardTypeString
#endif
             ])
    {
#if TARGET_OS_IPHONE
        str = pb.string;
#else
        str = [pb stringForType: NSPasteboardTypeString];
#endif
    }
    else
    {
        return NO;
    }

#if !TARGET_OS_IPHONE
    if (files && [files count] > 0)
    {
        NSEnumerator *fileEnum = [files objectEnumerator];
        id file;
        while ((file = [fileEnum nextObject]))
        {
            NSData *data = [NSData dataWithContentsOfFile:file options:(NSMappedRead | NSUncachedRead) error:&err];
            if (data)
            {
                [self setObjectRepresentation: data];
                [self pasteObjectRepresentation: &err];
            }
        }
    }
    else
#endif
    {
        if (data)
        {
            [self setObjectRepresentation: data];
            [self pasteObjectRepresentation: &err];
        }
        else if (str && [str length] > 0)
        {
            [self setStringRepresentation: str];
            [self pasteStringRepresentation: &err];
        }
    }

    return YES;
}
#endif
@end
