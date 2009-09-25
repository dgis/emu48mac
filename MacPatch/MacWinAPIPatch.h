#ifndef _MAC_WINAPIPATCH_H_
#define _MAC_WINAPIPATCH_H_
/*
 *  MacWinAPIPatch.h
 *  Emu48
 *
 *  Created by Da Woon Jung on Wed Dec 10 2003.
 *  Copyright (c) 2003 dwj. All rights reserved.
 *
 */

#import "MacTypePatch.h"
#import <stdio.h>
#import <string.h>

enum
{
    GENERIC_READ   = 1,
    GENERIC_WRITE  = 2,
    FILE_SHARE_READ  = 1,
    FILE_SHARE_WRITE = 2,
    OPEN_EXISTING = 121,
    FILE_ATTRIBUTE_NORMAL = 1,
    FILE_FLAG_OVERLAPPED  = 2,
    FILE_FLAG_SEQUENTIAL_SCAN = 4,
    PAGE_READONLY,
    FILE_MAP_READ,
    CREATE_ALWAYS,
    PAGE_READWRITE,
    PAGE_WRITECOPY,
    FILE_MAP_WRITE,
    FILE_MAP_COPY,

    //errors
    INVALID_HANDLE_VALUE = -1,
    ERROR_ALREADY_EXISTS = 1
};


enum MsgBoxFlagType {
    IDOK     = 0,
    IDYES    = 1,
    IDNO     = 2,
    IDCANCEL = 3,
    MB_OK              = 1,
    MB_YESNO           = 1 << 1,
    MB_YESNOCANCEL     = 1 << 2,
    MB_ICONWARNING     = 1 << 3,
    MB_ICONERROR       = 1 << 4,
    MB_ICONSTOP        = 1 << 5,
    MB_ICONINFORMATION = 1 << 6,
    MB_ICONQUESTION    = 1 << 7,
    MB_ICONEXCLAMATION = 1 << 8,
    MB_DEFBUTTON2      = 1 << 9
};

#define MB_APPLMODAL        0
#define MB_SETFOREGROUND    0

// These are passed to tab control callbacks
enum {
  WM_INITDIALOG,	// fills in tab controls when first shown
  WM_COMMAND,	// respond to validation/dimming commands
  WM_GETDLGVALUES	// read off the control settings
};

// Constants for the msg parameter in SendDlgItemMessage()
enum {
  CB_ERR = -1,
  CB_GETCURSEL = 1,
  CB_GETLBTEXT,
  CB_RESETCONTENT,
  CB_SETCURSEL,
  CB_ADDSTRING,
  WMU_SETWINDOWVALUE
};

// Constants for SetFilePointer
enum FilePointerType {
  INVALID_SET_FILE_POINTER = -1,
  FILE_BEGIN = 1,
  FILE_CURRENT,
  FILE_END
};

// Supposedly specifies that Windows use default window coords
enum { CW_USEDEFAULT };

enum {
    AC_LINE_OFFLINE,
    AC_LINE_ONLINE,
    AC_LINE_UNKNOWN = 255
};

enum {
    BATTERY_FLAG_HIGH = 1,
    BATTERY_FLAG_LOW = 2,
    BATTERY_FLAG_CRITICAL = 4,
    BATTERY_FLAG_CHARGING = 8,
    BATTERY_FLAG_NO_BATTERY = 128,
    BATTERY_FLAG_UNKNOWN = 255
};


// Macros
#ifdef _T
#undef _T
//#define _T(x)	@x
#endif
#define _T(x)   x

#define TEXT(x)	@x
#define LOWORD(x)	x

#define HIBYTE(i)   ((i)>>8)
#define LOBYTE(i)   (i)
#define _istdigit(c)    ((c)>='0' && (c)<='9')
#define lstrlen(s)      strlen(s)
#define lstrcpy(d,s)    strcpy(d,s)
#define _tcsspn(s,k)    strspn(s,k)
#define wsprintf(s,f,...)   sprintf(s,f, ## __VA_ARGS__)
#define HeapAlloc(h,v,s)    malloc(s)
#define HeapFree(h,v,p)     do{free(p);(p)=v;}while(0)
#define ZeroMemory(p,s)     memset(p,0,s)
#define FillMemory(p,n,v)   memset(p,v,n*sizeof(*(p)))
#define CopyMemory(d,src,s) memcpy(d,src,s)
//inline unsigned char HIBYTE(int i) { return i>>8; }
//inline unsigned char LOBYTE(int i) { return i; }
//inline BOOL _istdigit(unichar c) { return (c>='0' && c<='9'); }
/*
extern RGBColor RGB(int r, int g, int b);
inline ControlRef GetDlgItem(WindowRef window, SInt32 control_code)
{
  ControlRef control;
  ControlID	control_id = { app_signature, control_code };
  FailOSErr(GetControlByID(window, &control_id, &control));
  return control;
}
// For radio groups, 1=first choice, 2=second, etc
extern void CheckDlgButton(WindowRef, SInt32 control_code, SInt32 value);
extern void SetDlgItemInt(WindowRef, SInt32 control_code, int value, bool);
extern void SetDlgItemText(WindowRef, SInt32 control_code, CFStringRef);
// Use this to fiddle with dropdown menus (pass a CB_ constant for msg)
// Indexes are zero-based. Also handles WMU_SETWINDOWVALUE
extern int SendDlgItemMessage(WindowRef, SInt32 control_code, int msg, int p1, void *p2);
// For checkboxes, result will be zero or one (can cast directly to bool)
extern SInt32 IsDlgButtonChecked(WindowRef, SInt32 control_code);
// Despite its name, this dims/undims controls
extern void EnableWindow(ControlRef, bool enable);
// Used to fill in font dropdown menus
typedef FMFontFamilyCallbackFilterProcPtr FONTENUMPROC;
extern void EnumFontFamilies(void *, void *, FONTENUMPROC, void *userdata);
*/
extern BOOL SetCurrentDirectory(LPCTSTR);	// returns NO if fails
extern int CreateFile(LPCTSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPVOID lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, LPVOID hTemplateFile);
/*
extern int ReadFile(int fd, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, LPDWORD lpNumberOfBytesRead, LPVOID lpOverlapped);
// WriteFile() writes to a temp file, then swaps that with the real file
extern OSErr WriteFile(FSPtr &, void *buf, SInt64 size, void *, void *);
extern UInt64 GetFileSize(FSPtr &, void *);
// Do a strcmp-like comparison between 64-bit times
extern int CompareFileTime(FILETIME *, FILETIME *);
extern long SetFilePointer(FSPtr &, long offset, void *, FilePointerType startpoint);

extern void SetTimer(void *, TimerType, int msec, void *);
*/
extern int MessageBox(HANDLE, LPCTSTR szMessage, LPCTSTR szTitle, int flags);
extern BOOL QueryPerformanceFrequency(PLARGE_INTEGER l);
extern BOOL QueryPerformanceCounter(PLARGE_INTEGER l);
extern DWORD timeGetTime();
extern void EnterCriticalSection(CRITICAL_SECTION *);
extern void LeaveCriticalSection(CRITICAL_SECTION *);
extern HANDLE CreateEvent(WORD, BOOL, BOOL, WORD);
extern void SetEvent(HANDLE);
extern void DestroyEvent(HANDLE);
extern BOOL ResetEvent(HANDLE);
#define CloseEvent(h);

#define WAIT_OBJECT_0   0
#define WAIT_TIMEOUT    0x00000102
#define WAIT_FAILED     0xFFFFFFFF
extern DWORD WaitForSingleObject(HANDLE, int);
extern void Sleep(int);
#define UNREFERENCED_PARAMETER(a)

extern BOOL GetSystemPowerStatus(LPSYSTEM_POWER_STATUS l);
#endif
