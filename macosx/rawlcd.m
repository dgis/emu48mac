//
//  rawlcd.m
//  emu48
//
//  Image-based CalcLCD implementation that draws
//  to a raw internal image rep
//
//  Created by Da Woon Jung on Thu Feb 26 2004.
//  Copyright (c) 2004 dwj. All rights reserved.
//

#import "rawlcd.h"
#import "pch.h"
#import "EMU48.H"
#import "IO.H"
#import "stack.h"

extern CHIPSET Chipset;

#define NOCOLORSGRAY    8
#define NOCOLORSBW      2

#define B 0
#define W 0xFFFFFFFF
#define I 0xFFFFFFFF

#define LCD_ROW		(36*4)					// max. pixel per line

#define GRAYMASK(c)	(((((c)-1)>>1)<<24) \
                    |((((c)-1)>>1)<<16) \
                    |((((c)-1)>>1)<<8)  \
                    |((((c)-1)>>1)))

#define DIBWORD4(d,p)   *(d) = ((*(d) & graymask) << 1) | (p)


@interface CalcRawLCD (Private)
- (void)BuildPattern;
- (void)InitColors:(NSDictionary *)aColors;
@end

@implementation CalcRawLCD

- (id)initWithScale:(unsigned)aScale colors:(NSDictionary *)aColors
{
    lcdScale = (aScale>0) ? aScale : 1;
    CGSize size = computeLCDSize(lcdScale);
    NSRect frame = NSMakeRect(0, 0, size.width, size.height);
    self = [super initWithFrame:frame];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide:LCD_ROW pixelsHigh:SCREENHEIGHT bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:4*8];

    if (rep)
    {
        img = [[NSImage alloc] initWithSize: NSMakeSize([rep pixelsWide], [rep pixelsHigh])];
        if (img)
        {
            //[img setDataRetained: YES];
            [img addRepresentation: rep];
            [rep release];
        }
        else
        {
            [rep release];
            return nil;
        }
        lcd = [rep bitmapData]; //(LPBYTE)malloc(4 * LCD_ROW * SCREENHEIGHT);
    }

    [self BuildPattern];
    [self InitColors: aColors];
    [self SetGrayscaleMode: NO];
    return self;
}

- (void)dealloc
{
    if (graylcd)
        free(graylcd);
    [img release];
    [super dealloc];
}

- (void)BuildPattern
{
    WORD i,j;
    for (i=0; i<16; ++i)
    {
        LcdPattern[i] = 0;
#ifdef __LITTLE_ENDIAN__
        for (j=8; j>0; j>>=1)
        {
            LcdPattern[i] = (LcdPattern[i] << 8) | ((i&j) != 0);
        }
#else
        for (j=1; j<16; j<<=1)
        {
            LcdPattern[i] = (LcdPattern[i] << 8) | ((i&j) != 0);
        }
#endif
    }
}

- (void)UpdateContrast:(unsigned char)byContrast;
{
    RGBQUAD c, b;
    int i, nColors;
    
    const int nCAdj[] = { 0, 1, 1, 2, 1, 2, 2, 3 };
    if ((Chipset.IORam[BITOFFSET] & DON) == 0) byContrast = 0;

    c = *(RGBQUAD *)&KmlColors[byContrast];      // pixel on color
    b = *(RGBQUAD *)&KmlColors[byContrast+32];   // pixel off color
    
    if (I == *(DWORD *)&b) b = *(RGBQUAD *)&KmlColors[0];
    
    nColors = grayscale ? (NOCOLORSGRAY-1) : (NOCOLORSBW-1);
    _ASSERT(nColors <= ARRAYSIZEOF(nCAdj));
    
    for (i = 0; i <= nColors; ++i)
    {
        LcdColors[i] = b;
        LcdColors[i].rgbRed   += ((int) c.rgbRed   - (int) b.rgbRed)   * nCAdj[i] / nCAdj[nColors];
        LcdColors[i].rgbGreen += ((int) c.rgbGreen - (int) b.rgbGreen) * nCAdj[i] / nCAdj[nColors];
        LcdColors[i].rgbBlue  += ((int) c.rgbBlue  - (int) b.rgbBlue)  * nCAdj[i] / nCAdj[nColors];
    }
}

- (void)InitColors:(NSDictionary *)aColors
{
    const DWORD defaultColors[64] = {
        W,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,
        B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,
        I,I,I,I,I,I,I,I,I,I,I,I,I,I,I,I,
        I,I,I,I,I,I,I,I,I,I,I,I,I,I,I,I
    };
    ZeroMemory(LcdColors, sizeof(LcdColors));
    memcpy(KmlColors, defaultColors, sizeof(KmlColors));
    if (aColors)
    {
        NSEnumerator *e = [aColors keyEnumerator];
        id index;
        NSNumber *color;
        while ((index = [e nextObject]))
        {
            color = [aColors objectForKey: index];
            if (color)
                KmlColors[[index unsignedIntValue]] = [color unsignedIntValue];
        }
    }
}

- (void)SetGrayscaleMode:(BOOL) bMode
{
	if ((grayscale = bMode))
	{
		// set pixel update mask
		graymask = GRAYMASK(NOCOLORSGRAY);
        if (nil == graylcd)
            graylcd = (LPBYTE)calloc(1, 4 * LCD_ROW * SCREENHEIGHT);
	}
	else
	{
		// set pixel update mask
		graymask = GRAYMASK(NOCOLORSBW);
        if (graylcd)
        {
            free(graylcd);
            graylcd = nil;
        }
	}
	[self UpdateContrast: Chipset.contrast];
}


- (BOOL)isOpaque
{
    return YES;
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect]; //++

    NSRect dstRect = rect;
    rect.origin.x /= lcdScale;
    rect.origin.y /= lcdScale;
    rect.size.width  /= lcdScale;
    rect.size.height /= lcdScale;
    // Real calculator doesn't do antialiasing so we don't either
    [[NSGraphicsContext currentContext] setImageInterpolation: NSImageInterpolationNone];
//++    [img drawInRect:dstRect fromRect:rect operation:NSCompositeCopy fraction:1.0];
//++
    NSBitmapImageRep * imgRep = (NSBitmapImageRep*)[[img representations] objectAtIndex: 0];
    NSDictionary * dict = [NSDictionary dictionary];
    NSData * imageData = [imgRep representationUsingType: NSBitmapImageFileTypePNG properties: dict];
    NSImage * img2 = [[NSImage alloc] initWithData:(NSData *)imageData];
    [img2 drawInRect:dstRect fromRect:rect operation:NSCompositingOperationCopy fraction:1.0];
    [img2 release];
}

- (void)UpdateMain
{
	UINT  x, y;
	BYTE  *p;
    DWORD *gp;
    RGBQUAD *dp;
	DWORD d;

#if defined DEBUG_DISPLAY
	{
		NSLog(@"%.5x: Update Main Display", Chipset.pc);
	}
#endif

	if (!(Chipset.IORam[BITOFFSET]&DON)) return;

    p = lcd+(4*Chipset.d0size*LCD_ROW);	// bitmap offset
    dp = (RGBQUAD *)p;
    gp = (DWORD *)graylcd;
    d = Chipset.start1;					// pixel offset counter
    for (y = 0; y < MAINSCREENHEIGHT; ++y)
    {
        // read line with actual start1 address!!
        Npeek(Buf,d,36);
        for (x = 0; x < 36; ++x)	// every 4 pixel
        {
            DWORD x0 = LcdPattern[Buf[x]];
            if (grayscale)
            {
                x0 = DIBWORD4(gp,x0); ++gp;
            }
            *dp++ = LcdColors[((BYTE*)&x0)[0]];
            *dp++ = LcdColors[((BYTE*)&x0)[1]];
            *dp++ = LcdColors[((BYTE*)&x0)[2]];
            *dp++ = LcdColors[((BYTE*)&x0)[3]];
        }
        d+=Chipset.width;
    }

    // BitBlt: destbuf, xdest, ydest, wdest, hdest,
    // srcbuf, xsrc, ysrc, op (copy)
    [self setNeedsDisplayInRect: NSMakeRect(0., (SCREENHEIGHT-Chipset.d0size-MAINSCREENHEIGHT)*lcdScale, 131.*lcdScale, MAINSCREENHEIGHT*lcdScale)];
}

- (void)UpdateMenu
{
	UINT  x, y;
	BYTE  *p;
    DWORD *gp;
    RGBQUAD *dp;
	DWORD d;

#if defined DEBUG_DISPLAY
	NSLog(@"%.5x: Update Menu Display",Chipset.pc);
#endif

	if (!(Chipset.IORam[BITOFFSET]&DON)) return;
	if (MENUHEIGHT==0) return;				// menu disabled

	// calculate bitmap offset
	p = lcd + ((Chipset.d0size+MAINSCREENHEIGHT)*LCD_ROW*4);
    dp = (RGBQUAD *)p;
    if (grayscale)
        gp = (DWORD *)(graylcd + ((Chipset.d0size+MAINSCREENHEIGHT)*LCD_ROW*4));
	d = Chipset.start2;						// pixel offset counter
    for (y = 0; y < MENUHEIGHT; ++y)
    {
        Npeek(Buf,d,34);	// 34 nibbles are viewed
        for (x = 0; x < 34; ++x)		// every 4 pixel
        {
            DWORD x0 = LcdPattern[Buf[x]];
            if (grayscale)
            {
                x0 = DIBWORD4(gp,x0); ++gp;
            }
            *dp++ = LcdColors[((BYTE*)&x0)[0]];
            *dp++ = LcdColors[((BYTE*)&x0)[1]];
            *dp++ = LcdColors[((BYTE*)&x0)[2]];
            *dp++ = LcdColors[((BYTE*)&x0)[3]];
        }
        // adjust pointer to 36 DIBPIXEL drawing calls
        dp+=(36-34)*4;
        if (grayscale) gp+=(36-34)*4;
        d+=34;
    }
    [self setNeedsDisplayInRect: NSMakeRect(0., (SCREENHEIGHT-MAINSCREENHEIGHT-Chipset.d0size-MENUHEIGHT)*lcdScale, 131.*lcdScale, MENUHEIGHT*lcdScale)];
}

- (void)RefreshDisp0
{
	UINT x, y;
	BYTE *p;
    DWORD *gp;
    RGBQUAD *dp;
	BYTE* d = Chipset.d0memory;
    
#if defined DEBUG_DISPLAY
    NSLog(@"%.5x: Update header Display",Chipset.pc);
#endif
    
	if (!(Chipset.IORam[BITOFFSET]&DON)) return;
    
	// calculate bitmap offset
    p = lcd;
    dp = (RGBQUAD *)p;
    if (grayscale)
        gp = (DWORD *)graylcd;
	for (y = 0; y<Chipset.d0size; ++y)
	{
		memcpy(Buf,d,34);				// 34 nibbles are viewed
		for (x=0; x<36; ++x)			// every 4 pixel
		{
            DWORD x0 = LcdPattern[Buf[x]];
            if (grayscale)
            {
                x0 = DIBWORD4(gp,x0); ++gp;
            }
            *dp++ = LcdColors[((BYTE*)&x0)[0]];
            *dp++ = LcdColors[((BYTE*)&x0)[1]];
            *dp++ = LcdColors[((BYTE*)&x0)[2]];
            *dp++ = LcdColors[((BYTE*)&x0)[3]];
		}
		d+=34;
	}
    [self setNeedsDisplayInRect: NSMakeRect(0., (SCREENHEIGHT-Chipset.d0size)*lcdScale, 131.*lcdScale, Chipset.d0size*lcdScale)];
}

- (void)WriteToMain:(CalcLCDWriteArgument *)args
{
    unsigned char *a;
    uint32_t d;
    uint32_t s;
	UINT x0, x;
	UINT y0, y;
	DWORD *p;
    RGBQUAD *dp;
    DWORD p0;

	INT  lWidth = abs(Chipset.width);		// display width

	if (grayscale)
	{
		return;
	}

#if defined DEBUG_DISPLAY
	NSLog(@"%.5x: Write Main Display...",Chipset.pc);
#endif

	if (!(Chipset.IORam[BITOFFSET]&DON)) return;	// display off
	if (MAINSCREENHEIGHT == 0) return;				// menu disabled

    a = [args pointer];
    d = [args offset];
    s = [args count];
	d -= Chipset.start1;					// nibble offset to DISPADDR (start of display)
	y0 = y = (d / lWidth) + Chipset.d0size;		// bitmap row
	x0 = x = d % lWidth;					// bitmap coloumn
	p = (DWORD*)(lcd + 4*y0*LCD_ROW + 4*x0*sizeof(*p));
    dp = (RGBQUAD *)p;

#if defined DEBUG_DISPLAY
    NSLog(@"%.5x: Write Main Display %x,%u",Chipset.pc,d,s);
#endif

	// outside main display area
    //	_ASSERT(y0 >= (INT)Chipset.d0size && y0 < (INT)(MAINSCREENHEIGHT+Chipset.d0size));
	if (!(y0 >= (INT)Chipset.d0size && y0 < (INT)(MAINSCREENHEIGHT+Chipset.d0size))) return;

	while (s--)								// loop for nibbles to write
	{
		if (x<36)							// only fill visible area
		{
            p0 = LcdPattern[*a];
            *dp++ = LcdColors[((BYTE*)&p0)[0]];
            *dp++ = LcdColors[((BYTE*)&p0)[1]];
            *dp++ = LcdColors[((BYTE*)&p0)[2]];
            *dp++ = LcdColors[((BYTE*)&p0)[3]];
		}
		a++;								// next value to write
		x++;								// next x position
		if (((INT) x==lWidth)&&s)			// end of display line
		{
			x = 0;							// first coloumn
			y++;							// next row
			if (y == (INT) MAINSCREENHEIGHT+Chipset.d0size) break;
			// recalculate bitmap memory position of new line
			p = (DWORD*) (lcd+4*y*LCD_ROW);  // CdB for HP: add 64/80 ligne display for apples
            dp = (RGBQUAD *)p;
		} else p+=4;
	}
	if (y==y0) y++;
}

- (void)WriteToMenu:(CalcLCDWriteArgument *)args
{
    unsigned char *a;
    uint32_t d;
    uint32_t s;
	UINT x0, x;
	UINT y0, y;
	DWORD *p;
    RGBQUAD *dp;
    DWORD p0;

	if (grayscale)
	{
		return;
	}

#if defined DEBUG_DISPLAY
	NSLog(@"%.5x: Write Menu Display",Chipset.pc);
#endif

	if (!(Chipset.IORam[BITOFFSET]&DON)) return;	// display off
	if (MENUHEIGHT == 0) return;				// menu disabled

    a = [args pointer];
    d = [args offset];
    s = [args count];
	d -= Chipset.start2;					// nibble offset to DISPADDR (start of display)
	y0 = y = (d / 34) + MAINSCREENHEIGHT+Chipset.d0size;         	// bitmap row
	x0 = x = d % 34;                                        	// bitmap coloumn
	p = (DWORD*)(lcd + 4*y0*LCD_ROW + 4*x0*sizeof(*p));
    dp = (RGBQUAD *)p;
    
#if defined DEBUG_DISPLAY
    NSLog(@"%.5x: Write Menu Display %x,%u",Chipset.pc,d,s);
#endif

	// outside menu display area
    //	_ASSERT(y0 >= (INT)(Chipset.d0size+MAINSCREENHEIGHT) && y0 < (INT)(SCREENHEIGHT));
	if (!(y0 >= (UINT)(Chipset.d0size+MAINSCREENHEIGHT) && y0 < (UINT)(SCREENHEIGHT))) return;
    
	while (s--)								// loop for nibbles to write
	{
		if (x<36)							// only fill visible area
		{
            p0 = LcdPattern[*a];
            *dp++ = LcdColors[((BYTE*)&p0)[0]];
            *dp++ = LcdColors[((BYTE*)&p0)[1]];
            *dp++ = LcdColors[((BYTE*)&p0)[2]];
            *dp++ = LcdColors[((BYTE*)&p0)[3]];
		}
		a++;								// next value to write
		x++;								// next x position
		if ((x==34)&&s)					// end of display line
		{
			x = 0;							// first coloumn
			y++;							// next row
			if (y == SCREENHEIGHTREAL) break;
			// recalculate bitmap memory position of new line
			p=(DWORD*)(lcd+4*y*LCD_ROW);  // CdB for HP: add 64/80 ligne display for apples
            dp = (RGBQUAD *)p;
		} else p+=4;
	}
	if (y==y0) y++;
}

//- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
//{
//    return NSDragOperationCopy;
//}

-(NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    return NSDragOperationCopy;
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    NSPasteboard *pb = [NSPasteboard pasteboardWithName: NSPasteboardNameDrag];
    NSError *err = nil;
    CalcStack *stack = [[CalcStack alloc] initWithError: &err];
    if (nil == stack)
        return;
    BOOL copied = [stack copyToPasteboard: pb];
    [stack release];
    if (!copied)
        return;

    NSRect dragRect = NSZeroRect;
    NSRect srcRect;
    NSPoint dragPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    dragRect.size = [img size];
    dragRect.size.width = 131.;
    srcRect = dragRect;
    dragRect.size.width  *= lcdScale;
    dragRect.size.height *= lcdScale;
    dragPoint.x -= dragRect.size.width*0.5;
    dragPoint.y -= dragRect.size.height*0.5;
    NSImage *dragImage = [[[NSImage alloc] initWithSize: dragRect.size]  autorelease];
    [dragImage lockFocus];
    [img drawInRect:dragRect fromRect:srcRect operation:NSCompositingOperationSourceOver fraction:0.5];
    [dragImage unlockFocus];
    [self dragImage:dragImage at:dragPoint offset:NSZeroSize event:theEvent pasteboard:pb source:self slideBack:YES];
}
@end
