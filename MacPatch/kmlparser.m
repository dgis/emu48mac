/*
 *  kmlparser.m
 *  emu48
 *
 *  Cocoa implementation of kml.c
 *
 *  Created by Da Woon Jung on 2009-01-22
 *  Copyright (c) 2009 dwj. All rights reserved.
 *
 */
#import "kmlparser.h"
#ifndef TARGET_OS_IPHONE
#import "KmlLogController.h"
#import "CalcAppController.h"
#endif
#import "CalcBackend.h"
#import "pch.h"
#import "EMU48.H"


#ifndef TARGET_OS_IPHONE
#define LogController   [[NSApp delegate] kmlLogController]
#endif

typedef struct KmlTokenC
{
	TokenId eId;
	DWORD  nParams;
	DWORD  nLen;
	NSString *szName;
} KmlTokenC;

static KmlTokenC pLexToken[] =
{
	{TOK_ANNUNCIATOR,000001,11,@"Annunciator"},
	{TOK_BACKGROUND, 000000,10,@"Background"},
	{TOK_IFPRESSED,  000001, 9,@"IfPressed"},
	{TOK_RESETFLAG,  000001, 9,@"ResetFlag"},
	{TOK_SCANCODE,   000001, 8,@"Scancode"},
	{TOK_HARDWARE,   000002, 8,@"Hardware"},
	{TOK_MENUITEM,   000001, 8,@"MenuItem"},
	{TOK_SETFLAG,    000001, 7,@"SetFlag"},
	{TOK_RELEASE,    000001, 7,@"Release"},
	{TOK_VIRTUAL,    000000, 7,@"Virtual"},
	{TOK_INCLUDE,    000002, 7,@"Include"},
	{TOK_NOTFLAG,    000001, 7,@"NotFlag"},
    {TOK_MENUBAR,    000001, 7,@"Menubar"},	// windows mobile
	{TOK_GLOBAL,     000000, 6,@"Global"},
	{TOK_AUTHOR,     000002, 6,@"Author"},
	{TOK_BITMAP,     000002, 6,@"Bitmap"},
	{TOK_OFFSET,     000011, 6,@"Offset"},
	{TOK_BUTTON,     000001, 6,@"Button"},
	{TOK_IFFLAG,     000001, 6,@"IfFlag"},
	{TOK_ONDOWN,     000000, 6,@"OnDown"},
	{TOK_NOHOLD,     000000, 6,@"NoHold"},
    {TOK_TOPBAR,     000001, 6,@"Topbar"},	// windows mobile
	{TOK_TITLE,      000002, 5,@"Title"},
	{TOK_OUTIN,      000011, 5,@"OutIn"},
	{TOK_PATCH,      000002, 5,@"Patch"},
	{TOK_PRINT,      000002, 5,@"Print"},
	{TOK_DEBUG,      000001, 5,@"Debug"},
	{TOK_COLOR,      001111, 5,@"Color"},
	{TOK_MODEL,      000002, 5,@"Model"},
	{TOK_CLASS,      000001, 5,@"Class"},
	{TOK_PRESS,      000001, 5,@"Press"},
	{TOK_TYPE,       000001, 4,@"Type"},
	{TOK_SIZE,       000011, 4,@"Size"},
	{TOK_ZOOM,       000001, 4,@"Zoom"},
	{TOK_DOWN,       000011, 4,@"Down"},
	{TOK_ELSE,       000000, 4,@"Else"},
	{TOK_ONUP,       000000, 4,@"OnUp"},
	{TOK_MAP,        000011, 3,@"Map"},
	{TOK_ROM,        000002, 3,@"Rom"},
    {TOK_VGA,        000001, 3,@"Vga"},		// windows mobile
	{TOK_LCD,        000000, 3,@"Lcd"},
	{TOK_END,        000000, 3,@"End"},
	{TOK_NONE,       000000, 0,@""},
};

static TokenId eIsGlobalBlock[] =
{
    TOK_GLOBAL,
    TOK_BACKGROUND,
    TOK_LCD,
    TOK_ANNUNCIATOR,
    TOK_BUTTON,
    TOK_SCANCODE
};

static TokenId eIsBlock[] =
{
	TOK_IFFLAG,
	TOK_IFPRESSED,
	TOK_ONDOWN,
	TOK_ONUP
};


NSString *MapKMLFile(NSString *filename)
{
    // Read the whole file into one huge string
    // We support only a couple of encodings for now
    NSError *err = nil;
    NSString *bufstr;
    bufstr = [[NSString alloc] initWithContentsOfFile:filename encoding:NSUTF8StringEncoding error:&err];
    if (err)
    {
        err = nil;
        bufstr = [[NSString alloc] initWithContentsOfFile:filename encoding:NSISOLatin1StringEncoding error:&err];
    }
    if (err)
    {
        return nil;
    }
    return bufstr;
}

KmlLine* SkipLines(KmlLine* pLine, TokenId eCommand)
{
	UINT nLevel = 0;
	while (pLine)
	{
		if (IsBlock(pLine->eCommand)) nLevel++;
		if (pLine->eCommand==eCommand)
		{
			if (nLevel == 0) return pLine->pNext;
		}
		if (pLine->eCommand == TOK_END)
		{
			if (nLevel)
				nLevel--;
			else
				return NULL;
		}
		pLine = pLine->pNext;
	}
	return pLine;
}

void FreeLines(KmlLine* pLine)
{
	while (pLine)
	{
		KmlLine* pThisLine = pLine;
		UINT i = 0;
		DWORD nParams;
		while (pLexToken[i].nLen)			// search in all token definitions
		{
			// break when token definition found
			if (pLexToken[i].eId == pLine->eCommand) break;
			i++;							// next token definition
		}
		nParams = pLexToken[i].nParams;		// get argument types of command
		i = 0;								// first parameter
		while ((nParams&7))					// argument left
		{
			if ((nParams&7) == TYPE_STRING)	// string type
			{
				[(NSString *)pLine->nParam[i] release];
			}
			i++;							// incr. parameter buffer index
			nParams >>= 3;					// next argument type
		}
		pLine = pLine->pNext;				// get next line
		free(pThisLine);
	}
}

void FreeBlocks(KmlBlock* pBlock)
{
	while (pBlock)
	{
		KmlBlock* pThisBlock = pBlock;
		pBlock = pBlock->pNext;
		FreeLines(pThisBlock->pFirstLine);
		free(pThisBlock);
	}
}

BOOL IsGlobalBlock(TokenId eId)
{
	UINT i;
    
	for (i = 0; i < ARRAYSIZEOF(eIsGlobalBlock); ++i)
	{
		if (eId == eIsGlobalBlock[i]) return TRUE;
	}
	return FALSE;
}

BOOL IsBlock(TokenId eId)
{
	UINT i;

	for (i = 0; i < ARRAYSIZEOF(eIsBlock); ++i)
	{
		if (eId == eIsBlock[i]) return TRUE;
	}
	return FALSE;
}

NSString *GetStringOf(TokenId eId)
{
	UINT i;

	for (i = 0; pLexToken[i].nLen; ++i)
	{
		if (pLexToken[i].eId == eId) return pLexToken[i].szName;
	}
	return NSLocalizedString(@"<Undefined>",@"");
}


NSString *GetStringParam(KmlBlock* pBlock, TokenId eBlock, TokenId eCommand, UINT nParam)
{
	while (pBlock)
	{
		if (pBlock->eType == eBlock)
		{
			KmlLine* pLine = pBlock->pFirstLine;
			while (pLine)
			{
				if (pLine->eCommand == eCommand)
				{
					return (NSString *)pLine->nParam[nParam];
				}
				pLine = pLine->pNext;
			}
		}
		pBlock = pBlock->pNext;
	}
	return nil;
}


@implementation KmlParser

- (IBAction)DisplayKMLLog:(id)sender
{
#ifndef TARGET_OS_IPHONE
    KmlLogController *logController = LogController;
    BOOL showLog = [[NSUserDefaults standardUserDefaults]
                    boolForKey: @"AlwaysDisplayLog"];

    if (self != sender || showLog)
        [logController showWindow: sender];
#endif
}

- (void)dealloc
{
    [scanner release];
    [super dealloc];
}

- (id)delegate
{
    return delegate;
}
- (void)setDelegate:(id)aDelegate
{
    delegate = aDelegate;
}
- (UINT)blockIncludeLevel
{
    return nBlocksIncludeLevel;
}
- (void)setBlockIncludeLevel:(UINT)aLevel
{
    nBlocksIncludeLevel = aLevel;
}
- (UINT)lineIncludeLevel
{
    return nLinesIncludeLevel;
}
- (void)setLineIncludeLevel:(UINT)aLevel
{
    nLinesIncludeLevel = aLevel;
}


- (KmlBlock *)ParseIncludeBlocks:(NSString *)aFilename
                    includeLevel:(int)aIncludeLevel
                           error:(NSString **)aErrmsg
{
    KmlBlock *result = nil;
    NSError  *err    = nil;
	NSString *lpbyBuf = [[NSString alloc] initWithContentsOfFile:aFilename encoding:NSUTF8StringEncoding error:&err];
    if (err)
    {
        err = nil;
        lpbyBuf = [[NSString alloc] initWithContentsOfFile:aFilename encoding:NSISOLatin1StringEncoding error:&err];
    }
	if (err || nil==lpbyBuf)
	{
        if (aErrmsg)
        {
            NSString *title = [[NSString alloc] initWithFormat: NSLocalizedString(@"Error while opening include file %@.",@""), aFilename];
            if (err)
            {
                *aErrmsg = [[NSString alloc] initWithFormat: @"%@ %@", title, [err localizedFailureReason]];
                [title release];
            }
            else
                *aErrmsg = title;
        }
		return nil;
	}

	PrintfToLog(@"b%i:Including %@", aIncludeLevel, aFilename);
    KmlParser *parser = [[KmlParser alloc] init];
    [parser setBlockIncludeLevel: aIncludeLevel];
	[parser InitLex:lpbyBuf];
	result = [parser ParseBlocks];
	[parser release];
    [lpbyBuf release];
    return result;
}

- (KmlLine *)ParseIncludeLines:(NSString *)aFilename
                  includeLevel:(int)aIncludeLevel
                         error:(NSString **)aErrmsg
{
    KmlLine *result = nil;
    NSError  *err    = nil;
	NSString *lpbyBuf = [[NSString alloc] initWithContentsOfFile:aFilename encoding:NSUTF8StringEncoding error:&err];
    if (err)
    {
        err = nil;
        lpbyBuf = [[NSString alloc] initWithContentsOfFile:aFilename encoding:NSISOLatin1StringEncoding error:&err];
    }
	if (err || nil==lpbyBuf)
	{
        if (aErrmsg)
        {
            NSString *title = [[NSString alloc] initWithFormat: NSLocalizedString(@"Error while opening include file %@.",@""), aFilename];
            if (err)
            {
                *aErrmsg = [[NSString alloc] initWithFormat: @"%@ %@", title, [err localizedFailureReason]];
                [title release];
            }
            else
                *aErrmsg = title;
        }
		return nil;
	}
    
	PrintfToLog(@"l%i:Including %@", aIncludeLevel, aFilename);
    KmlParser *parser = [[KmlParser alloc] init];
    [parser setLineIncludeLevel: aIncludeLevel];
	[parser InitLex:lpbyBuf];
	result = [parser ParseLines];
	[parser release];
    [lpbyBuf release];
    return result;
}

// Parses the whole file
- (KmlParseResult *)ParseKML:(NSString *)filename error:(NSError **)outError
{
    NSString  *lpBuf;
	KmlBlock  *pBlock;
    KmlBlock  *result = nil;
    KmlParseResult *resultWrapped = nil;
	BOOL       bOk = NO;

	[self KillKML];

	nBlocksIncludeLevel = 0;
	if((lpBuf = MapKMLFile([filename lastPathComponent])) == nil) // already in kml folder so strip path to file
    {
        errReason = NSLocalizedString(@"The KML Script was either moved, has bad permissions, or is in an unrecognized encoding.",@"");
		goto quit;
    }

    resultWrapped = [[KmlParseResult alloc] initWithKmlPath: filename];
    [self setDelegate: resultWrapped];
	[self InitLex:lpBuf];
	result = [self ParseBlocks];
	[self CleanLex];

    [lpBuf release];
	if (result == nil) goto quit;

    [resultWrapped setFirstBlock: result];
	pBlock = result;
	while (pBlock)
	{
		switch (pBlock->eType)
		{
		case TOK_BUTTON:
			[self InitButton:pBlock];
			break;
		case TOK_SCANCODE:
			++nScancodes;
            if ([delegate respondsToSelector:@selector(parsedVKey:atIndex:)])
            {
                [delegate parsedVKey:pBlock atIndex:pBlock->nId];
            }
			break;
		case TOK_ANNUNCIATOR:
			[self InitAnnunciator:pBlock];
			break;
		case TOK_GLOBAL:
			[self InitGlobal:pBlock];
			break;
		case TOK_LCD:
			[self InitLcd:pBlock];
			break;
		case TOK_BACKGROUND:
			[self InitBackground:pBlock];
			break;
		default:
			PrintfToLog(@"Block %@ Ignored.", GetStringOf(pBlock->eType));
			pBlock = pBlock->pNext;
		}
		pBlock = pBlock->pNext;
	}

	if (!romTypeValid)
	{
        errReason = NSLocalizedString(@"The KML Script doesn't specify a valid model.",@"");
		AddToLog(errReason);
		goto quit;
	}
	if (!romLoadSuccess)
	{
        errReason = NSLocalizedString(@"The KML Script doesn't specify the ROM to use, or the ROM could not be loaded.",@"");
		AddToLog(errReason);
		goto quit;
	}
    if (!mainBitmapValid)
	{
        errReason = NSLocalizedString(@"The KML Script doesn't specify the background bitmap, or bitmap could not be loaded.",@"");
		AddToLog(errReason);
		goto quit;
	}
	if (!romCrcValid)					// build patched ROM fingerprint and check for unpacked data
	{
        errReason = NSLocalizedString(@"Packed ROM image detected.",@"");
		AddToLog(errReason);
//		UnmapRom();						// memory is freed elsewhere
		goto quit;
	}

	PrintfToLog(@"%i Buttons Defined", nButtons);
	PrintfToLog(@"%i Scancodes Defined", nScancodes);
	PrintfToLog(@"%i Annunciators Defined", nAnnunciators);
	bOk = YES;

quit:
	if(bOk)
	{
        AddToLog(NSLocalizedString(@"Press Close to Continue.",@""));
        [self DisplayKMLLog:self];
	}
	else
	{
        if (errReason && outError)
        {
            *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier]
                                            code:-1
                                        userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Calculator template file could not be opened because it contains errors.",@""), NSLocalizedDescriptionKey, [NSString stringWithString: errReason], NSLocalizedFailureReasonErrorKey, nil]];
        }
		AddToLog(NSLocalizedString(@"Press Close to Abort.",@""));
        [self DisplayKMLLog:self];
        [self KillKML];
        [resultWrapped release]; resultWrapped = nil;
        result = nil;
	}

	return [resultWrapped autorelease];
}


- (void)KillKML
{
	nButtons      = 0;
	nScancodes    = 0;
	nAnnunciators = 0;
    romTypeValid    = NO;
    romLoadSuccess  = NO;
    romCrcValid     = NO;
    mainBitmapValid = NO;
    errReason = nil;
}


// Just parses the header (global section)
- (KmlParseResult *)LoadKMLGlobal:(NSString *)filename
{
    NSString  *buf;
	KmlBlock  *pBlock;
    KmlParseResult *blockWrapped = nil;
	DWORD      eToken;

    buf = MapKMLFile(filename);
    [self InitLex:buf];
	pBlock = NULL;
	eToken = [self Lex:LEX_BLOCK];
	if (eToken == TOK_GLOBAL)
	{
		pBlock = [self ParseBlock:(TokenId)eToken];
		if (pBlock) pBlock->pNext = nil;
	}
	[self CleanLex];
    [buf release];
    if (pBlock)
    {
        blockWrapped = [[KmlParseResult alloc] initWithKmlPath: filename];
        [blockWrapped setFirstBlock: pBlock];
    }
	return [blockWrapped autorelease];
}


- (void)InitLex:(NSString *)szScript
{
	nLexLine = 1;
    [scanner release];
    scanner = [[NSScanner alloc] initWithString: szScript];
    [scanner setCharactersToBeSkipped: [NSCharacterSet whitespaceCharacterSet]];
}


- (void)CleanLex
{
	nLexLine = 0;
	nLexInteger = 0;
	szLexString = nil;
    [scanner release]; scanner = nil;
}


- (TokenId)Lex:(UINT)nMode
{
    if ((nMode != LEX_PARAM) && [scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil])
    {
        ++nLexLine;
    }
    if ([scanner scanString:@"#" intoString:nil])
    {
        [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil];
    }

    if ([scanner isAtEnd])
        return TOK_NONE;

    int dummyInt = 0;
    if ([scanner scanInt: &dummyInt])
    {
        nLexInteger = dummyInt;
        return TOK_INTEGER;
    }
    if ([scanner scanString:@"\"" intoString:nil])
    {
        NSString *dummyString = @"";
        [scanner scanUpToString:@"\"" intoString:&dummyString];
        if ([scanner scanString:@"\"" intoString:nil])
        {
            szLexString = [[NSString alloc] initWithString: dummyString];
            return TOK_STRING;
        }
    }
	if ((nMode == LEX_PARAM) && [scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil])
	{
		++nLexLine;
		return TOK_EOL;
	}

	return [self ParseToken:nMode];
}


- (KmlBlock *)IncludeBlocks:(NSString *)szFilename
{
	KmlBlock *pFirst = nil;
    NSString *errmsg = nil;

    pFirst = [self ParseIncludeBlocks:szFilename includeLevel:(++nBlocksIncludeLevel) error:&errmsg];
    if (nil==pFirst)
    {
        if (errmsg)
        {
            PrintfToLog(errmsg);
            [errmsg release];
        }
		[self FatalError];
		return nil;
    }
	return pFirst;
}


- (KmlLine *)IncludeLines:(NSString *)szFilename
{
	KmlLine  *pLine  = nil;
    NSString *errmsg = nil;

    pLine = [self ParseIncludeLines:szFilename includeLevel:(++nLinesIncludeLevel) error:&errmsg];
    if (nil==pLine)
    {
        if (errmsg)
        {
            PrintfToLog(errmsg);
            [errmsg release];
        }
		[self FatalError];
		return nil;
    }
	return pLine;
}


- (KmlBlock *)ParseBlocks
{
	KmlBlock* pFirst = nil;
	KmlBlock* pBlock = nil;
	TokenId   eToken;
    BOOL      success = YES;

	while ((eToken=[self Lex:LEX_BLOCK])!=TOK_NONE)
	{
		if (eToken == TOK_INCLUDE)
		{
			NSString *szFilename;
			eToken = [self Lex:LEX_PARAM];		// get include parameter in 'szLexString'
			if (eToken != TOK_STRING)		// not a string (token don't begin with ")
			{
                errReason = NSLocalizedString(@"Include: string expected as parameter.",@"");
				AddToLog(errReason);
				[self FatalError];
                success = NO;
                break;
			}
			szFilename = szLexString;		// save pointer to allocated memory
			if (pFirst)
				pBlock = pBlock->pNext = [self IncludeBlocks:szLexString];
			else
				pBlock = pFirst = [self IncludeBlocks:szLexString];
//			[szFilename release];			// free memory
			if (pBlock == nil)				// parsing error
            {
                success = NO;
                break;
            }
			while (pBlock->pNext) pBlock=pBlock->pNext;
			continue;
		}
		if (!IsGlobalBlock(eToken))			// check for valid block commands
		{
			PrintfToLog(@"%i: Invalid Block %@.", nLexLine, GetStringOf(eToken));
			[self FatalError];
            success = NO;
            break;
		}
		if (pFirst)
			pBlock = pBlock->pNext = [self ParseBlock:eToken];
		else
			pBlock = pFirst = [self ParseBlock:eToken];
		if (pBlock == nil)
		{
            errReason = NSLocalizedString(@"Invalid block.",@"");
			AddToLog(errReason);
			[self FatalError];
            success = NO;
            break;
		}
	}

    if (success)
    {
        if (pFirst) pBlock->pNext = nil;
        return pFirst;
    }
	if (pFirst) FreeBlocks(pFirst);
	return nil;
}


- (KmlBlock *)ParseBlock:(TokenId)eType
{
	UINT      u1;
	KmlBlock* pBlock;
	TokenId   eToken;

	nLinesIncludeLevel = 0;

	pBlock = (KmlBlock *)calloc(1, sizeof(KmlBlock));
	pBlock->eType = eType;

	u1 = 0;
	while (pLexToken[u1].nLen)
	{
		if (pLexToken[u1].eId == eType) break;
		u1++;
	}
	if (pLexToken[u1].nParams)
	{
		eToken = [self Lex:LEX_COMMAND];
		switch (eToken)
		{
		case TOK_NONE:
            errReason = NSLocalizedString(@"Open Block at End Of File.",@"");
			AddToLog(errReason);
			free(pBlock);
			[self FatalError];
			return nil;
		case TOK_INTEGER:
			if ((pLexToken[u1].nParams&7)!=TYPE_INTEGER)
			{
                errReason = NSLocalizedString(@"Wrong block argument.",@"");
				AddToLog(errReason);
                free(pBlock);
				[self FatalError];
				return nil;
			}
			pBlock->nId = nLexInteger;
			break;
		default:
            errReason = NSLocalizedString(@"Wrong block argument.",@"");
            AddToLog(errReason);
            free(pBlock);
			[self FatalError];
			return nil;
		}
	}

	pBlock->pFirstLine = [self ParseLines];

	if (pBlock->pFirstLine == nil)			// break on ParseLines error
	{
        free(pBlock);
		pBlock = nil;
	}

	return pBlock;
}


- (KmlLine *)ParseLines
{
	KmlLine* pFirst = nil;
	KmlLine* pLine  = nil;
	TokenId  eToken;
	UINT     nLevel = 0;
    BOOL     success = YES;

	while ((eToken = [self Lex:LEX_COMMAND]))
	{
		if (IsGlobalBlock(eToken))			// check for block command
		{
			PrintfToLog(@"%i: Invalid Command %@.", nLexLine, GetStringOf(eToken));
            success = NO;
            break;
		}
		if (IsBlock(eToken)) nLevel++;
		if (eToken == TOK_INCLUDE)
		{
			NSString *szFilename;
			eToken = [self Lex:LEX_PARAM];		// get include parameter in 'szLexString'
			if (eToken != TOK_STRING)		// not a string (token don't begin with ")
			{
                
                errReason = NSLocalizedString(@"Include: string expected as parameter.",@"");
				AddToLog(errReason);
				[self FatalError];
                success = NO;
                break;
			}
			szFilename = szLexString;		// save pointer to allocated memory
			if (pFirst)
			{
				pLine->pNext = [self IncludeLines:szLexString];
			}
			else
			{
				pLine = pFirst = [self IncludeLines:szLexString];
			}
//			[szFilename release];			// free memory
			if (pLine == nil)				// parsing error
            {
                success = NO;
                break;
            }
			while (pLine->pNext) pLine=pLine->pNext;
			continue;
		}
		if (eToken == TOK_END)
		{
			if (nLevel)
			{
				nLevel--;
			}
			else
			{
				if (pLine) pLine->pNext = nil;
				return pFirst;
			}
		}
		if (pFirst)
		{
			pLine = pLine->pNext = [self ParseLine:eToken];
		}
		else
		{
			pLine = pFirst = [self ParseLine:eToken];
		}
		if (pLine == nil)					// parsing error
        {
            success = NO;
            break;
        }
	}

    if (success)
    {
        if (nLinesIncludeLevel)
        {
            if (pLine) pLine->pNext = nil;
            return pFirst;
        }	
    }
	if (pFirst)
	{
		FreeLines(pFirst);
	}
	return nil;
}


- (KmlLine *)ParseLine:(TokenId)eCommand
{
	UINT     i, j;
	DWORD    nParams;
	TokenId  eToken;
	KmlLine* pLine;

	for (i = 0; pLexToken[i].nLen; ++i)
	{
		if (pLexToken[i].eId == eCommand) break;
	}
	if (pLexToken[i].nLen == 0) return nil;

	pLine = (KmlLine *)calloc(1, sizeof(KmlLine));
	pLine->eCommand = eCommand;
	nParams = pLexToken[i].nParams;

	for (j = 0, nParams = pLexToken[i].nParams; TRUE; nParams >>= 3)
    {
		// check for parameter overflow
		_ASSERT(j < ARRAYSIZEOF(pLine->nParam));

        eToken = [self Lex:LEX_PARAM];
        if ((nParams&7)==TYPE_NONE)
        {
            if (eToken != TOK_EOL)
            {
				PrintfToLog(@"%i: Too many parameters for %@ (%i expected).", nLexLine, pLexToken[i].szName, j);
                break;					// free memory of arguments
            }
            return pLine;
        }
        if ((nParams&7)==TYPE_INTEGER)
        {
            if (eToken != TOK_INTEGER)
            {
                PrintfToLog(@"%i: Parameter %i of %@ must be an integer.", nLexLine, j+1, pLexToken[i].szName);
                break;					// free memory of arguments
            }
            pLine->nParam[j++] = nLexInteger;
            continue;
        }
        if ((nParams&7)==TYPE_STRING)
        {
            if (eToken != TOK_STRING)
            {
                PrintfToLog(@"%i: Parameter %i of %@ must be a string.", nLexLine, j+1, pLexToken[i].szName);
                break;					// free memory of arguments
            }
            pLine->nParam[j++] = (DWORD_PTR)szLexString;
            continue;
        }
		_ASSERT(FALSE);						// unknown parameter type
		break;
    }

	// if last argument was string, free it
	if (eToken == TOK_STRING)
    {
        [szLexString release]; szLexString = nil;
    }

	nParams = pLexToken[i].nParams;			// get argument types of command
	for (i=0; i<j; i++)						// handle all scanned arguments
	{
		if ((nParams&7) == TYPE_STRING)		// string type
		{
			[(NSString *)pLine->nParam[i] release];
		}
		nParams >>= 3;						// next argument type
	}

	free(pLine);
	return nil;
}


- (TokenId)ParseToken:(UINT)nMode
{
	UINT j;
    BOOL early_break;
    NSString *token = nil;
    early_break = NO;
    if ((nMode != LEX_PARAM) && [scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil])
    {
        ++nLexLine;
    }
    j = 0;
    while (pLexToken[j].nLen)
    {
        if ([scanner scanString:pLexToken[j].szName intoString:&token])
            break;
        token = nil;
        ++j;
    }
    if (token)
    {
        return pLexToken[j].eId;
    }

	if (bDebug)
	{
		PrintfToLog(@"%i: Undefined token", nLexLine);
	}
	return TOK_NONE;
}


- (void)SkipWhite:(UINT)nMode
{
	UINT i;
    while (![scanner isAtEnd])
    {
        i = 0;
        if ([scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil])
        {
            if ((nMode != LEX_PARAM) && [scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil])
            {
                ++nLexLine;
            }
            continue;
        }
        if ([scanner scanString:@"#" intoString:nil])
        {
            [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil];
            if (nMode != LEX_PARAM) continue;
        }
        break;
    }
}


- (void)FatalError
{
	PrintfToLog(@"Fatal Error at line %i", nLexLine);
}
@end


@implementation KmlParseResult

- (id)initWithKmlPath: (NSString *)path
{
    self = [super init];
    if (self)
    {
        kmlPath = [path retain];
    }
    return self;
}

- (void)dealloc
{
    FreeBlocks(block);
    [mainBitmap release];
    [lcdColors release];
    [kmlPath release];
    [super dealloc];
}

- (void)setFirstBlock:(KmlBlock *)aBlock
{
    block = aBlock;
}

- (NSString *)stringForBlockId:(TokenId)aBlock
                     commandId:(TokenId)aCommand
                       atIndex:(unsigned int)aIndex
{
    return GetStringParam(block, aBlock, aCommand, aIndex);
}

- (void)parsedRomPath:(NSString *)path
{
    romPath = path;
}
- (void)parsedPatchPath:(NSString *)path
{
    patchPath = path;
}
- (void)parsedVKey:(KmlBlock *)aVKey atIndex:(int)aIndex
{
    pVKey[aIndex] = aVKey;
}
- (void)parsedButton:(KmlButton)aButton
{
    pButton[nButtons++] = aButton;
}
- (void)parsedAnnunciator:(KmlAnnunciatorC)aAnnun atIndex:(int)nId
{
    pAnnunciator[nId] = aAnnun;
}
- (void)parsedDebug:(BOOL)aDebug
{
    bDebug = aDebug;
}
- (BOOL)mainBitmapDefined
{
    return (nil != mainBitmap);
}
- (void)parsedMainBitmap:(CalcImage *)aImage
{
    [mainBitmap release];
    mainBitmap = [aImage retain];
}
- (void)parsedBackground:(CalcRect)aRect
{
    background = aRect;
}
- (void)parsedLcdOrigin:(CalcPoint)aPoint
{
    lcdOrigin = aPoint;
}
- (void)parsedLcdScale:(unsigned)v
{
    lcdScale = v;
}
- (void)parsedLcdColorAtIndex:(UINT)nId red:(UINT)nRed green:(UINT)nGreen blue:(UINT)nBlue
{
    if (nil == lcdColors)
        lcdColors = [[NSMutableDictionary alloc] initWithCapacity: 64];
#ifdef __LITTLE_ENDIAN__
    uint32_t c = 0xFF000000|((nBlue&0xFF)<<16)|((nGreen&0xFF)<<8)|((nRed&0xFF));
#else
    uint32_t c = 0x000000FF|((nRed&0xFF)<<24)|((nGreen&0xFF)<<16)|((nBlue&0xFF)<<8);
#endif
    NSNumber *color = [[NSNumber alloc] initWithUnsignedInt: c];
    NSNumber *index = [[NSNumber alloc] initWithUnsignedInt: (nId&0x3F)];
    [lcdColors setObject:color forKey:index];
    [color release];
    [index release];
}

- (NSString *)kmlPath
{
    return kmlPath;
}
- (void)reloadRom
{
    MapRom([romPath UTF8String]);
    PatchRom([patchPath UTF8String]);
}
- (void)reloadButtons:(BYTE *)Keyboard_Row size:(UINT)nSize
{
	UINT i;
	for (i=0; i<nButtons; i++)				// scan all buttons
	{
		if (pButton[i].nOut < nSize)		// valid out code
		{
			// get state of button from keyboard matrix
			pButton[i].bDown = ((Keyboard_Row[pButton[i].nOut] & pButton[i].nIn) != 0);
		}
	}
}
- (KmlBlock **)VKeys
{
    return pVKey;
}
- (KmlButton *)buttons
{
    return pButton;
}
- (KmlAnnunciatorC *)annunciators
{
    return pAnnunciator;
}
- (unsigned)countOfButtons
{
    return nButtons;
}
- (BOOL)debug
{
    return bDebug;
}
- (CalcImage *)mainBitmap
{
    return mainBitmap;
}
- (CalcRect)background
{
    return background;
}
- (CalcPoint)lcdOrigin
{
    return lcdOrigin;
}
- (unsigned)lcdScale
{
    return lcdScale;
}
- (NSDictionary *)lcdColors
{
    return lcdColors;
}
@end


// Appends a string and a newline
void AddToLog(NSString *szString)
{
  // TODO: check this mod
#warning TODO
#ifndef TARGET_OS_IPHONE
//#if !TARGET_OS_IPHONE
    if(nil==szString)
        return;

    [NSController appendLog: szString];
#endif
}


// format is assumed to be a localized string key
// if the format string wasn't found it's used as-is
void PrintfToLog(NSString *format, ...)
{
    NSString *result;
    NSString *localized_format = NSLocalizedString(format, @"");
    // NSLocalizedString will return format unaltered if a
    // localized version wasn't found
	va_list arglist;
    
	va_start(arglist, format);
    result = [[NSString alloc] initWithFormat:localized_format
                                       locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]
                                    arguments:arglist];
    AddToLog(result);
    [result release];
    
    va_end(arglist);
}
