/*
 *  MacWinAPIPatch.m
 *  Emu48
 *
 *  Created by Da Woon Jung on Wed Dec 10 2003.
 *  Copyright (c) 2003 dwj. All rights reserved.
 *
 */

#import "MacWinAPIPatch.h"
#import <mach/mach_time.h>
#import <fcntl.h>

HANDLE hWnd;
LPTSTR szTitle;

static NSMutableDictionary *gEventLockDict;
static HANDLE gEventId;


BOOL SetCurrentDirectory(LPCTSTR path)
{
    if(nil==path)
        return NO;

    return chdir(path);
}

int CreateFile(LPCTSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPVOID lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, LPVOID hTemplateFile)
{
    int flags = O_RDWR;
    int fd = -1;
    struct flock lock;
    mode_t perm = S_IRUSR | S_IWUSR;

    if (GENERIC_READ == dwDesiredAccess)
        flags = O_RDONLY;
    else
    {
        if (GENERIC_WRITE == dwDesiredAccess)
            flags = O_WRONLY;
        else if (0 != ((GENERIC_READ|GENERIC_WRITE) & dwDesiredAccess))
            flags = O_RDWR;

        if (CREATE_ALWAYS == dwCreationDisposition)
            flags |= O_CREAT;
    }

    fd = open(lpFileName, flags, perm);
    if (-1 != fd && 0 != dwShareMode)
    {
        // Not specifiying shared write means non-shared (exclusive) write
        if (0 == (dwShareMode & FILE_SHARE_WRITE))
            lock.l_type = F_WRLCK;
        else if (0 != (dwShareMode & FILE_SHARE_READ))
            lock.l_type = F_RDLCK;

        // Lock entire file
        lock.l_len = lock.l_start = 0;
        lock.l_whence = SEEK_SET;

        if (-1 == fcntl(fd, F_SETLK, &lock) &&
            (EACCES == errno || EAGAIN == errno))
        {
            close(fd);
            return -1;
        }
    }

    return fd;
}

/*
OSErr ReadFile(FSPtr &file, void *buf, SInt64 size, void *, void *)
{
  OSErr e;
  short filenum = *file;
  if(filenum==0)	// file needs to be open first
    return -1;

  SInt64 tot_read = 0;
  ByteCount bytesread;
  // Align read on 4K boundary if possible
  const SInt64 bufsize = (size<4096) ? size : 4096;
  while(noErr==(e = FSReadFork(filenum, fsAtMark|noCacheMask, 0, bufsize, buf+tot_read, &bytesread))) {
    tot_read += bytesread;
    if(tot_read>=size)
      break;
  }

  if(e==eofErr)
    tot_read += bytesread;

  if(tot_read != size)
    return -1;

  // EOF is not an error, just a sign that the file was read successfully
  return (e==eofErr) ? noErr : e;
}


OSErr WriteFile(FSPtr &file, void *buf, SInt64 size, void *, void *)
{
  short filenum = *file;
  if(filenum==0)	// file needs to be open first
    return -1;

  FSRef fref = *file;
  FSPtr tempfile = FSPtr(new FSFile());
  UInt32 currentTime;
  ProcessSerialNumber pid;	// 64-bit data
  DCFStringPtr tempFileName;
  FSRef tempfolder;
  OSErr e;

  FSCatalogInfo inf;

  // If destination is different volume, save the temp file there
  // (since FSExchange only works inside the same volume)
  if((e=FSFindFolder(kLocalDomain, kTemporaryFolderType, TRUE, &tempfolder))==noErr) {
    if((e=FSGetCatalogInfo(&fref, kFSCatInfoVolume, &inf, NULL, NULL, NULL))==noErr) {
      FSVolumeRefNum origvol = inf.volume;
      // Get the actual vol number of the temp folder
      e = FSGetCatalogInfo(&tempfolder, kFSCatInfoVolume, &inf, NULL, NULL, NULL);
      if(e==noErr) {
        if(origvol != inf.volume)// on different volumes
          tempfolder = file->parent;	// force use of same volume
      }
    }
  }

  if(e!=noErr)
    tempfolder = file->parent;	// try a sensible alternative

  // Generate tempfile name based on current time and process pid
  GetDateTime(&currentTime);
  e = GetCurrentProcess(&pid);
  tempFileName = MakeCFObject(
    (e==noErr) ?
      CFStringCreateWithFormat(NULL, NULL, CFSTR("%lu%lu%@%lu"), pid.highLongOfPSN, pid.lowLongOfPSN, file->filename, currentTime) :
      CFStringCreateWithFormat(NULL, NULL, CFSTR("JFCd%@%d"), file->filename, currentTime)
    );
  if(tempFileName.get()==NULL)
    return -1;

  tempfile->parent = tempfolder;
  tempfile->filename = CFRetain(*tempFileName);
  e = tempfile->open(fsRdWrPerm, false, FOUR_CHAR_CODE('trsh'));

  if(e==noErr) {
    // write data here
    SInt64 tot_written = 0;
    ByteCount bytes_written;
    short temprefnum = *tempfile;
    const SInt64 bufsize = (size<4096) ? size : 4096;
    while(noErr==(e = FSWriteFork(temprefnum, 
        fsAtMark|noCacheMask, // os keeps track of file pointer
        0, // ignored
        bufsize, buf+tot_written, &bytes_written))) {
      tot_written += bytes_written;
      if(tot_written>=size)
        break;
    }

    if(tot_written < size) {	// disk full? couldn't complete write
      FSRef tempref = *tempfile;
      tempfile.reset();
      FSDeleteObject(&tempref);
      return (e==noErr) ? -1 : e;	// error no matter what
    }
  }

  if(e == noErr) {
    FSRef tempref = *tempfile;
    FSRef finalsrc, finaldest;
    // Must close the files early before deleting
    tempfile.reset(); // calls ~FSFile(), which calls FSCloseFork()
    file.reset();
    e = FSExchangeObjectsCompat(&tempref, &fref, &finalsrc, &finaldest);
    if(e == noErr)
      FSDeleteObject(&finalsrc);
  }

  return e;
}


UInt64 GetFileSize(FSPtr &file, void *)
{
  FSRef fref = *file;
  FSCatalogInfo info;

  OSErr e = FSGetCatalogInfo(
              &fref,
              kFSCatInfoDataSizes,
              &info,
              NULL, NULL, NULL);

  return (e==noErr) ? info.dataLogicalSize : 0;
}


int CompareFileTime(FILETIME *a, FILETIME *b)
{
  int result = 0;
  if(a->dwHighDateTime > b->dwHighDateTime)	// guaranteed a > b
    result = 1;
  else if(a->dwHighDateTime < b->dwHighDateTime)	// guaranteed a < b
    result = -1;
  else {
    if(a->dwLowDateTime > b->dwLowDateTime)
      result = 1;
    else if(a->dwLowDateTime < b->dwLowDateTime)
      result = -1;
  }

  return result;
}


long SetFilePointer(FSPtr &file, long offset, void *, FilePointerType startpoint)
{
  SInt16 forknum = *file;
  SInt64 updatedpos = 0;

  UInt16 mode;
  switch(startpoint) {
  case FILE_BEGIN: mode = fsFromStart; break;	// offset must be +ve
  case FILE_CURRENT: mode = fsFromMark; break;
  case FILE_END: mode = fsFromLEOF; break;	// offset must be -ve
  default:
    return INVALID_SET_FILE_POINTER;
  }

  OSErr e = FSSetForkPosition(forknum, mode, offset);
  // Duplicate behaviour of Win32 call by returning the updated position
  if(e==noErr)
    e = FSGetForkPosition(forknum, &updatedpos);

  return (e==noErr) ? (long)updatedpos : INVALID_SET_FILE_POINTER;
}


void SetTimer(void *, TimerType id, int msec, void *)
{
  switch(id) {
  case TIME_SHOW:
    doc_manager->getCurrent()->SetShowTimer(msec);
    break;
  case TIME_NEXT:
    doc_manager->getCurrent()->SetNextTimer(msec);
    break;
  }
}
*/

int MessageBox(HANDLE h, LPCTSTR szMessage, LPCTSTR title, int flags)
{
    int result = IDOK;
#if !TARGET_OS_IPHONE
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: NSLocalizedString([NSString stringWithUTF8String: szMessage],@"")];
    if (0 != (flags & MB_OK))
    {
        [alert addButtonWithTitle: NSLocalizedString(@"OK",@"")];
    }
    else if (0 != (flags & MB_YESNO))
    {
        [alert addButtonWithTitle: NSLocalizedString(@"Yes",@"")];
        [alert addButtonWithTitle: NSLocalizedString(@"No",@"")];
    }
    else if (0 != (flags & MB_YESNOCANCEL))
    {
        [alert addButtonWithTitle: NSLocalizedString(@"Yes",@"")];
        [alert addButtonWithTitle: NSLocalizedString(@"Cancel",@"")];
        [alert addButtonWithTitle: NSLocalizedString(@"No",@"")];
    }

    if (0 != (flags & MB_ICONSTOP))
        [alert setAlertStyle: NSAlertStyleCritical];
    else if (0 != (flags & MB_ICONINFORMATION))
        [alert setAlertStyle: NSAlertStyleInformational];

    result = (int)[alert runModal];
    [alert release];

    if (0 != (flags & MB_OK))
        result = IDOK;
    else if (0 != (flags & MB_YESNO))
        result = NSAlertFirstButtonReturn ? IDYES : IDNO;
    else if (0 != (flags & MB_YESNOCANCEL))
        result = NSAlertFirstButtonReturn ? IDYES :
            NSAlertSecondButtonReturn ? IDCANCEL : IDNO;
#endif
    return result;
}

BOOL QueryPerformanceFrequency(PLARGE_INTEGER l)
{
    static struct mach_timebase_info timebase = { 0, 0 };
    if (0 == timebase.denom)
        mach_timebase_info(&timebase);
//    l->LowPart  = 1e9 * timebase.denom / timebase.numer;
    l->QuadPart=1000000;
	return TRUE;
}

BOOL QueryPerformanceCounter(PLARGE_INTEGER l)
{
    l->QuadPart = mach_absolute_time() / 1000;
    return TRUE;
}

DWORD timeGetTime(void)
{
    time_t t = time(nil);
    return (DWORD)(t * 1000);
}

void EnterCriticalSection(CRITICAL_SECTION *lock)
{
    pthread_mutex_lock(lock);
}

void LeaveCriticalSection(CRITICAL_SECTION *lock)
{
    pthread_mutex_unlock(lock);
}

HANDLE CreateEvent(WORD attr, BOOL is_manual_reset, BOOL is_signaled, WORD name)
{
    if (nil == gEventLockDict)
    {
        gEventLockDict = [[NSMutableDictionary alloc] init];
    }
    ++gEventId;
    NSNumber *key = [[NSNumber alloc] initWithInt: gEventId];
    NSConditionLock *lock = [[NSConditionLock alloc] initWithCondition: 0];
    [gEventLockDict setObject:lock forKey:key];
    [lock release];
    [key release];
//    if (NULL == gEventLock)
//    {
//        gEventLock = [[NSConditionLock alloc] initWithCondition: 0];
//    }

    return gEventId;
}

void SetEvent(HANDLE eventId)
{
    NSNumber *key = [[NSNumber alloc] initWithInt: eventId];
    NSConditionLock *lock = [gEventLockDict objectForKey: key];
    [key release];
    if (lock)
    {
        [lock lock];
        [lock unlockWithCondition: eventId];
    }
}

BOOL ResetEvent(HANDLE eventId)
{
    NSNumber *key = [[NSNumber alloc] initWithInt: eventId];
    NSConditionLock *lock = [gEventLockDict objectForKey: key];
    [key release];
    if (lock)
    {
        [lock lock];
        [lock unlockWithCondition: 0];
        return YES;
    }
    return NO;
}

void DestroyEvent(HANDLE eventId)
{
    NSNumber *key = [[NSNumber alloc] initWithInt: eventId];
    NSConditionLock *lock = [gEventLockDict objectForKey: key];
    if (lock)
    {
        [gEventLockDict removeObjectForKey: key];
    }
    [key release];
}

DWORD WaitForSingleObject(HANDLE eventId, int timeout)
{
    DWORD result = WAIT_OBJECT_0;
    NSNumber *key = [[NSNumber alloc] initWithInt: eventId];
    NSConditionLock *lock = [gEventLockDict objectForKey: key];
    [key release];

    if (nil == lock)
        return WAIT_FAILED;

    if (timeout > 0)
    {
        NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow: (timeout/1000.0)];
        if (![lock lockWhenCondition:eventId beforeDate:timeoutDate])
            result = WAIT_TIMEOUT;
        [timeoutDate release];
    }
    else
    {
        [lock lockWhenCondition: eventId];
        [lock unlockWithCondition: 0];
    }
    return result;
}

void Sleep(int ms)
{
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: (ms / 1000.0)]];
//    [NSThread sleepUntilDate: [NSDate dateWithTimeIntervalSinceNow: (ms / 1000.0)]];
}


BOOL GetSystemPowerStatus(LPSYSTEM_POWER_STATUS status)
{
    status->ACLineStatus = AC_LINE_ONLINE;
    return TRUE;
}
