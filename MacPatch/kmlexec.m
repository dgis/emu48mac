//
//  kmlexec.m
//  emu48
//
//  Separates out Initxxx methods from the kml parser into a category
//
//  Created by Da Woon Jung on Wed Feb 25 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

#import "kmlparser.h"
#import "CalcBackend.h"
#import "CalcView.h"
#import "pch.h"
#import "EMU48.H"
#import "files.h"


@implementation KmlParser (Init)

// Runs parsed global section commands
- (void)InitGlobal:(KmlBlock *)pBlock
{
	KmlLine* pLine = pBlock->pFirstLine;
	while (pLine)
	{
		switch (pLine->eCommand)
		{
            case TOK_TITLE:
                PrintfToLog(@"Title: %@", (NSString *)pLine->nParam[0]);
                break;
            case TOK_AUTHOR:
                PrintfToLog(@"Author: %@", (NSString *)pLine->nParam[0]);
                break;
            case TOK_PRINT:
                AddToLog((NSString *)pLine->nParam[0]);
                break;
            case TOK_HARDWARE:
                PrintfToLog(@"Hardware Platform: %@", (NSString *)pLine->nParam[0]);
                break;
            case TOK_MODEL:
                if ((NSString *)pLine->nParam[0] && [(NSString *)pLine->nParam[0] length]>0)
                {
                    cCurrentRomType = (BYTE)[(NSString *)pLine->nParam[0] characterAtIndex: 0];
                    romTypeValid = isModelValid(cCurrentRomType);
                    PrintfToLog(@"Calculator Model : %c", cCurrentRomType);
                }
                break;
            case TOK_CLASS:
                nCurrentClass = (UINT)(pLine->nParam[0]);
                PrintfToLog(@"Calculator Class : %u", nCurrentClass);
                break;
            case TOK_DEBUG:
                {
                    bDebug = pLine->nParam[0]&1;
                    if ([delegate respondsToSelector:@selector(parsedDebug:)])
                    {
                        [delegate parsedDebug: bDebug];
                    }
                    PrintfToLog(@"Debug %@", bDebug?@"On":@"Off");
                }
                break;
            case TOK_ROM:
                if (pbyRom != NULL)
                {
                    PrintfToLog(@"Rom %@ Ignored.", (NSString *)pLine->nParam[0]);
                    AddToLog(NSLocalizedString(@"Please put only one Rom command in the Global block.",@""));
                    break;
                }
                if ([delegate respondsToSelector:@selector(parsedRomPath:)])
                {
                    [delegate parsedRomPath: (NSString *)pLine->nParam[0]];
                }
                if(!MapRom([(NSString *)pLine->nParam[0] UTF8String]))
                {
                    PrintfToLog(@"Cannot open Rom %@", (NSString *)pLine->nParam[0]);
                    break;
                }

                romLoadSuccess = (pbyRom != nil);
                PrintfToLog(@"Rom %@ Loaded.", (NSString *)pLine->nParam[0]);
                break;
            case TOK_PATCH:
                if (pbyRom == NULL)
                {
                    PrintfToLog(@"Patch %@ ignored.", (NSString *)pLine->nParam[0]);
                    AddToLog(NSLocalizedString(@"Please put the Rom command before any Patch.",@""));
                    break;
                }

                if ([delegate respondsToSelector:@selector(parsedPatchPath:)])
                {
                    [delegate parsedPatchPath: (NSString *)pLine->nParam[0]];
                }
                if (PatchRom([(NSString *)pLine->nParam[0] UTF8String]))
                    PrintfToLog(@"Patch %@ Loaded", (NSString *)pLine->nParam[0]);
                else
                    PrintfToLog(@"Patch %@ is Wrong or Missing", (NSString *)pLine->nParam[0]);
                break;
            case TOK_BITMAP:
                if ([delegate respondsToSelector:@selector(mainBitmapDefined)] &&
                    [delegate mainBitmapDefined])
                {
                    PrintfToLog(@"Bitmap %@ Ignored.", (NSString *)pLine->nParam[0]);
                    AddToLog(NSLocalizedString(@"Please put only one Bitmap command in the Global block.",@""));
                    break;
                }
                {
                    CalcImage *mainBitmap = nil;
                    if ((mainBitmap = [CalcView CreateMainBitmap:(NSString *)pLine->nParam[0]]))
                    {
                        if ([delegate respondsToSelector:@selector(parsedMainBitmap:)])
                        {
                            [delegate parsedMainBitmap: mainBitmap];
                        }
                        mainBitmapValid = YES;
                        PrintfToLog(@"Bitmap %@ Loaded.", (NSString *)pLine->nParam[0]);
                        break;
                    }
                }
                PrintfToLog(@"Cannot Load Bitmap %@.", (NSString *)pLine->nParam[0]);
                break;
            default:
                PrintfToLog(@"Command %@ Ignored in Block %@", GetStringOf(pLine->eCommand), GetStringOf(pBlock->eType));
		}
		pLine = pLine->pNext;
	}

    if (romLoadSuccess)
    {
        romCrcValid = CrcRom(&wRomCrc);
    }
}


- (KmlLine *)InitAnnunciator:(KmlBlock *)pBlock
{
	KmlLine* pLine = pBlock->pFirstLine;
    KmlAnnunciatorC annunciator;
	UINT nId = pBlock->nId-1;
	if (nId >= 6)
	{
		PrintfToLog(@"Wrong Annunciator Id %i", nId);
		return nil;
	}
    memset(&annunciator, 0, sizeof(annunciator));
	++nAnnunciators;
	while (pLine)
	{
		switch (pLine->eCommand)
		{
		case TOK_OFFSET:
            annunciator.nOx = (unsigned int)(pLine->nParam[0]);
            annunciator.nOy = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_DOWN:
			annunciator.nDx = (unsigned int)(pLine->nParam[0]);
			annunciator.nDy = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_SIZE:
			annunciator.nCx = (unsigned int)(pLine->nParam[0]);
			annunciator.nCy = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_END:
			return pLine;
		default:
			PrintfToLog(@"Command %@ Ignored in Block %@", GetStringOf(pLine->eCommand), GetStringOf(pBlock->eType));
		}
		pLine = pLine->pNext;
	}

    if ([delegate respondsToSelector:@selector(parsedAnnunciator:atIndex:)])
    {
        [delegate parsedAnnunciator:annunciator atIndex:nId];
    }
	return nil;
}


- (KmlLine *)InitBackground:(KmlBlock *)pBlock
{
	KmlLine* pLine = pBlock->pFirstLine;
    CalcRect rect;
    memset(&rect, 0, sizeof(rect));
	while (pLine)
	{
		switch (pLine->eCommand)
		{
		case TOK_OFFSET:
            rect.origin.x = pLine->nParam[0];
			rect.origin.y = pLine->nParam[1];
			break;
		case TOK_SIZE:
			rect.size.width  = pLine->nParam[0];
			rect.size.height = pLine->nParam[1];
			break;
		case TOK_END:
            // Blocks never contain TOK_ENDs
			return pLine;
		default:
			PrintfToLog(@"Command %@ Ignored in Block %@", GetStringOf(pLine->eCommand), GetStringOf(pBlock->eType));
		}
		pLine = pLine->pNext;
	}

    if ([delegate respondsToSelector:@selector(parsedBackground:)])
    {
        [delegate parsedBackground: rect];
    }
	return nil;
}


- (void)InitButton:(KmlBlock *)pBlock
{
	KmlLine* pLine = pBlock->pFirstLine;
    KmlButton button;
	UINT nLevel = 0;
	if (nButtons>=256)
	{
		AddToLog(NSLocalizedString(@"Only the first 256 buttons will be defined.",@""));
		return;
	}

    memset(&button, 0, sizeof(button));
    button.nId = pBlock->nId;
    button.bDown = NO;
    button.nType = 0; // default : user defined button

	while (pLine)
	{
		if (nLevel)
		{
			if (IsBlock(pLine->eCommand)) nLevel++;
			if (pLine->eCommand == TOK_END) nLevel--;
			pLine = pLine->pNext;
			continue;
		}
		if (IsBlock(pLine->eCommand)) nLevel++;
		switch (pLine->eCommand)
		{
		case TOK_TYPE:
			button.nType = (unsigned int)(pLine->nParam[0]);
			break;
		case TOK_OFFSET:
			button.nOx = (unsigned int)(pLine->nParam[0]);
			button.nOy = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_DOWN:
			button.nDx = (unsigned int)(pLine->nParam[0]);
			button.nDy = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_SIZE:
			button.nCx = (unsigned int)(pLine->nParam[0]);
			button.nCy = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_OUTIN:
			button.nOut = (unsigned int)(pLine->nParam[0]);
			button.nIn  = (unsigned int)(pLine->nParam[1]);
			break;
		case TOK_ONDOWN:
			button.pOnDown = pLine;
			break;
		case TOK_ONUP:
			button.pOnUp = pLine;
			break;
		case TOK_NOHOLD:
			button.dwFlags &= ~(BUTTON_VIRTUAL);
			button.dwFlags |= BUTTON_NOHOLD;
			break;
		case TOK_VIRTUAL:
			button.dwFlags &= ~(BUTTON_NOHOLD);
			button.dwFlags |= BUTTON_VIRTUAL;
			break;
		default:
			PrintfToLog(@"Command %@ Ignored in Block %@ %i", GetStringOf(pLine->eCommand), GetStringOf(pBlock->eType), pBlock->nId);
		}
		pLine = pLine->pNext;
	}
	if (nLevel)
		PrintfToLog(@"%i Open Block(s) in Block %@ %i", nLevel, GetStringOf(pBlock->eType), pBlock->nId);

    if ([delegate respondsToSelector: @selector(parsedButton:)])
    {
        [delegate parsedButton:button];
    }
	++nButtons;
}


- (KmlLine *)InitLcd:(KmlBlock *)pBlock
{
	KmlLine* pLine = pBlock->pFirstLine;
	while (pLine)
	{
		switch (pLine->eCommand)
		{
		case TOK_OFFSET:
            if ([delegate respondsToSelector:@selector(parsedLcdOrigin:)])
            {
                [delegate parsedLcdOrigin: CalcMakePoint(pLine->nParam[0], pLine->nParam[1])];
            }
			break;
		case TOK_ZOOM:
            if ([delegate respondsToSelector:@selector(parsedLcdScale:)])
            {
                unsigned nLcdDoubled = (unsigned int)(pLine->nParam[0]);
                if (nLcdDoubled != 1 && nLcdDoubled != 2 && nLcdDoubled != 3 && nLcdDoubled != 4)
                    nLcdDoubled = 1;
                [delegate parsedLcdScale: nLcdDoubled];
            }
			break;
		case TOK_COLOR:
            if ([delegate respondsToSelector:@selector(parsedLcdColorAtIndex:red:green:blue:)])
            {
                [delegate parsedLcdColorAtIndex:(unsigned int)(pLine->nParam[0])
                                            red:(unsigned int)(pLine->nParam[1])
                                          green:(unsigned int)(pLine->nParam[2])
                                           blue:(unsigned int)(pLine->nParam[3])];
            }
			break;
		case TOK_END:
			return pLine;
		default:
			PrintfToLog(@"Command %@ Ignored in Block %@", GetStringOf(pLine->eCommand), GetStringOf(pBlock->eType));
		}
		pLine = pLine->pNext;
	}
	return nil;
}
@end
