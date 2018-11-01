//
//  files.m
//  emu48
//
//  Adapted from files.c by Da-Woon Jung on 2009-03-27.
//

#import "pch.h"
#import "EMU48.H"
#import "IO.H"
#import "DEBUGGER.H"
#import "I28F160.H"
#import "files.h"
#import <sys/stat.h>
#import <sys/mman.h>
#import <fcntl.h>


// document signatures
static BYTE pbySignatureA[16] = "Emu38 Document\xFE";
static BYTE pbySignatureB[16] = "Emu39 Document\xFE";
static BYTE pbySignatureE[16] = "Emu48 Document\xFE";
static BYTE pbySignatureW[16] = "Win48 Document\xFE";
static BYTE pbySignatureV[16] = "Emu49 Document\xFE";

BYTE   cCurrentRomType = 0;					// Model -> hardware
UINT   nCurrentClass = 0;					// Class -> derivate
//BOOL   bRomWriteable = TRUE;				// flag if ROM writeable
LPBYTE pbyRom = NULL;
DWORD  dwRomSize = 0;
WORD   wRomCrc = 0;							// fingerprint of patched ROM

LPBYTE pbyPort2 = NULL;
BOOL   bPort2Writeable = FALSE;
BOOL   bPort2IsShared = FALSE;
DWORD  dwPort2Size = 0;						// size of mapped port2
DWORD  dwPort2Mask = 0;
WORD   wPort2Crc = 0;						// fingerprint of port2

static HANDLE  hPort2File = 0;


//################
//#
//#    Patch
//#
//################

BYTE Asc2Nib(BYTE c)
{
	if (c<'0') return 0;
	if (c<='9') return c-'0';
	if (c<'A') return 0;
	if (c<='F') return c-'A'+10;
	if (c<'a') return 0;
	if (c<='f') return c-'a'+10;
	return 0;
}

// functions to restore ROM patches

static TREENODE *nodePatch = NULL;

BOOL PatchNibble(DWORD dwAddress, BYTE byPatch)
{
	TREENODE *p;

	_ASSERT(pbyRom);						// ROM defined
	if((p = HeapAlloc(hHeap,0,sizeof(TREENODE))) == NULL)
		return TRUE;

	p->bPatch = TRUE;						// address patched
	p->dwAddress = dwAddress;				// save current values
	p->byROM = pbyRom[dwAddress];
	p->byPatch = byPatch;
	p->next = nodePatch;					// save node
	nodePatch = p;

	pbyRom[dwAddress] = byPatch;			// patch ROM
	return FALSE;
}

VOID RestorePatches(VOID)
{
	TREENODE *p;

	_ASSERT(pbyRom);						// ROM defined
	while (nodePatch != NULL)
	{
		// restore original data
		pbyRom[nodePatch->dwAddress] = nodePatch->byROM;
        
		p = nodePatch->next;				// save pointer to next node
		HeapFree(hHeap,0,nodePatch);		// free node
		nodePatch = p;						// new node
	}
}

VOID UpdatePatches(BOOL bPatch)
{
	TREENODE *p = nodePatch;
    
	_ASSERT(pbyRom);						// ROM defined
	while (p != NULL)
	{
		if (bPatch)							// patch ROM
		{
			if (!p->bPatch)					// patch only if not patched
			{
				// use original data for patch restore
				p->byROM = pbyRom[p->dwAddress];
                
				// restore patch data
				pbyRom[p->dwAddress] = p->byPatch;
				p->bPatch = TRUE;			// address patched
			}
			else
			{
				_ASSERT(FALSE);				// call ROM patch on a patched ROM
			}
		}
		else								// restore ROM
		{
			// restore original data
			pbyRom[p->dwAddress] = p->byROM;
			p->bPatch = FALSE;				// address not patched
		}
        
		p = p->next;						// next node
	}
}

BOOL PatchRom(LPCTSTR aFilename)
{
	DWORD dwAddress = 0;

	if (pbyRom == NULL) return FALSE;
//	SetCurrentDirectory(szEmuDirectory);
    NSString *szFilename = [[NSString alloc] initWithUTF8String: aFilename];
    NSError *err = nil;
    NSString *patchStr = [[NSString alloc] initWithContentsOfFile:szFilename encoding:NSUTF8StringEncoding error:&err];
    if (err)
    {
        err = nil;
        patchStr = [[NSString alloc] initWithContentsOfFile:szFilename encoding:NSISOLatin1StringEncoding error:&err];
    }
//	SetCurrentDirectory(szCurrentDirectory);
	if (err || nil == patchStr)
    {
        [szFilename release];
        return NO;
    }
	NSScanner *scanner = [[NSScanner alloc] initWithString: patchStr];
    NSCharacterSet *hexdigitSet = [NSCharacterSet characterSetWithCharactersInString: @"0123456789ABCDEFabcdef"];
    NSString *line;
    while (![scanner isAtEnd])
    {
//        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:nil];
        if ([scanner scanString:@";" intoString:nil])
        {
            [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil];
            continue;
        }
        if ([scanner scanUpToString:@";" intoString:&line])
        {
            NSScanner *numScanner = [[NSScanner alloc] initWithString: line];
            NSString  *data;
            unsigned i, dataLen;
            do
            {
                if (![numScanner scanHexInt: &dwAddress])
                    break;
                if (![numScanner scanString:@":" intoString:nil])
                    break;
                if (![numScanner scanCharactersFromSet:hexdigitSet intoString:&data])
                    break;
                dataLen = (unsigned int)[data length];
                for (i = 0; i < dataLen; ++i)
                {
                    PatchNibble(dwAddress, Asc2Nib((BYTE)[data characterAtIndex:i]));
                    dwAddress = (dwAddress+1)&(dwRomSize-1);
                }
            } while (NO);
            [numScanner release];
            [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"] intoString:nil];
        }
    }
    [scanner release];
    [patchStr release];
    [szFilename release];

	return YES;
}


//################
//#
//#    ROM
//#
//################

BOOL CrcRom(WORD *pwChk)		// calculate fingerprint of ROM
{
	DWORD *pdwData,dwSize;
	DWORD dwChk = 0;

	_ASSERT(pbyRom);						// view on ROM
	pdwData = (DWORD *) pbyRom;

	_ASSERT((dwRomSize % sizeof(*pdwData)) == 0);
	dwSize = dwRomSize / sizeof(*pdwData);	// file size in DWORD's

	// use checksum, because it's faster
	while (dwSize-- > 0)
	{
		DWORD dwData = *pdwData++;
		if ((dwData & 0xF0F0F0F0) != 0)		// data packed?
			return FALSE;
		dwChk += dwData;
	}

	*pwChk = (WORD) ((dwChk >> 16) + (dwChk & 0xFFFF));
	return TRUE;
}

BOOL MapRom(LPCTSTR szFilename)
{
    BOOL result = NO;
    do {
        // open ROM for writing
        BOOL bRomWriteableSetting = [[NSUserDefaults standardUserDefaults] boolForKey: @"RomWriteable"];
        BOOL bWrite = (cCurrentRomType == 'X' || cCurrentRomType == 'Q') ? bRomWriteableSetting : NO;   // CdB for HP: add apples

        if (pbyRom)
        {
            break;
        }
        struct stat statInfo;
        int romfd = -1;
        if (bWrite)
        {
//            romfd = open(szFilename, O_RDWR,   0);
            romfd = CreateFile(szFilename,
                               GENERIC_READ|GENERIC_WRITE,
                               FILE_SHARE_READ,
                               NULL,
                               OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL,
                               NULL);
            if (romfd == INVALID_HANDLE_VALUE)
            {
                bWrite = FALSE;					// ROM not writeable
                romfd = CreateFile(szFilename,
                                   GENERIC_READ,
                                   FILE_SHARE_READ|FILE_SHARE_WRITE,
                                   NULL,
                                   OPEN_EXISTING,
                                   FILE_ATTRIBUTE_NORMAL,
                                   NULL);
            }
        }
        else
        {
//            romfd = open(szFilename, O_RDONLY, 0);
            romfd = CreateFile(szFilename,
                               GENERIC_READ,
                               FILE_SHARE_READ,
                               NULL,
                               OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL,
                               NULL);
        }

        if (romfd == INVALID_HANDLE_VALUE)
        {
            break;
        }
        else
        {
            do {
                // We now know the file exists. Retrieve the file size.
                if (fstat(romfd, &statInfo) != 0)
                {
                    dwRomSize = 0;
                    break;
                }
                // Map the file into memory
                dwRomSize = (unsigned int)(statInfo.st_size);
                void *rom = mmap(NULL,
                                 statInfo.st_size,
                                 PROT_READ|PROT_WRITE,
                                 bWrite ? MAP_SHARED : MAP_PRIVATE,
                                 romfd,
                                 0);
                if (rom == MAP_FAILED)
                {
                    pbyRom = NULL;
                    dwRomSize = 0;
                }
                else
                {
                    pbyRom = (LPBYTE)rom;
                    result = YES;
                }
            } while(NO);
            // Now close the file. The kernel doesn’t use our file descriptor.
            close( romfd );
        }
    } while(NO);
    return result;
}

VOID UnmapRom(VOID)
{
	if (pbyRom == NULL) return;
	RestorePatches();						// restore ROM Patches
	munmap(pbyRom, dwRomSize);
	pbyRom = NULL;
	dwRomSize = 0;
	wRomCrc = 0;
}


//################
//#
//#    Port2
//#
//################

BOOL CrcPort2(WORD *pwCrc)					// calculate fingerprint of port2
{
	DWORD dwCount;
	DWORD dwFileSize;

	*pwCrc = 0;

	// port2 CRC isn't available
	if (pbyPort2 == NULL) return YES;

    struct stat statInfo;
    if (fstat(hPort2File, &statInfo) != 0)
        return NO;

	dwFileSize = (unsigned int)statInfo.st_size; // get real filesize

	for (dwCount = 0;dwCount < dwFileSize; ++dwCount)
	{
		if ((pbyPort2[dwCount] & 0xF0) != 0) // data packed?
			return NO;
        
		*pwCrc = (*pwCrc >> 4) ^ (((*pwCrc ^ ((WORD) pbyPort2[dwCount])) & 0xf) * 0x1081);
	}
	return YES;
}

BOOL MapPort2(LPCTSTR szFilename)
{
    struct stat statInfo;
	DWORD dwFileSizeLo,dwFileSizeHi,dwCount;

	if (pbyPort2 != NULL)
        return FALSE;
	bPort2Writeable = TRUE;
	dwPort2Size = 0;						// reset size of port2

//	SetCurrentDirectory(szEmuDirectory);
    BOOL port2IsShared = [[NSUserDefaults standardUserDefaults] boolForKey: @"Port2IsShared"];
    if([[NSUserDefaults standardUserDefaults] boolForKey: @"Port2Writeable"]) {
        hPort2File = CreateFile(szFilename,
                                GENERIC_READ|GENERIC_WRITE,
                                port2IsShared ? FILE_SHARE_READ : 0,
                                NULL,
                                OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL,
                                NULL);
    }
	if (hPort2File == INVALID_HANDLE_VALUE || hPort2File == 0)
	{
		bPort2Writeable = FALSE;
		hPort2File = CreateFile(szFilename,
								GENERIC_READ,
								port2IsShared ? (FILE_SHARE_READ|FILE_SHARE_WRITE) : 0,
								NULL,
								OPEN_EXISTING,
								FILE_ATTRIBUTE_NORMAL,
								NULL);
		if (hPort2File == INVALID_HANDLE_VALUE)
		{
//			SetCurrentDirectory(szCurrentDirectory);
			hPort2File = 0;
			return FALSE;
		}
	}
//	SetCurrentDirectory(szCurrentDirectory);
    if (0 != fstat(hPort2File, &statInfo))
    {
        close(hPort2File);
		hPort2File = 0;
		dwPort2Mask = 0;
		bPort2Writeable = FALSE;
		return FALSE;
	}
	dwFileSizeLo = (unsigned int)statInfo.st_size;

	// count number of set bits
	for (dwCount = 0, dwFileSizeHi = dwFileSizeLo; dwFileSizeHi != 0;dwFileSizeHi >>= 1)
	{
		if ((dwFileSizeHi & 0x1) != 0) ++dwCount;
	}

	// size not 32, 128, 256, 512, 1024, 2048 or 4096 KB
	if (dwCount != 1 || (dwFileSizeLo & 0xFF02FFFF) != 0)
	{
		close(hPort2File);
		hPort2File = 0;
		dwPort2Mask = 0;
		bPort2Writeable = FALSE;
		return FALSE;
	}

	dwPort2Mask = (dwFileSizeLo - 1) >> 18;	// mask for valid address lines of the BS-FF
	void *port2 = mmap(NULL, dwFileSizeLo, bPort2Writeable ? PROT_READ|PROT_WRITE : PROT_READ, bPort2Writeable ? MAP_SHARED : MAP_PRIVATE, hPort2File, 0);
	if (MAP_FAILED == port2)
	{
		close(hPort2File);
		hPort2File = 0;
		dwPort2Mask = 0;
		bPort2Writeable = FALSE;
		return FALSE;
	}
    pbyPort2 = (LPBYTE)port2;
	dwPort2Size = dwFileSizeLo / 2048;		// mapping size of port2
    
	if (CrcPort2(&wPort2Crc) == FALSE)		// calculate fingerprint of port2
	{
		UnmapPort2();						// free memory
		NSLog(@"Packed Port 2 image detected!");
		return FALSE;
	}
	return TRUE;
}

void UnmapPort2()
{
	if (pbyPort2==NULL) return;
    munmap(pbyPort2, dwPort2Size);
	close(hPort2File);
	pbyPort2 = NULL;
	hPort2File = 0;
	dwPort2Size = 0;						// reset size of port2
	dwPort2Mask = 0;
	bPort2Writeable = FALSE;
	wPort2Crc = 0;
}

// Uses code from Christoph Giesselink's mkshared utility
BOOL NewPort2(NSString *filename, int numBlocks)
{
    BOOL result = NO;
    int hFile = -1;
    hFile = open([filename UTF8String], O_RDWR|O_CREAT|O_TRUNC, S_IRUSR | S_IWUSR);
    if (-1 != hFile)
    {
        unsigned char *buf = calloc(2048, 1);
        while (numBlocks--) write(hFile, buf, 2048);
        free(buf);
        close(hFile);
        result = YES;
    }
    return result;
}



//################
//#
//#    Documents
//#
//################

BOOL IsDataPacked(VOID *pMem, DWORD dwSize)
{
	_ASSERT((dwSize % sizeof(DWORD)) == 0);
	if ((dwSize % sizeof(DWORD)) != 0) return TRUE;

    DWORD *dp = (DWORD *)pMem;
	for (dwSize /= sizeof(DWORD); dwSize-- > 0;)
	{
		if ((*dp++ & 0xF0F0F0F0) != 0)
			return TRUE;
	}
	return FALSE;
}

VOID ResetDocument(VOID)
{
	DisableDebugger();
    ResetEvent(hEventDebug);
/*
	if (szCurrentKml[0])
	{
		KillKML();
	}
	if (hCurrentFile)
	{
		CloseHandle(hCurrentFile);
		hCurrentFile = NULL;
	}
	szCurrentKml[0] = 0;
	szCurrentFilename[0]=0;
*/
	if (Chipset.Port0) HeapFree(hHeap,0,Chipset.Port0);
	if (Chipset.Port1) HeapFree(hHeap,0,Chipset.Port1);
	if (Chipset.Port2) HeapFree(hHeap,0,Chipset.Port2); else UnmapPort2();
	ZeroMemory(&Chipset,sizeof(Chipset));
	ZeroMemory(&RMap,sizeof(RMap));			// delete MMU mappings
	ZeroMemory(&WMap,sizeof(WMap));
}

BOOL NewDocument()
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
//	SaveBackup();
//    ResetDocument();
	Chipset.type = cCurrentRomType;
    
	if (Chipset.type == '6' || Chipset.type == 'A')	// HP38G
	{
		Chipset.Port0Size = (Chipset.type == 'A') ? 32 : 64;
		Chipset.Port1Size = 0;
		Chipset.Port2Size = 0;
        
		Chipset.cards_status = 0x0;
	}
	if (Chipset.type == 'E' || Chipset.type == 'P')				// HP39/40G/HP39G+   // CdB for HP: add apples
	{
		Chipset.Port0Size = 128;
		Chipset.Port1Size = 0;
		Chipset.Port2Size = 128;
        
		Chipset.cards_status = 0xF;
        
		bPort2Writeable = TRUE;				// port2 is writeable
	}
	if (Chipset.type == 'S')				// HP48SX
	{
		Chipset.Port0Size = 32;
		Chipset.Port1Size = 128;
		Chipset.Port2Size = 0;

		Chipset.cards_status = 0x5;

        //id port2file = [defaults objectForKey: @"Port2Filename"];
        id port2file = [[defaults URLForKey: @"Port2Filename"] path];
        if (port2file && [port2file isKindOfClass: [NSString class]] &&
            [port2file length]>0)
            MapPort2([port2file UTF8String]);
	}
	if (Chipset.type == 'G')				// HP48GX
	{
		Chipset.Port0Size = 128;
		Chipset.Port1Size = 128;
		Chipset.Port2Size = 0;

		Chipset.cards_status = 0xA;

        //id port2file = [defaults objectForKey: @"Port2Filename"];
        id port2file = [[defaults URLForKey: @"Port2Filename"] path];
        if (port2file && [port2file isKindOfClass: [NSString class]] &&
            [port2file length]>0)
            MapPort2([port2file UTF8String]);
	}
	if (Chipset.type == 'X' || Chipset.type == '2' || Chipset.type == 'Q')				// HP49G/HP48Gii/HP49G+   // CdB for HP: add apples
	{
		Chipset.Port0Size = 256;
		Chipset.Port1Size = 128;
		Chipset.Port2Size = 128;
        
		Chipset.cards_status = 0xF;
		bPort2Writeable = TRUE;				// port2 is writeable
        
		FlashInit();						// init flash structure
	}
	if (Chipset.type == 'Q')				// HP49G+   // CdB for HP: add apples
	{
		Chipset.d0size = 16;
	}
    
	Chipset.IORam[LPE] = RST;				// set ReSeT bit at power on reset

	// allocate port memory
	if (Chipset.Port0Size)
	{
		Chipset.Port0 = calloc(1, Chipset.Port0Size*2048);
		_ASSERT(Chipset.Port0 != NULL);
	}
	if (Chipset.Port1Size)
	{
		Chipset.Port1 = calloc(1, Chipset.Port1Size*2048);
		_ASSERT(Chipset.Port1 != NULL);
	}
	if (Chipset.Port2Size)
	{
		Chipset.Port2 = calloc(1, Chipset.Port2Size*2048);
		_ASSERT(Chipset.Port2 != NULL);
	}
    //	LoadBreakpointList(NULL);				// clear debugger breakpoint list
	RomSwitch(0);							// boot ROM view of HP49G and map memory
//	SaveBackup();
	return YES;
}



//################
//#
//#    Backup
//#
//################

BOOL SaveBackup(VOID)
{
	if (pbyRom == NULL) return FALSE;

	_ASSERT(nState != SM_RUN);				// emulation engine is running
#if 0
	// save window position
//	_ASSERT(hWnd);							// window open
//	wndpl.length = sizeof(wndpl);			// update saved window position
//	GetWindowPlacement(hWnd, &wndpl);
//	Chipset.nPosX = (SWORD) wndpl.rcNormalPosition.left;
//	Chipset.nPosY = (SWORD) wndpl.rcNormalPosition.top;

	lstrcpy(szBackupFilename, szCurrentFilename);
	lstrcpy(szBackupKml, szCurrentKml);
	if (BackupChipset.Port0) HeapFree(hHeap,0,BackupChipset.Port0);
	if (BackupChipset.Port1) HeapFree(hHeap,0,BackupChipset.Port1);
	if (BackupChipset.Port2) HeapFree(hHeap,0,BackupChipset.Port2);
	CopyMemory(&BackupChipset, &Chipset, sizeof(Chipset));
	BackupChipset.Port0 = HeapAlloc(hHeap,0,Chipset.Port0Size*2048);
	CopyMemory(BackupChipset.Port0,Chipset.Port0,Chipset.Port0Size*2048);
	BackupChipset.Port1 = HeapAlloc(hHeap,0,Chipset.Port1Size*2048);
	CopyMemory(BackupChipset.Port1,Chipset.Port1,Chipset.Port1Size*2048);
	BackupChipset.Port2 = NULL;
	if (Chipset.Port2Size)					// internal port2
	{
		BackupChipset.Port2 = HeapAlloc(hHeap,0,Chipset.Port2Size*2048);
		CopyMemory(BackupChipset.Port2,Chipset.Port2,Chipset.Port2Size*2048);
	}
	bBackup = TRUE;
#endif
//	UpdateWindowStatus();
	return TRUE;
}

BOOL RestoreBackup(VOID)
{
#if 0
	if (!bBackup) return FALSE;
	ResetDocument();
	// need chipset for contrast setting in InitKML()
	Chipset.contrast = BackupChipset.contrast;
	if (!InitKML(szBackupKml,TRUE))
	{
		InitKML(szCurrentKml,TRUE);
		return FALSE;
	}
	lstrcpy(szCurrentKml, szBackupKml);
	lstrcpy(szCurrentFilename, szBackupFilename);
	if (szCurrentFilename[0])
	{
		hCurrentFile = CreateFile(szCurrentFilename, GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
		if (hCurrentFile == INVALID_HANDLE_VALUE)
		{
			hCurrentFile = NULL;
			szCurrentFilename[0] = 0;
		}
	}
	CopyMemory(&Chipset, &BackupChipset, sizeof(Chipset));
	Chipset.Port0 = HeapAlloc(hHeap,0,Chipset.Port0Size*2048);
	CopyMemory(Chipset.Port0,BackupChipset.Port0,Chipset.Port0Size*2048);
	Chipset.Port1 = HeapAlloc(hHeap,0,Chipset.Port1Size*2048);
	CopyMemory(Chipset.Port1,BackupChipset.Port1,Chipset.Port1Size*2048);
	if (Chipset.Port2Size)					// internal port2
	{
		Chipset.Port2 = HeapAlloc(hHeap,0,Chipset.Port2Size*2048);
		CopyMemory(Chipset.Port2,BackupChipset.Port2,Chipset.Port2Size*2048);
	}
	// map port2
	else
	{
		if (cCurrentRomType=='S' || cCurrentRomType=='G') // HP48SX/GX
		{
			// use 2nd command line argument if defined
			MapPort2((nArgc < 3) ? szPort2Filename : ppArgv[2]);
		}
	}
//	SetWindowPathTitle(szCurrentFilename);	// update window title line
//	SetWindowLocation(hWnd,Chipset.nPosX,Chipset.nPosY);
//	UpdateWindowStatus();
	Map(0x00,0xFF);
#endif
	return TRUE;
}

BOOL ResetBackup(VOID)
{
#if 0
	if (!bBackup) return FALSE;
	szBackupFilename[0] = 0;
	szBackupKml[0] = 0;
	if (BackupChipset.Port0) HeapFree(hHeap,0,BackupChipset.Port0);
	if (BackupChipset.Port1) HeapFree(hHeap,0,BackupChipset.Port1);
	if (BackupChipset.Port2) HeapFree(hHeap,0,BackupChipset.Port2);
	ZeroMemory(&BackupChipset,sizeof(BackupChipset));
	bBackup = FALSE;
//	UpdateWindowStatus();
#endif
	return TRUE;
}

#if 0
BOOL LoadObject(LPCTSTR szFilename)			// separated stack writing part
{
	HANDLE hFile;
	DWORD  dwFileSizeLow;
	LPBYTE lpBuf;
	WORD   wError;
    
	hFile = CreateFile(szFilename,
					   GENERIC_READ,
					   FILE_SHARE_READ,
					   NULL,
					   OPEN_EXISTING,
					   FILE_FLAG_SEQUENTIAL_SCAN,
					   NULL);
	if (hFile == INVALID_HANDLE_VALUE) return FALSE;
    struct stat statInfo;
    if (fstat(hFile, &statInfo) != 0)
	{
		close(hFile);
		return FALSE;
	}
	dwFileSizeLow = statInfo.st_size;
	lpBuf = HeapAlloc(hHeap,0,dwFileSizeLow*2);
	if (lpBuf == NULL)
	{
		close(hFile);
		return FALSE;
	}
	read(hFile, lpBuf+dwFileSizeLow, dwFileSizeLow, 0);
	close(hFile);
    
	wError = WriteStack(1,lpBuf,dwFileSizeLow);
    
	if (wError == S_ERR_OBJECT)
		AbortMessage(_T("This isn't a valid binary file."));
    
	if (wError == S_ERR_BINARY)
		AbortMessage(_T("The calculator does not have enough\nfree memory to load this binary file."));
    
	if (wError == S_ERR_ASCII)
		AbortMessage(_T("The calculator does not have enough\nfree memory to load this text file."));
    
	HeapFree(hHeap,0,lpBuf);
	return (wError == S_ERR_NO);
}

BOOL SaveObject(LPCTSTR szFilename)			// separated stack reading part
{
	HANDLE	hFile;
	LPBYTE  pbyHeader;
	DWORD	lBytesWritten;
	DWORD   dwAddress;
	DWORD   dwLength;
    
	dwAddress = RPL_Pick(1);
	if (dwAddress == 0)
	{
		AbortMessage(_T("Too Few Arguments."));
		return FALSE;
	}
	dwLength = (RPL_SkipOb(dwAddress) - dwAddress + 1) / 2;
    
	hFile = CreateFile(szFilename, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_FLAG_SEQUENTIAL_SCAN, NULL);
	if (hFile == INVALID_HANDLE_VALUE)
	{
		AbortMessage(_T("Cannot open file."));
		return FALSE;
	}

	pbyHeader = (Chipset.type != 'X') ? BINARYHEADER48 : BINARYHEADER49;
	lBytesWritten = write(hFile, pbyHeader, 8, 0);

	while (dwLength--)
	{
		BYTE byByte = Read2(dwAddress);
		lBytesWritten = write(hFile, &byByte, 1, 0);
		dwAddress += 2;
	}
	close(hFile);
	return TRUE;
}
#endif

@implementation CalcState

- (id)initWithKml:(NSString *)kmlPath error:(NSError **)outError
{
    self = [super init];
    ResetDocument();
    if ([self setKmlFile:kmlPath error:outError])
    {
        NewDocument();
    }
    else
    {
        [super release];
        self = nil;
    }
    return self;
}

// OpenDocument
- (id)initWithFile:(NSString *)aStateFile error:(NSError **)outError
{
    self = [super init];

    NSString *errDesc   = nil;
    NSString *errReason = nil;

#define CHECKAREA(s,e) (offsetof(CHIPSET,e)-offsetof(CHIPSET,s)+sizeof(((CHIPSET *)NULL)->e))
    
	int     hFile = -1;
	DWORD   lBytesRead,lSizeofChipset;
	BYTE    pbyFileSignature[16];
	LPBYTE  pbySig;
	UINT    ctBytesCompared;
	UINT    nLength;
    LPSTR   kmlPath = NULL;

//	SaveBackup();
	ResetDocument();

	// Open file
	hFile = CreateFile([aStateFile UTF8String], GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
	if (hFile == INVALID_HANDLE_VALUE)
	{
        errDesc = NSLocalizedString(@"Calculator state file could not be opened because the file is missing or already loaded in another instance of Emu48.",@"");
        errReason = NSLocalizedString(@"This file is missing or already loaded in another instance of Emu48.",@"");
		goto restore;
	}

	// Read and Compare signature
	lBytesRead = (unsigned int)read(hFile, pbyFileSignature, 16);
	switch (pbyFileSignature[0])
	{
        case 'E':
            pbySig = (pbyFileSignature[3] == '3')
            ? ((pbyFileSignature[4] == '8') ? pbySignatureA : pbySignatureB)
            : ((pbyFileSignature[4] == '8') ? pbySignatureE : pbySignatureV);
            for (ctBytesCompared=0; ctBytesCompared<14; ctBytesCompared++)
            {
                if (pbyFileSignature[ctBytesCompared]!=pbySig[ctBytesCompared])
                {
                    errDesc = NSLocalizedString(@"Calculator state file could not be opened because the file is not a valid Emu48 document.",@"");
                    errReason = NSLocalizedString(@"This file is not a valid Emu48 document.",@"");
                    goto restore;
                }
            }
            break;
        case 'W':
            for (ctBytesCompared=0; ctBytesCompared<14; ctBytesCompared++)
            {
                if (pbyFileSignature[ctBytesCompared]!=pbySignatureW[ctBytesCompared])
                {
                    errDesc = NSLocalizedString(@"Calculator state file could not be opened because the file is not a valid Win48 document.",@"");
                    errReason = NSLocalizedString(@"This file is not a valid Win48 document.",@"");
                    goto restore;
                }
            }
            break;
        default:
            errDesc = NSLocalizedString(@"Calculator state file could not be opened because the file is not a valid document.",@"");
            errReason = NSLocalizedString(@"This file is not a valid document.",@"");
            goto restore;
	}
    
	switch (pbyFileSignature[14])
	{
        case 0xFE: // Win48 2.1 / Emu4x 0.99.x format
            lBytesRead = (unsigned int)read(hFile,&nLength,sizeof(nLength));
            kmlPath = HeapAlloc(hHeap,0,nLength+1);
            if (kmlPath == NULL)
            {
                errDesc = NSLocalizedString(@"Calculator state file could not be opened because of not enough memory.",@"");
                errReason = NSLocalizedString(@"Memory Allocation Failure.",@"");
                goto restore;
            }
            lBytesRead = (unsigned int)read(hFile, kmlPath, nLength);
            if (nLength != lBytesRead) goto read_err;
            kmlPath[nLength] = 0;
            break;
        case 0xFF: // Win48 2.05 format
            break;
        default:
            errDesc = NSLocalizedString(@"Calculator state file could not be opened because the file is for an unknown version of Emu48.",@"");
            errReason = NSLocalizedString(@"This file is for an unknown version of Emu48.",@"");
            goto restore;
	}
    
	// read chipset size inside file
	lBytesRead = (unsigned int)read(hFile, &lSizeofChipset, sizeof(lSizeofChipset));
	if (lBytesRead != sizeof(lSizeofChipset)) goto read_err;
	if (lSizeofChipset <= sizeof(Chipset))	// actual or older chipset version
	{
		// read chipset content
		ZeroMemory(&Chipset,sizeof(Chipset));	// init chipset
		lBytesRead = (unsigned int)read(hFile, &Chipset, lSizeofChipset);
	}
	else									// newer chipset version
	{
		// read my used chipset content
		lBytesRead = (unsigned int)read(hFile, &Chipset, sizeof(Chipset));
        
		// skip rest of chipset
        lseek(hFile, lSizeofChipset-sizeof(Chipset), SEEK_CUR);
        //		SetFilePointer(hFile, lSizeofChipset-sizeof(Chipset), NULL, FILE_CURRENT);
		lSizeofChipset = sizeof(Chipset);
	}
	Chipset.Port0 = NULL;					// delete invalid port pointers
	Chipset.Port1 = NULL;
	Chipset.Port2 = NULL;
	if (lBytesRead != lSizeofChipset) goto read_err;
    
	if (!isModelValid(Chipset.type))		// check for valid model in emulator state file
	{
        errDesc = NSLocalizedString(@"Calculator state file could not be opened because the calculator model is invalid.",@"");
        errReason = NSLocalizedString(@"Emulator state file with invalid calculator model.",@"");
		goto restore;
	}
    
//	SetWindowLocation(hWnd,Chipset.nPosX,Chipset.nPosY);
    
    //	while (TRUE)
	{
        BOOL bOK = NO;
		if (kmlPath[0])				// KML file name
		{
			bOK = [self setKmlFile:[NSString stringWithUTF8String: kmlPath] error:outError];
			bOK = bOK && (cCurrentRomType == Chipset.type);
            //			if (bOK) break;
            
            //			KillKML();
		}
        //		if (!DisplayChooseKml(Chipset.type))
        if (!bOK)
			goto restore;
	}

	// reload old button state
	[kml reloadButtons:Chipset.Keyboard_Row size:sizeof(Chipset.Keyboard_Row)];

	FlashInit();							// init flash structure

	if (Chipset.Port0Size)
	{
		Chipset.Port0 = HeapAlloc(hHeap,0,Chipset.Port0Size*2048);
		if (Chipset.Port0 == NULL)
		{
            errDesc = NSLocalizedString(@"Calculator state file could not be opened because of not enough memory.",@"");
            errReason = NSLocalizedString(@"Memory Allocation Failure.",@"");
			goto restore;
		}
        
		lBytesRead = (unsigned int)read(hFile, Chipset.Port0, Chipset.Port0Size*2048);
		if (lBytesRead != Chipset.Port0Size*2048) goto read_err;
        
		if (IsDataPacked(Chipset.Port0,Chipset.Port0Size*2048)) goto read_err;
	}

	if (Chipset.Port1Size)
	{
		Chipset.Port1 = HeapAlloc(hHeap,0,Chipset.Port1Size*2048);
		if (Chipset.Port1 == NULL)
		{
            errDesc = NSLocalizedString(@"Calculator state file could not be opened because of not enough memory.",@"");
            errReason = NSLocalizedString(@"Memory Allocation Failure.",@"");
			goto restore;
		}

		lBytesRead = (unsigned int)read(hFile, Chipset.Port1, Chipset.Port1Size*2048);
		if (lBytesRead != Chipset.Port1Size*2048) goto read_err;

		if (IsDataPacked(Chipset.Port1,Chipset.Port1Size*2048)) goto read_err;
	}

	// HP48SX/GX
	if(cCurrentRomType=='S' || cCurrentRomType=='G')
	{
        
        //id port2file = [[NSUserDefaults standardUserDefaults] objectForKey: @"Port2Filename"];
        id port2file = [[[NSUserDefaults standardUserDefaults] URLForKey: @"Port2Filename"] path];
        if (port2file && [port2file isKindOfClass: [NSString class]] &&
            [port2file length]>0)
        {
            MapPort2([port2file UTF8String]);
        }
		// port2 changed and card detection enabled
		if (    Chipset.wPort2Crc != wPort2Crc
			&& (Chipset.IORam[CARDCTL] & ECDT) != 0 && (Chipset.IORam[TIMER2_CTRL] & RUN) != 0
            )
		{
			Chipset.HST |= MP;				// set Module Pulled
			IOBit(SRQ2,NINT,FALSE);			// set NINT to low
			Chipset.SoftInt = TRUE;			// set interrupt
			bInterrupt = TRUE;
		}
	}
	else									// HP38G, HP39/40G, HP49G
	{
		if (Chipset.Port2Size)
		{
			Chipset.Port2 = HeapAlloc(hHeap,0,Chipset.Port2Size*2048);
			if (Chipset.Port2 == NULL)
			{
                errDesc = NSLocalizedString(@"Calculator state file could not be opened because of not enough memory.",@"");
                errReason = NSLocalizedString(@"Memory Allocation Failure.",@"");
				goto restore;
			}
            
			lBytesRead = (unsigned int)read(hFile, Chipset.Port2, Chipset.Port2Size*2048);
			if (lBytesRead != Chipset.Port2Size*2048) goto read_err;
            
			if (IsDataPacked(Chipset.Port2,Chipset.Port2Size*2048)) goto read_err;
            
			bPort2Writeable = TRUE;
			Chipset.cards_status = 0xF;
		}
	}

	RomSwitch(Chipset.Bank_FF);				// reload ROM view of HP49G and map memory

	if (Chipset.wRomCrc != wRomCrc)		// ROM changed
	{
		CpuReset();
		Chipset.Shutdn = FALSE;				// automatic restart
	}

	// check CPU main registers
	if (IsDataPacked(Chipset.A,CHECKAREA(A,R4))) goto read_err;
    
//	LoadBreakpointList(hFile);				// load debugger breakpoint list
    close(hFile);
	return self;

read_err:
    errDesc = NSLocalizedString(@"Calculator state file could not be opened because the file is truncated.",@"");
    errReason = NSLocalizedString(@"This file is truncated, and cannot be loaded.",@"");
restore:
    if (outError && nil==*outError)
        *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:errDesc, NSLocalizedDescriptionKey, errReason, NSLocalizedFailureReasonErrorKey, nil]];

    if (kmlPath)
        free(kmlPath);
	if (INVALID_HANDLE_VALUE != hFile)		// close if valid handle
		close(hFile);
//	RestoreBackup();
//	ResetBackup();

	// HP48SX/GX
	if(cCurrentRomType=='S' || cCurrentRomType=='G')
	{
        //id port2file = [[NSUserDefaults standardUserDefaults] objectForKey: @"Port2Filename"];
        id port2file = [[[NSUserDefaults standardUserDefaults] URLForKey: @"Port2Filename"] path];
        if (port2file && [port2file isKindOfClass: [NSString class]] &&
            [port2file length]>0)
        {
            MapPort2([port2file UTF8String]);
        }
	}

    [self release];
	return nil;
#undef CHECKAREA
}

- (void)dealloc
{
    SwitchToState(SM_RETURN);
    ResetDocument();
    UnmapRom();
    [kml release];
    [super dealloc];
}

// OnViewScript (next)
- (BOOL)setKmlFile:(NSString *)aFilename error:(NSError **)outError
{
    BOOL result = NO;
    KmlParseResult *freshKml = nil;
    KmlParser *parser = [[KmlParser alloc] init];
    
//    BOOL isRunning = (SM_RUN == nState);
//    if (isRunning)
//        SwitchToState(SM_INVALID);
    UnmapRom();
    
    // Determine the KML folder and switch to it
    NSString *kmlFolder = [aFilename stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:kmlFolder];
    freshKml = [parser ParseKML:aFilename error:outError];
    [parser release];
    
    if (freshKml)
    {
        [kml release];
        kml = [freshKml retain];
//        [self finishInit];
        //        [[self window] setTitleWithRepresentedFilename: aFilename];
        result = YES;
    }
    else
    {
        // Parse failed, revert changes
        [kml reloadRom];
    }
//    if (isRunning)
//        if (pbyRom) SwitchToState(SM_RUN);
    return result;
}

- (BOOL)setKmlFileWithStop:(NSString *)aFilename error:(NSError **)outError
{
    BOOL isRunning = (SM_RUN == nState);
    if (isRunning)
        SwitchToState(SM_INVALID);
    [self setKmlFile:(NSString *)aFilename error:(NSError **)outError];
    if (isRunning)
        if (pbyRom) SwitchToState(SM_RUN);
}


- (BOOL)saveAs:(NSString *)aStateFile error:(NSError **)outError
{
    int hFile = -1;
    struct flock lock;
	ssize_t lBytesWritten;
	DWORD   lSizeofChipset;
	UINT    nLength;

    // Set default permissions
    mode_t perm = S_IRUSR | S_IWUSR;
    // Check for file writeability
    lock.l_type = F_WRLCK;
    lock.l_len = lock.l_start = 0;
    lock.l_whence = SEEK_SET;
    int peekFd = open([aStateFile UTF8String], O_WRONLY|O_CREAT, perm);
    if (-1 == peekFd)
        return NO;
    if (-1 == fcntl(peekFd, F_SETLK, &lock) &&
        (EACCES == errno || EAGAIN == errno))
    {
        close(peekFd);
        if (outError)
            *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"Calculator state file could not be saved because the state file is currently in use.",@""), NSLocalizedDescriptionKey, NSLocalizedString(@"State file is currently in use by another instance of Emu48.",@""), NSLocalizedFailureReasonErrorKey, nil]];
        return NO;
    }

#if USE_WRITE_TEMPFILE
    close(peekFd);
    // Temp filename
    NSString *tempFileTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent: @"e48stateXXXXXXXXXX"];
    const char *tempFileTemplateStr = [tempFileTemplate UTF8String];
    char *tempFilename = (char *)calloc(sizeof(char)*(strlen(tempFileTemplateStr)+1), 1);
    strcpy(tempFilename, tempFileTemplateStr);
    
    hFile = mkstemp(tempFilename);
#else
    hFile = peekFd;
#endif

    //	Chipset.nPosX = (SWORD) wndpl.rcNormalPosition.left;
    //	Chipset.nPosY = (SWORD) wndpl.rcNormalPosition.top;

    lBytesWritten = write(hFile, pbySignatureE, sizeof(pbySignatureE));
	if (lBytesWritten < sizeof(pbySignatureE))
	{
        close(hFile);
        unlink([aStateFile UTF8String]);
#if USE_WRITE_TEMPFILE
        free(tempFilename);
#endif
        if (outError)
        {
            NSMutableDictionary *errUserInfo = [NSMutableDictionary dictionary];
            if (-1 == lBytesWritten)
            {
                NSError *underlyingError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                [errUserInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
            }
            [errUserInfo setObject:NSLocalizedString(@"Calculator state file could not be saved because the save was interrupted or a disk error occurred.",@"") forKey:NSLocalizedDescriptionKey];
            [errUserInfo setObject:NSLocalizedString(@"The save was interrupted or a disk error occurred.",@"") forKey:NSLocalizedFailureReasonErrorKey];
            *outError = [NSError errorWithDomain:[[NSBundle mainBundle] bundleIdentifier] code:-1 userInfo:errUserInfo];
        }
		return NO;
	}

	CrcRom(&Chipset.wRomCrc);               // save fingerprint of ROM
	CrcPort2(&Chipset.wPort2Crc);           // save fingerprint of port2

    NSString *kmlPath = [kml kmlPath];
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    // If kml is inside app bundle, save path relative to app
    // This way app location changes are handled robustly
    if ([kmlPath hasPrefix: appPath])
        kmlPath = [kmlPath substringFromIndex: ([appPath length]+1)];
    const char *kmlPathStr = [kmlPath UTF8String];
	nLength = (unsigned int)strlen(kmlPathStr);
    write(hFile, &nLength, sizeof(nLength));
    write(hFile, kmlPathStr, nLength);

	lSizeofChipset = sizeof(CHIPSET);
    write(hFile, &lSizeofChipset, sizeof(lSizeofChipset));
	write(hFile, &Chipset, lSizeofChipset);
	if (Chipset.Port0Size) write(hFile, Chipset.Port0, Chipset.Port0Size*2048);
	if (Chipset.Port1Size) write(hFile, Chipset.Port1, Chipset.Port1Size*2048);
	if (Chipset.Port2Size) write(hFile, Chipset.Port2, Chipset.Port2Size*2048);
    //	SaveBreakpointList(hCurrentFile);		// save debugger breakpoint list
    close(hFile);
#if USE_WRITE_TEMPFILE
    rename(tempFilename, [aStateFile UTF8String]);
    free(tempFilename);
#endif

    return YES;
}

- (KmlParseResult *)kml
{
    return kml;
}
@end


@implementation CalcBackup

//SaveBackup
- (id)initWithState:(CalcState *)aState
{
    self = [super init];
	if (pbyRom == NULL)
    {
        [self release];
        return nil;
    }

	_ASSERT(nState != SM_RUN);				// emulation engine is running

    backupKmlPath = [[[aState kml] kmlPath] retain];
    if (backupChipset.Port0) free(backupChipset.Port0);
	if (backupChipset.Port1) free(backupChipset.Port1);
	if (backupChipset.Port2) free(backupChipset.Port2);
	CopyMemory(&backupChipset, &Chipset, sizeof(Chipset));
	backupChipset.Port0 = malloc(Chipset.Port0Size*2048);
	CopyMemory(backupChipset.Port0,Chipset.Port0,Chipset.Port0Size*2048);
	backupChipset.Port1 = malloc(Chipset.Port1Size*2048);
	CopyMemory(backupChipset.Port1,Chipset.Port1,Chipset.Port1Size*2048);
	backupChipset.Port2 = NULL;
	if (Chipset.Port2 && Chipset.Port2Size)					// internal port2
	{
		backupChipset.Port2 = malloc(Chipset.Port2Size*2048);
		CopyMemory(backupChipset.Port2,Chipset.Port2,Chipset.Port2Size*2048);
	}
    return self;
}

- (void)dealloc
{
    [backupKmlPath release];
    [super dealloc];
}

- (BOOL)restoreToState:(CalcState *)aState
{
	ResetDocument();
	// need chipset for contrast setting in InitKML()
	Chipset.contrast = backupChipset.contrast;
    NSError *err = nil;
    if (![aState setKmlFile:backupKmlPath error:&err])
	{
//		InitKML(szCurrentKml,TRUE);
		return NO;
    }

	CopyMemory(&Chipset, &backupChipset, sizeof(Chipset));
	Chipset.Port0 = malloc(Chipset.Port0Size*2048);
	CopyMemory(Chipset.Port0,backupChipset.Port0,Chipset.Port0Size*2048);
	Chipset.Port1 = malloc(Chipset.Port1Size*2048);
	CopyMemory(Chipset.Port1,backupChipset.Port1,Chipset.Port1Size*2048);
	if (Chipset.Port2Size)					// internal port2
	{
		Chipset.Port2 = malloc(Chipset.Port2Size*2048);
		CopyMemory(Chipset.Port2,backupChipset.Port2,Chipset.Port2Size*2048);
	}
	// map port2
	else
	{
		if (cCurrentRomType=='S' || cCurrentRomType=='G') // HP48SX/GX
		{
            //id port2file = [[NSUserDefaults standardUserDefaults] objectForKey: @"Port2Filename"];
            id port2file = [[[NSUserDefaults standardUserDefaults] URLForKey: @"Port2Filename"] path];
            if (port2file && [port2file isKindOfClass: [NSString class]] &&
                [port2file length]>0)
                MapPort2([port2file UTF8String]);
		}
	}
	Map(0x00,0xFF);
	return TRUE;
}
@end
