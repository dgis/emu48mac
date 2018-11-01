//
//  CalcBackend.m
//  emu48
//
//  Created by Da Woon Jung on 2009-01-23
//  Copyright 2009 dwj. All rights reserved.
//

#import "CalcBackend.h"
#import "engine.h"
#import "timer.h"
#import "files.h"
#import "stack.h"
#import "external.h"
#import "CalcView.h"
#import "lcd.h"
#import "rawlcd.h"
#import "CalcDebugger.h"
#import "EMU48.H"
#import "IO.H"
#import <sys/stat.h>
#import <sys/mman.h>
#if TARGET_OS_IPHONE
#import <AudioToolbox/AudioToolbox.h>
#endif


CalcBackend *gSharedCalcBackend = nil;

@interface CalcBackend(Private)
- (void)loadEngine;
- (void)unloadEngine;
@end


@implementation CalcBackend

+ (CalcBackend *)sharedBackend
{
    if (nil == gSharedCalcBackend)
        gSharedCalcBackend = [[CalcBackend alloc] init];
    return gSharedCalcBackend;
}

- (void)dealloc
{
    [self stop];
    [state release];
    [backups release];
    [super dealloc];
}

- (void)loadEngine
{
    if (nil == toneGenerator)
        toneGenerator = [[CalcToneGenerator alloc] init];
    if (nil == debugModel)
        debugModel = [[CalcDebugger alloc] init];
    if (nil == timer)
        timer  = [[CalcTimer alloc] init];
    if (nil == engine)
        engine = [[CalcEngine alloc] init];
    
    [self preRun];
}
- (void)unloadEngine
{
    if(engine)
        [engine release]; engine = nil;
    if(timer)
        [timer release];  timer = nil;
    if(debugModel)
        [debugModel release]; debugModel = nil;
    if(toneGenerator)
        [toneGenerator release]; toneGenerator = nil;
}

- (BOOL)makeUntitledCalcWithKml:(NSString *)aFilename error:(NSError **)outError
{
    [self loadEngine];
    
    CalcState *freshState = [[CalcState alloc] initWithKml:aFilename error:outError];
    if (freshState)
    {
        [state release];
        state = freshState;
        return YES;
    }
    else
    {
        [self unloadEngine];
    }
    return NO;
}

// OnViewScript
- (void)changeKml:(id)sender
{
    id path = nil;
    if ([sender respondsToSelector: @selector(representedObject)])
        path = [sender representedObject];
    if (path)
    {
        NSArray *pathComps = [[path stringByDeletingLastPathComponent] pathComponents];
        if ([pathComps count] < 2)
            path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: path];
        NSError *err = nil;
        [state setKmlFileWithStop:path error:&err];
        
        NSView * view = [self calcView];
        if(view && [view window])
        {
            SwitchToState(SM_INVALID);
            [self finishInitWithViewContainer:[view window] lcdClass:[CalcRawLCD class]];
            SwitchToState(SM_RUN);
        }
    }
}

- (void)preRun
{
    if (engine)
    {
        QueryPerformanceFrequency(&lFreq);        // init high resolution counter
        QueryPerformanceCounter(&lAppStart);

        //SetSpeed(NO);
        bool realSpeed = [[NSUserDefaults standardUserDefaults] boolForKey: @"RealSpeed"];
        SetSpeed(realSpeed);
        nState     = SM_RUN;                    // init state must be <> nNextState
        nNextState = SM_INVALID;                // go into invalid state
        [NSThread detachNewThreadSelector:@selector(main) toTarget:engine withObject:nil];
        while (nState!=nNextState) Sleep(0);    // wait for thread initialized
    }
}

- (void)run
{
    if (engine)
    {
        if (pbyRom)
        {
            SwitchToState(SM_RUN);
            isRunning = YES;
        }
    }
}

- (void)stop
{
    SwitchToState(SM_INVALID);
    if(state)
        [state release]; state = nil;
    [self unloadEngine];
    calcView = nil;
    isRunning = NO;
}

- (BOOL)isRunning
{
    return isRunning;
}

- (NSString *)currentModel
{
    return [NSString stringWithFormat:@"%c", cCurrentRomType];
}

- (CalcTimer *)timer
{
    return timer;
}

- (CalcView *)calcView
{
    if ([self initDone])
    {
        return calcView;
    }
    return nil;
}

- (void)setCalcView:(CalcView *)aView
{
    calcView = aView;
}

- (CalcDebugger *)debugModel
{
    return debugModel;
}

- (void)playToneWithFrequency:(DWORD)freq duration:(DWORD)duration
{
    [toneGenerator playToneWithFrequency:freq duration:duration];
}

#if TARGET_OS_IPHONE
- (void)interruptToneWithState:(UInt32)aInterruptState
{
    switch (aInterruptState)
    {
        case kAudioSessionBeginInterruption:
            [toneGenerator release]; toneGenerator = nil;
            break;
        case kAudioSessionEndInterruption:
            if (nil == toneGenerator)
                toneGenerator = [[CalcToneGenerator alloc] init];
            break;
        default:
            break;
    }
}
#endif

- (KmlLine *)If:(KmlLine *)pLine
      condition:(BOOL)bCondition
{
	pLine = pLine->pNext;
	if (bCondition)
	{
		while (pLine)
		{
			if (pLine->eCommand == TOK_END)
			{
				pLine = pLine->pNext;
				break;
			}
			if (pLine->eCommand == TOK_ELSE)
			{
				pLine = SkipLines(pLine, TOK_END);
				break;
			}
			pLine = [self RunLine:pLine];
		}
	}
	else
	{
		pLine = SkipLines(pLine, TOK_ELSE);
		while (pLine)
		{
			if (pLine->eCommand == TOK_END)
			{
				pLine = pLine->pNext;
				break;
			}
			pLine = [self RunLine:pLine];
		}
	}
	return pLine;
}

- (KmlLine *)RunLine:(KmlLine *)pLine
{
	switch (pLine->eCommand)
	{
        case TOK_MAP:
            if (byVKeyMap[pLine->nParam[0]&0xFF]&1)
                [self PressButtonById: (unsigned int)(pLine->nParam[1])];
            else
                [self ReleaseButtonById: (unsigned int)(pLine->nParam[1])];
            break;
        case TOK_PRESS:
            [self PressButtonById: (unsigned int)(pLine->nParam[0])];
            break;
        case TOK_RELEASE:
            [self ReleaseButtonById: (unsigned int)(pLine->nParam[0])];
            break;
//	case TOK_MENUITEM:
//		PostMessage(hWnd, WM_COMMAND, 0x19C40+(pLine->nParam[0]&0xFF), 0);
//		break;
        case TOK_SETFLAG:
            nKMLFlags |= 1<<(pLine->nParam[0]&0x1F);
            break;
        case TOK_RESETFLAG:
            nKMLFlags &= ~(1<<(pLine->nParam[0]&0x1F));
            break;
        case TOK_NOTFLAG:
            nKMLFlags ^= 1<<(pLine->nParam[0]&0x1F);
            break;
        case TOK_IFPRESSED:
            return [self If:pLine condition:byVKeyMap[pLine->nParam[0]&0xFF]];
            break;
        case TOK_IFFLAG:
            return [self If:pLine condition:((nKMLFlags>>(pLine->nParam[0]&0x1F))&1)];
        default:
            break;
	}
	return pLine->pNext;
}


- (void)mouseDownAt:(CalcPoint)aPoint
{
	UINT i;
	for (i=0; i<nButtons; i++)
	{
		if ([self ClipButton:aPoint forId:i])
		{
			if (pButton[i].dwFlags&BUTTON_NOHOLD)
			{
                bClicking = TRUE;
                uButtonClicked = i;
                pButton[i].bDown = TRUE;
                [self DrawButton: i];
                return;
			}
			if (pButton[i].dwFlags&BUTTON_VIRTUAL)
			{
				bClicking = TRUE;
				uButtonClicked = i;
			}
			bPressed = TRUE;				// key pressed
			uLastPressedKey = i;			// save pressed key
			[self PressButton: i];
			return;
		}
	}
}

- (void)rightMouseDownAt:(CalcPoint)aPoint
{
	UINT i;
	for (i=0; i<nButtons; i++)
	{
		if ([self ClipButton:aPoint forId:i])
		{
			if (pButton[i].dwFlags&BUTTON_NOHOLD)
			{
                return;
			}
			if (pButton[i].dwFlags&BUTTON_VIRTUAL)
			{
				return;
			}
			bPressed = TRUE;				// key pressed
			uLastPressedKey = i;			// save pressed key
			[self PressButton: i];
			return;
		}
	}
}

- (void)mouseUpAt:(CalcPoint)aPoint
{
	UINT i;
	if (bPressed)							// emulator key pressed
	{
		[self ReleaseAllButtons];
        return;
	}
	for (i=0; i<nButtons; i++)
	{
		if ([self ClipButton:aPoint forId:i])
		{
			if ((bClicking)&&(uButtonClicked != i)) break;
			[self ReleaseButton :i];
			break;
		}
	}
	bClicking = FALSE;
	uButtonClicked = 0;
}

- (void)runKey:(BYTE)nId pressed:(BOOL)aPressed
{
	if (pVKey[nId])
	{
		KmlLine *line = pVKey[nId]->pFirstLine;
		byVKeyMap[nId] = aPressed;
		while (line) line = [self RunLine: line];
	}
	else
	{
		if ([[state kml] debug]&&aPressed)
		{
			NSString *msgStr = [NSString stringWithFormat: NSLocalizedString(@"Scancode %i",@""), nId];
			InfoMessage([msgStr UTF8String]);
		}
	}
}


- (BOOL)ClipButton:(CalcPoint)aPoint forId:(unsigned)nId
{
	return (pButton[nId].nOx<=aPoint.x)
        && (pButton[nId].nOy<=aPoint.y)
        && (aPoint.x<(pButton[nId].nOx+pButton[nId].nCx))
        && (aPoint.y<(pButton[nId].nOy+pButton[nId].nCy));
}

- (void)DrawButton:(unsigned)nId
{
    drawingButton = &pButton[nId];
    [calcView buttonDrawing];
}

- (BOOL)drawingButtonPressed
{
    return drawingButton ? drawingButton->bDown : NO;
}

- (UINT)drawingButtonType
{
    return drawingButton ? drawingButton->nType : 0;
}

- (CalcRect)drawingButtonRect
{
    CalcRect result = CalcZeroRect;
    if (drawingButton)
        result = CalcMakeRect(drawingButton->nOx, drawingButton->nOy, drawingButton->nCx, drawingButton->nCy);
    return result;
}

- (CalcRect)drawingButtonRectPressed
{
    CalcRect result = CalcZeroRect;
    if (drawingButton)
        result = CalcMakeRect(drawingButton->nDx, drawingButton->nDy, drawingButton->nCx, drawingButton->nCy);
    return result;
}

- (void)PressButton:(unsigned)nId
{
	if (pButton[nId].bDown) return;			// key already pressed -> exit
    
	pButton[nId].bDown = TRUE;
	[self DrawButton: nId];
	if (pButton[nId].nIn)
	{
		KeyboardEvent(TRUE,pButton[nId].nOut,pButton[nId].nIn);
	}
	else
	{
		KmlLine* pLine = pButton[nId].pOnDown;
		while ((pLine)&&(pLine->eCommand!=TOK_END))
		{
			pLine = [self RunLine: pLine];
		}
	}
}

- (void)ReleaseButton:(unsigned)nId
{
	pButton[nId].bDown = FALSE;
	[self DrawButton: nId];
	if (pButton[nId].nIn)
	{
		KeyboardEvent(FALSE,pButton[nId].nOut,pButton[nId].nIn);
	}
	else
	{
		KmlLine* pLine = pButton[nId].pOnUp;
		while ((pLine)&&(pLine->eCommand!=TOK_END))
		{
			pLine = [self RunLine: pLine];
		}
	}
}

- (void)PressButtonById:(unsigned)nId
{
	UINT i;
	for (i=0; i<nButtons; i++)
	{
		if (nId == pButton[i].nId)
		{
			[self PressButton: i];
			return;
		}
	}
}

- (void)ReleaseButtonById:(unsigned)nId
{
	UINT i;
	for (i=0; i<nButtons; i++)
	{
		if (nId == pButton[i].nId)
		{
			[self ReleaseButton: i];
			return;
		}
	}
}

- (void)ReleaseAllButtons
{
	UINT i;
	for (i=0; i<nButtons; i++)				// scan all buttons
	{
		if (pButton[i].bDown)				// button pressed
			[self ReleaseButton: i];		// release button
	}
    
	bPressed = FALSE;						// key not pressed
	bClicking = FALSE;						// var uButtonClicked not valid (no virtual or nohold key)
	uButtonClicked = 0;						// set var to default
}


- (void)onPowerKey
{
    KeyboardEvent(TRUE,0,0x8000);
    Sleep(200);
    KeyboardEvent(FALSE,0,0x8000);
    Sleep(200);
}

- (BOOL)initDone
{
    return initDone;
}

- (void)setInitDone:(BOOL)value
{
    initDone = value;
}


- (void)finishInitWithViewContainer:(CalcViewContainer *)aViewContainer
                           lcdClass:(Class)aLcdClass
{
    KmlParseResult *kml = [state kml];
    pVKey     = [kml VKeys];
    pButton   = [kml buttons];
    nButtons  = [kml countOfButtons];

    CalcRect bg = [kml background];
    if (bg.size.width>0.f && bg.size.height>0.f &&
        [aViewContainer respondsToSelector:@selector(setContentSize:)])
    {
        [aViewContainer setContentSize: bg.size];
    }
    [calcView setMainBitmap:[kml mainBitmap] atOrigin:bg.origin];

    KmlAnnunciatorC *pAnnunciator = [kml annunciators];
    if(pAnnunciator)
    {
        int i;
        for (i = 0; i < 6; ++i)
        {
            // position of annunciator
            CalcRect annunRect = CalcMakeRect(pAnnunciator[i].nDx, pAnnunciator[i].nDy, pAnnunciator[i].nCx, pAnnunciator[i].nCy);
            [calcView setAnnunciatorRect:annunRect atIndex:i isOn:YES];
            // position of background
            annunRect.origin.x = pAnnunciator[i].nOx;
            annunRect.origin.y = pAnnunciator[i].nOy;
            [calcView setAnnunciatorRect:annunRect atIndex:i isOn:NO];
        }
    }
    [calcView setLCD:[[[aLcdClass alloc] initWithScale:[kml lcdScale] colors:[kml lcdColors]] autorelease] atOrigin:[kml lcdOrigin]];
    [calcView setLcdGrayscaleMode: [[NSUserDefaults standardUserDefaults] boolForKey: @"Grayscale"]];
#if TARGET_OS_IPHONE
    [calcView setNeedsDisplay];
#else
    [calcView setNeedsDisplay: YES];
#endif

    [self setInitDone: YES];
}

#pragma mark -
#pragma mark Open/Save state

- (BOOL)readFromState:(NSString *)statePath error:(NSError **)outError
{
    [self loadEngine];
    CalcState *freshState = [[CalcState alloc] initWithFile:statePath error:outError];
    if (freshState)
    {
        [state release];
        state = freshState;
        return YES;
    }
    else
    {
        [self unloadEngine];
    }
    return NO;
}

- (BOOL)saveStateAs:(NSString *)aStateFile error:(NSError **)outError
{
    return [state saveAs:aStateFile error:outError];
}

#pragma mark -
#pragma mark Import/Export object

- (BOOL)readFromObject:(NSString *)aObjectFile error:(NSError **)outError
{
    return [self readFromObjectURL:[NSURL URLWithString:aObjectFile] error:outError];
}

- (BOOL)readFromObjectURL:(NSURL *)aObjectURL error:(NSError **)outError
{
    NSData *data = [[NSData alloc] initWithContentsOfURL:aObjectURL options:(NSMappedRead | NSUncachedRead) error:outError];
    CalcStack *stack = nil;
    if (data)
    {
        stack = [[CalcStack alloc] initWithObject: data];
        [stack pasteObjectRepresentation: outError];
        [stack release];
        [data release];
        return (nil == outError);
    }
    return NO;
}

- (BOOL)saveObjectAs:(NSString *)aObjectFile error:(NSError **)outError
{
    return [self saveObjectAsURL:[NSURL URLWithString:aObjectFile] error:outError];
}

- (BOOL)saveObjectAsURL:(NSURL *)aObjectURL error:(NSError **)outError
{
    BOOL result = NO;
    CalcStack *stack = [[CalcStack alloc] initWithError: outError];
    if (stack)
    {
        NSData *object = [stack objectRepresentation];
        result = [object writeToURL:aObjectURL options:NSAtomicWrite error:outError];
        [stack release];
    }
    return result;
}

#pragma mark -
#pragma mark Backup/Restore

- (void)backup
{
	UINT nOldState;
	if (pbyRom == NULL) return;
	nOldState = SwitchToState(SM_INVALID);
    if (nil == backups) backups = [[NSMutableArray alloc] init];
    // TODO: Maybe implement multiple backups?
    [backups removeAllObjects];
    NSDictionary *backup = [[NSDictionary alloc] initWithObjectsAndKeys:
                            [NSDate date], @"date",
                            [[[CalcBackup alloc] initWithState: state] autorelease], @"state",
                            nil];
    [backups addObject: backup];
    [backup release];
	SwitchToState(nOldState);
}

- (void)restore
{
	SwitchToState(SM_INVALID);
    if (backups && [backups count] > 0)
    {
        NSDictionary *backup = [backups objectAtIndex: 0];
        [[backup objectForKey: @"state"] restoreToState: state];
    }
	if (pbyRom) SwitchToState(SM_RUN);
}
@end
