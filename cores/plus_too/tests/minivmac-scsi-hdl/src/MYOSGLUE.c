/*
	MYOSGLUE.c

	Copyright (C) 2009 Michael Hanni, Christian Bauer,
	Stephan Kochen, Paul C. Pratt, and others

	You can redistribute this file and/or modify it under the terms
	of version 2 of the GNU General Public License as published by
	the Free Software Foundation.  You should have received a copy
	of the license along with this file; see the file COPYING.

	This file is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	license for more details.
*/

/*
	MY Operating System GLUE. (for X window system)

	All operating system dependent code for the
	X Window System should go here.

	This code is descended from Michael Hanni's X
	port of vMac, by Philip Cummins.
	I learned more about how X programs work by
	looking at other programs such as Basilisk II,
	the UAE Amiga Emulator, Bochs, QuakeForge,
	DooM Legacy, and the FLTK. A few snippets
	from them are used here.

	Drag and Drop support is based on the specification
	"XDND: Drag-and-Drop Protocol for the X Window System"
	developed by John Lindal at New Planet Software, and
	looking at included examples, one by Paul Sheer.
*/

#include "CNFGRAPI.h"
#include "SYSDEPNS.h"
#include "ENDIANAC.h"

#include "MYOSGLUE.h"

#include "STRCONST.h"

/* --- some simple utilities --- */

GLOBALPROC MyMoveBytes(anyp srcPtr, anyp destPtr, si5b byteCount)
{
	(void) memcpy((char *)destPtr, (char *)srcPtr, byteCount);
}

/* --- control mode and internationalization --- */

#define NeedCell2PlainAsciiMap 1

#include "INTLCHAR.h"


LOCALVAR char *d_arg = NULL;
LOCALVAR char *n_arg = NULL;

#if CanGetAppPath
LOCALVAR char *app_parent = NULL;
LOCALVAR char *app_name = NULL;
#endif

LOCALFUNC tMacErr ChildPath(char *x, char *y, char **r)
{
	tMacErr err = mnvm_miscErr;
	int nx = strlen(x);
	int ny = strlen(y);
	{
		if ((nx > 0) && ('/' == x[nx - 1])) {
			--nx;
		}
		{
			int nr = nx + 1 + ny;
			char *p = malloc(nr + 1);
			if (p != NULL) {
				char *p2 = p;
				(void) memcpy(p2, x, nx);
				p2 += nx;
				*p2++ = '/';
				(void) memcpy(p2, y, ny);
				p2 += ny;
				*p2 = 0;
				*r = p;
				err = mnvm_noErr;
			}
		}
	}

	return err;
}

#if UseActvFile || IncludeSonyNew
LOCALFUNC tMacErr FindOrMakeChild(char *x, char *y, char **r)
{
	tMacErr err = mnvm_miscErr;
	struct stat folder_info;
	char *r0;

	if (mnvm_noErr == (err = ChildPath(x, y, &r0))) {
		if (0 != stat(r0, &folder_info)) {
			if (0 == mkdir(r0, S_IRWXU)) {
				*r = r0;
				err = mnvm_noErr;
			}
		} else {
			if (S_ISDIR(folder_info.st_mode)) {
				*r = r0;
				err = mnvm_noErr;
			}
		}
	}

	return err;
}
#endif

LOCALPROC MyMayFree(char *p)
{
	if (NULL != p) {
		free(p);
	}
}

/* --- sending debugging info to file --- */

#if dbglog_HAVE

#define dbglog_ToStdErr 0

#if ! dbglog_ToStdErr
LOCALVAR FILE *dbglog_File = NULL;
#endif

LOCALFUNC blnr dbglog_open0(void)
{
#if dbglog_ToStdErr
	return trueblnr;
#else
	dbglog_File = fopen("dbglog.txt", "w");
	return (NULL != dbglog_File);
#endif
}

LOCALPROC dbglog_write0(char *s, uimr L)
{
#if dbglog_ToStdErr
	(void) fwrite(s, 1, L, stderr);
#else
	if (dbglog_File != NULL) {
		(void) fwrite(s, 1, L, dbglog_File);
	}
#endif
}

LOCALPROC dbglog_close0(void)
{
#if ! dbglog_ToStdErr
	if (dbglog_File != NULL) {
		fclose(dbglog_File);
		dbglog_File = NULL;
	}
#endif
}

#endif

/* --- debug settings and utilities --- */

#if ! dbglog_HAVE
#define WriteExtraErr(s)
#else
LOCALPROC WriteExtraErr(char *s)
{
	dbglog_writeCStr("*** error: ");
	dbglog_writeCStr(s);
	dbglog_writeReturn();
}
#endif

LOCALVAR Display *x_display = NULL;

#define MyDbgEvents (dbglog_HAVE && 0)

#if MyDbgEvents
LOCALPROC WriteDbgAtom(char *s, Atom x)
{
	char *name = XGetAtomName(x_display, x);
	if (name != NULL) {
		dbglog_writeCStr("Atom ");
		dbglog_writeCStr(s);
		dbglog_writeCStr(": ");
		dbglog_writeCStr(name);
		dbglog_writeReturn();
		XFree(name);
	}
}
#endif

/* --- information about the environment --- */

LOCALVAR Atom MyXA_DeleteW = (Atom)0;
#if EnableDragDrop
LOCALVAR Atom MyXA_UriList = (Atom)0;
LOCALVAR Atom MyXA_DndAware = (Atom)0;
LOCALVAR Atom MyXA_DndEnter = (Atom)0;
LOCALVAR Atom MyXA_DndLeave = (Atom)0;
LOCALVAR Atom MyXA_DndDrop = (Atom)0;
LOCALVAR Atom MyXA_DndPosition = (Atom)0;
LOCALVAR Atom MyXA_DndStatus = (Atom)0;
LOCALVAR Atom MyXA_DndActionCopy = (Atom)0;
LOCALVAR Atom MyXA_DndActionPrivate = (Atom)0;
LOCALVAR Atom MyXA_DndSelection = (Atom)0;
LOCALVAR Atom MyXA_DndFinished = (Atom)0;
LOCALVAR Atom MyXA_MinivMac_DndXchng = (Atom)0;
LOCALVAR Atom MyXA_NetActiveWindow = (Atom)0;
LOCALVAR Atom MyXA_NetSupported = (Atom)0;
#endif
#if IncludeHostTextClipExchange
LOCALVAR Atom MyXA_CLIPBOARD = (Atom)0;
LOCALVAR Atom MyXA_TARGETS = (Atom)0;
LOCALVAR Atom MyXA_MinivMac_Clip = (Atom)0;
#endif

LOCALPROC LoadMyXA(void)
{
	MyXA_DeleteW = XInternAtom(x_display, "WM_DELETE_WINDOW", False);
#if EnableDragDrop
	MyXA_UriList = XInternAtom (x_display, "text/uri-list", False);
	MyXA_DndAware = XInternAtom (x_display, "XdndAware", False);
	MyXA_DndEnter = XInternAtom(x_display, "XdndEnter", False);
	MyXA_DndLeave = XInternAtom(x_display, "XdndLeave", False);
	MyXA_DndDrop = XInternAtom(x_display, "XdndDrop", False);
	MyXA_DndPosition = XInternAtom(x_display, "XdndPosition", False);
	MyXA_DndStatus = XInternAtom(x_display, "XdndStatus", False);
	MyXA_DndActionCopy = XInternAtom(x_display,
		"XdndActionCopy", False);
	MyXA_DndActionPrivate = XInternAtom(x_display,
		"XdndActionPrivate", False);
	MyXA_DndSelection = XInternAtom(x_display, "XdndSelection", False);
	MyXA_DndFinished = XInternAtom(x_display, "XdndFinished", False);
	MyXA_MinivMac_DndXchng = XInternAtom(x_display,
		"_MinivMac_DndXchng", False);
	MyXA_NetActiveWindow = XInternAtom(x_display,
		"_NET_ACTIVE_WINDOW", False);
	MyXA_NetSupported = XInternAtom(x_display,
		"_NET_SUPPORTED", False);
#endif
#if IncludeHostTextClipExchange
	MyXA_CLIPBOARD = XInternAtom(x_display, "CLIPBOARD", False);
	MyXA_TARGETS = XInternAtom(x_display, "TARGETS", False);
	MyXA_MinivMac_Clip = XInternAtom(x_display,
		"_MinivMac_Clip", False);
#endif
}

#if EnableDragDrop
LOCALFUNC blnr NetSupportedContains(Atom x)
{
	/*
		Note that the window manager could be replaced at
		any time, so don't cache results of this function.
	*/
	Atom ret_type;
	int ret_format;
	unsigned long ret_item;
	unsigned long remain_byte;
	unsigned long i;
	unsigned char *s = 0;
	blnr foundit = falseblnr;
	Window rootwin = XRootWindow(x_display,
		DefaultScreen(x_display));

	if (Success != XGetWindowProperty(x_display, rootwin,
		MyXA_NetSupported,
		0, 65535, False, XA_ATOM, &ret_type, &ret_format,
		&ret_item, &remain_byte, &s))
	{
		WriteExtraErr("XGetWindowProperty failed");
	} else if (! s) {
		WriteExtraErr("XGetWindowProperty failed");
	} else if (ret_type != XA_ATOM) {
		WriteExtraErr("XGetWindowProperty returns wrong type");
	} else {
		Atom *v = (Atom *)s;

		for (i = 0; i < ret_item; ++i) {
			if (v[i] == x) {
				foundit = trueblnr;
				/* fprintf(stderr, "found the hint\n"); */
			}
		}
	}
	if (s) {
		XFree(s);
	}
	return foundit;
}
#endif

#define WantColorTransValid 1

#include "COMOSGLU.h"

#include "CONTROLM.h"

/* --- parameter buffers --- */

#if IncludePbufs
LOCALVAR void *PbufDat[NumPbufs];
#endif

#if IncludePbufs
LOCALFUNC tMacErr PbufNewFromPtr(void *p, ui5b count, tPbuf *r)
{
	tPbuf i;
	tMacErr err;

	if (! FirstFreePbuf(&i)) {
		free(p);
		err = mnvm_miscErr;
	} else {
		*r = i;
		PbufDat[i] = p;
		PbufNewNotify(i, count);
		err = mnvm_noErr;
	}

	return err;
}
#endif

#if IncludePbufs
GLOBALFUNC tMacErr PbufNew(ui5b count, tPbuf *r)
{
	tMacErr err = mnvm_miscErr;

	void *p = calloc(1, count);
	if (NULL != p) {
		err = PbufNewFromPtr(p, count, r);
	}

	return err;
}
#endif

#if IncludePbufs
GLOBALPROC PbufDispose(tPbuf i)
{
	free(PbufDat[i]);
	PbufDisposeNotify(i);
}
#endif

#if IncludePbufs
LOCALPROC UnInitPbufs(void)
{
	tPbuf i;

	for (i = 0; i < NumPbufs; ++i) {
		if (PbufIsAllocated(i)) {
			PbufDispose(i);
		}
	}
}
#endif

#if IncludePbufs
GLOBALPROC PbufTransfer(ui3p Buffer,
	tPbuf i, ui5r offset, ui5r count, blnr IsWrite)
{
	void *p = ((ui3p)PbufDat[i]) + offset;
	if (IsWrite) {
		(void) memcpy(p, Buffer, count);
	} else {
		(void) memcpy(Buffer, p, count);
	}
}
#endif

/* --- text translation --- */

#if IncludePbufs
/* this is table for Windows, any changes needed for X? */
LOCALVAR const ui3b Native2MacRomanTab[] = {
	0xAD, 0xB0, 0xE2, 0xC4, 0xE3, 0xC9, 0xA0, 0xE0,
	0xF6, 0xE4, 0xB6, 0xDC, 0xCE, 0xB2, 0xB3, 0xB7,
	0xB8, 0xD4, 0xD5, 0xD2, 0xD3, 0xA5, 0xD0, 0xD1,
	0xF7, 0xAA, 0xC5, 0xDD, 0xCF, 0xB9, 0xC3, 0xD9,
	0xCA, 0xC1, 0xA2, 0xA3, 0xDB, 0xB4, 0xBA, 0xA4,
	0xAC, 0xA9, 0xBB, 0xC7, 0xC2, 0xBD, 0xA8, 0xF8,
	0xA1, 0xB1, 0xC6, 0xD7, 0xAB, 0xB5, 0xA6, 0xE1,
	0xFC, 0xDA, 0xBC, 0xC8, 0xDE, 0xDF, 0xF0, 0xC0,
	0xCB, 0xE7, 0xE5, 0xCC, 0x80, 0x81, 0xAE, 0x82,
	0xE9, 0x83, 0xE6, 0xE8, 0xED, 0xEA, 0xEB, 0xEC,
	0xF5, 0x84, 0xF1, 0xEE, 0xEF, 0xCD, 0x85, 0xF9,
	0xAF, 0xF4, 0xF2, 0xF3, 0x86, 0xFA, 0xFB, 0xA7,
	0x88, 0x87, 0x89, 0x8B, 0x8A, 0x8C, 0xBE, 0x8D,
	0x8F, 0x8E, 0x90, 0x91, 0x93, 0x92, 0x94, 0x95,
	0xFD, 0x96, 0x98, 0x97, 0x99, 0x9B, 0x9A, 0xD6,
	0xBF, 0x9D, 0x9C, 0x9E, 0x9F, 0xFE, 0xFF, 0xD8
};
#endif

#if IncludePbufs
LOCALFUNC tMacErr NativeTextToMacRomanPbuf(char *x, tPbuf *r)
{
	if (NULL == x) {
		return mnvm_miscErr;
	} else {
		ui3p p;
		ui5b L = strlen(x);

		p = (ui3p)malloc(L);
		if (NULL == p) {
			return mnvm_miscErr;
		} else {
			ui3b *p0 = (ui3b *)x;
			ui3b *p1 = (ui3b *)p;
			int i;

			for (i = L; --i >= 0; ) {
				ui3b v = *p0++;
				if (v >= 128) {
					v = Native2MacRomanTab[v - 128];
				} else if (10 == v) {
					v = 13;
				}
				*p1++ = v;
			}

			return PbufNewFromPtr(p, L, r);
		}
	}
}
#endif

#if IncludePbufs
/* this is table for Windows, any changes needed for X? */
LOCALVAR const ui3b MacRoman2NativeTab[] = {
	0xC4, 0xC5, 0xC7, 0xC9, 0xD1, 0xD6, 0xDC, 0xE1,
	0xE0, 0xE2, 0xE4, 0xE3, 0xE5, 0xE7, 0xE9, 0xE8,
	0xEA, 0xEB, 0xED, 0xEC, 0xEE, 0xEF, 0xF1, 0xF3,
	0xF2, 0xF4, 0xF6, 0xF5, 0xFA, 0xF9, 0xFB, 0xFC,
	0x86, 0xB0, 0xA2, 0xA3, 0xA7, 0x95, 0xB6, 0xDF,
	0xAE, 0xA9, 0x99, 0xB4, 0xA8, 0x80, 0xC6, 0xD8,
	0x81, 0xB1, 0x8D, 0x8E, 0xA5, 0xB5, 0x8A, 0x8F,
	0x90, 0x9D, 0xA6, 0xAA, 0xBA, 0xAD, 0xE6, 0xF8,
	0xBF, 0xA1, 0xAC, 0x9E, 0x83, 0x9A, 0xB2, 0xAB,
	0xBB, 0x85, 0xA0, 0xC0, 0xC3, 0xD5, 0x8C, 0x9C,
	0x96, 0x97, 0x93, 0x94, 0x91, 0x92, 0xF7, 0xB3,
	0xFF, 0x9F, 0xB9, 0xA4, 0x8B, 0x9B, 0xBC, 0xBD,
	0x87, 0xB7, 0x82, 0x84, 0x89, 0xC2, 0xCA, 0xC1,
	0xCB, 0xC8, 0xCD, 0xCE, 0xCF, 0xCC, 0xD3, 0xD4,
	0xBE, 0xD2, 0xDA, 0xDB, 0xD9, 0xD0, 0x88, 0x98,
	0xAF, 0xD7, 0xDD, 0xDE, 0xB8, 0xF0, 0xFD, 0xFE
};
#endif

#if IncludePbufs
LOCALFUNC blnr MacRomanTextToNativePtr(tPbuf i, blnr IsFileName,
	ui3p *r)
{
	ui3p p;
	void *Buffer = PbufDat[i];
	ui5b L = PbufSize[i];

	p = (ui3p)malloc(L + 1);
	if (p != NULL) {
		ui3b *p0 = (ui3b *)Buffer;
		ui3b *p1 = (ui3b *)p;
		int j;

		if (IsFileName) {
			for (j = L; --j >= 0; ) {
				ui3b x = *p0++;
				if (x < 32) {
					x = '-';
				} else if (x >= 128) {
					x = MacRoman2NativeTab[x - 128];
				} else {
					switch (x) {
						case '/':
						case '<':
						case '>':
						case '|':
						case ':':
							x = '-';
						default:
							break;
					}
				}
				*p1++ = x;
			}
			if ('.' == p[0]) {
				p[0] = '-';
			}
		} else {
			for (j = L; --j >= 0; ) {
				ui3b x = *p0++;
				if (x >= 128) {
					x = MacRoman2NativeTab[x - 128];
				} else if (13 == x) {
					x = '\n';
				}
				*p1++ = x;
			}
		}
		*p1 = 0;

		*r = p;
		return trueblnr;
	}
	return falseblnr;
}
#endif

LOCALPROC NativeStrFromCStr(char *r, char *s)
{
	ui3b ps[ClStrMaxLength];
	int i;
	int L;

	ClStrFromSubstCStr(&L, ps, s);

	for (i = 0; i < L; ++i) {
		r[i] = Cell2PlainAsciiMap[ps[i]];
	}

	r[L] = 0;
}

/* --- drives --- */

#define NotAfileRef NULL

LOCALVAR FILE *Drives[NumDrives]; /* open disk image files */
#if IncludeSonyGetName || IncludeSonyNew
LOCALVAR char *DriveNames[NumDrives];
#endif

LOCALPROC InitDrives(void)
{
	/*
		This isn't really needed, Drives[i] and DriveNames[i]
		need not have valid values when not vSonyIsInserted[i].
	*/
	tDrive i;

	for (i = 0; i < NumDrives; ++i) {
		Drives[i] = NotAfileRef;
#if IncludeSonyGetName || IncludeSonyNew
		DriveNames[i] = NULL;
#endif
	}
}

GLOBALFUNC tMacErr vSonyTransfer(blnr IsWrite, ui3p Buffer,
	tDrive Drive_No, ui5r Sony_Start, ui5r Sony_Count,
	ui5r *Sony_ActCount)
{
	tMacErr err = mnvm_miscErr;
	FILE *refnum = Drives[Drive_No];
	ui5r NewSony_Count = 0;

	if (0 == fseek(refnum, Sony_Start, SEEK_SET)) {
		if (IsWrite) {
			NewSony_Count = fwrite(Buffer, 1, Sony_Count, refnum);
		} else {
			NewSony_Count = fread(Buffer, 1, Sony_Count, refnum);
		}

		if (NewSony_Count == Sony_Count) {
			err = mnvm_noErr;
		}
	}

	if (nullpr != Sony_ActCount) {
		*Sony_ActCount = NewSony_Count;
	}

	return err; /*& figure out what really to return &*/
}

GLOBALFUNC tMacErr vSonyGetSize(tDrive Drive_No, ui5r *Sony_Count)
{
	tMacErr err = mnvm_miscErr;
	FILE *refnum = Drives[Drive_No];
	long v;

	if (0 == fseek(refnum, 0, SEEK_END)) {
		v = ftell(refnum);
		if (v >= 0) {
			*Sony_Count = v;
			err = mnvm_noErr;
		}
	}

	return err; /*& figure out what really to return &*/
}

#ifndef HaveAdvisoryLocks
#define HaveAdvisoryLocks 1
#endif

/*
	What is the difference between fcntl(fd, F_SETLK ...
	and flock(fd ... ?
*/

#if HaveAdvisoryLocks
LOCALFUNC blnr MyLockFile(FILE *refnum)
{
	blnr IsOk = falseblnr;

#if 1
	struct flock fl;
	int fd = fileno(refnum);

	fl.l_start = 0; /* starting offset */
	fl.l_len = 0; /* len = 0 means until end of file */
	/* fl.pid_t l_pid; */ /* lock owner, don't need to set */
	fl.l_type = F_WRLCK; /* lock type: read/write, etc. */
	fl.l_whence = SEEK_SET; /* type of l_start */
	if (-1 == fcntl(fd, F_SETLK, &fl)) {
		MacMsg(kStrImageInUseTitle, kStrImageInUseMessage,
			falseblnr);
	} else {
		IsOk = trueblnr;
	}
#else
	int fd = fileno(refnum);

	if (-1 == flock(fd, LOCK_EX | LOCK_NB)) {
		MacMsg(kStrImageInUseTitle, kStrImageInUseMessage,
			falseblnr);
	} else {
		IsOk = trueblnr;
	}
#endif

	return IsOk;
}
#endif

#if HaveAdvisoryLocks
LOCALPROC MyUnlockFile(FILE *refnum)
{
#if 1
	struct flock fl;
	int fd = fileno(refnum);

	fl.l_start = 0; /* starting offset */
	fl.l_len = 0; /* len = 0 means until end of file */
	/* fl.pid_t l_pid; */ /* lock owner, don't need to set */
	fl.l_type = F_UNLCK;     /* lock type: read/write, etc. */
	fl.l_whence = SEEK_SET;   /* type of l_start */
	if (-1 == fcntl(fd, F_SETLK, &fl)) {
		/* an error occurred */
	}
#else
	int fd = fileno(refnum);

	if (-1 == flock(fd, LOCK_UN)) {
	}
#endif
}
#endif

LOCALFUNC tMacErr vSonyEject0(tDrive Drive_No, blnr deleteit)
{
	FILE *refnum = Drives[Drive_No];

	DiskEjectedNotify(Drive_No);

#if HaveAdvisoryLocks
	MyUnlockFile(refnum);
#endif

	fclose(refnum);
	Drives[Drive_No] = NotAfileRef; /* not really needed */

#if IncludeSonyGetName || IncludeSonyNew
	{
		char *s = DriveNames[Drive_No];
		if (NULL != s) {
			if (deleteit) {
				remove(s);
			}
			free(s);
			DriveNames[Drive_No] = NULL; /* not really needed */
		}
	}
#endif

	return mnvm_noErr;
}

GLOBALFUNC tMacErr vSonyEject(tDrive Drive_No)
{
	return vSonyEject0(Drive_No, falseblnr);
}

#if IncludeSonyNew
GLOBALFUNC tMacErr vSonyEjectDelete(tDrive Drive_No)
{
	return vSonyEject0(Drive_No, trueblnr);
}
#endif

LOCALPROC UnInitDrives(void)
{
	tDrive i;

	for (i = 0; i < NumDrives; ++i) {
		if (vSonyIsInserted(i)) {
			(void) vSonyEject(i);
		}
	}
}

#if IncludeSonyGetName
GLOBALFUNC tMacErr vSonyGetName(tDrive Drive_No, tPbuf *r)
{
	char *drivepath = DriveNames[Drive_No];
	if (NULL == drivepath) {
		return mnvm_miscErr;
	} else {
		char *s = strrchr(drivepath, '/');
		if (NULL == s) {
			s = drivepath;
		} else {
			++s;
		}
		return NativeTextToMacRomanPbuf(s, r);
	}
}
#endif

LOCALFUNC blnr Sony_Insert0(FILE *refnum, blnr locked,
	char *drivepath)
{
	tDrive Drive_No;
	blnr IsOk = falseblnr;

	if (! FirstFreeDisk(&Drive_No)) {
		MacMsg(kStrTooManyImagesTitle, kStrTooManyImagesMessage,
			falseblnr);
	} else {
		/* printf("Sony_Insert0 %d\n", (int)Drive_No); */

#if HaveAdvisoryLocks
		if (locked || MyLockFile(refnum))
#endif
		{
			Drives[Drive_No] = refnum;
			DiskInsertNotify(Drive_No, locked);

#if IncludeSonyGetName || IncludeSonyNew
			{
				ui5b L = strlen(drivepath);
				char *p = malloc(L + 1);
				if (p != NULL) {
					(void) memcpy(p, drivepath, L + 1);
				}
				DriveNames[Drive_No] = p;
			}
#endif

			IsOk = trueblnr;
		}
	}

	if (! IsOk) {
		fclose(refnum);
	}

	return IsOk;
}

LOCALFUNC blnr Sony_Insert1(char *drivepath, blnr silentfail)
{
	blnr locked = falseblnr;
	/* printf("Sony_Insert1 %s\n", drivepath); */
	FILE *refnum = fopen(drivepath, "rb+");
	if (NULL == refnum) {
		locked = trueblnr;
		refnum = fopen(drivepath, "rb");
	}
	if (NULL == refnum) {
		if (! silentfail) {
			MacMsg(kStrOpenFailTitle, kStrOpenFailMessage, falseblnr);
		}
	} else {
		return Sony_Insert0(refnum, locked, drivepath);
	}
	return falseblnr;
}

LOCALFUNC blnr Sony_Insert2(char *s)
{
	char *d =
#if CanGetAppPath
		(NULL == d_arg) ? app_parent :
#endif
		d_arg;
	blnr IsOk = falseblnr;

	if (NULL == d) {
		IsOk = Sony_Insert1(s, trueblnr);
	} else {
		char *t;

		if (mnvm_noErr == ChildPath(d, s, &t)) {
			IsOk = Sony_Insert1(t, trueblnr);
			free(t);
		}
	}

	return IsOk;
}

LOCALFUNC blnr LoadInitialImages(void)
{
	if (! AnyDiskInserted()) {
		int n = NumDrives > 9 ? 9 : NumDrives;
		int i;
		char s[] = "disk?.dsk";

		for (i = 1; i <= n; ++i) {
			s[4] = '0' + i;
			if (! Sony_Insert2(s)) {
				/* stop on first error (including file not found) */
				return trueblnr;
			}
		}
	}

	return trueblnr;
}

#if IncludeSonyNew
LOCALFUNC blnr WriteZero(FILE *refnum, ui5b L)
{
#define ZeroBufferSize 2048
	ui5b i;
	ui3b buffer[ZeroBufferSize];

	memset(&buffer, 0, ZeroBufferSize);

	while (L > 0) {
		i = (L > ZeroBufferSize) ? ZeroBufferSize : L;
		if (fwrite(buffer, 1, i, refnum) != i) {
			return falseblnr;
		}
		L -= i;
	}
	return trueblnr;
}
#endif

#if IncludeSonyNew
LOCALPROC MakeNewDisk0(ui5b L, char *drivepath)
{
	blnr IsOk = falseblnr;
	FILE *refnum = fopen(drivepath, "wb+");
	if (NULL == refnum) {
		MacMsg(kStrOpenFailTitle, kStrOpenFailMessage, falseblnr);
	} else {
		if (WriteZero(refnum, L)) {
			IsOk = Sony_Insert0(refnum, falseblnr, drivepath);
			refnum = NULL;
		}
		if (refnum != NULL) {
			fclose(refnum);
		}
		if (! IsOk) {
			(void) remove(drivepath);
		}
	}
}
#endif

#if IncludeSonyNew
LOCALPROC MakeNewDisk(ui5b L, char *drivename)
{
	char *d =
#if CanGetAppPath
		(NULL == d_arg) ? app_parent :
#endif
		d_arg;

	if (NULL == d) {
		MakeNewDisk0(L, drivename); /* in current directory */
	} else {
		tMacErr err;
		char *t = NULL;
		char *t2 = NULL;

		if (mnvm_noErr == (err = FindOrMakeChild(d, "out", &t)))
		if (mnvm_noErr == (err = ChildPath(t, drivename, &t2)))
		{
			MakeNewDisk0(L, t2);
		}

		MyMayFree(t2);
		MyMayFree(t);
	}
}
#endif

#if IncludeSonyNew
LOCALPROC MakeNewDiskAtDefault(ui5b L)
{
	char s[ClStrMaxLength + 1];

	NativeStrFromCStr(s, "untitled.dsk");
	MakeNewDisk(L, s);
}
#endif

/* --- ROM --- */

LOCALVAR char *rom_path = NULL;

LOCALFUNC tMacErr LoadMacRomFrom(char *path)
{
	tMacErr err;
	FILE *ROM_File;
	int File_Size;

	ROM_File = fopen(path, "rb");
	if (NULL == ROM_File) {
		err = mnvm_fnfErr;
	} else {
	  printf("reading %d bytes\n", kROM_Size);
		File_Size = fread(ROM, 1, kROM_Size, ROM_File);
		if (File_Size != kROM_Size) {
			if (feof(ROM_File)) {
				err = mnvm_eofErr;
			} else {
				err = mnvm_miscErr;
			}
		} else {
			err = mnvm_noErr;
		}
		fclose(ROM_File);
	}

	return err;
}

#if 0
#include <pwd.h>
#include <unistd.h>
#endif

LOCALFUNC tMacErr FindUserHomeFolder(char **r)
{
	tMacErr err = mnvm_fnfErr;
	char *s = getenv("HOME");

#if 0
	if (NULL == s) {
		struct passwd *user = getpwuid(getuid());
		if (user != NULL) {
			s = user->pw_dir;
		}
	} else
#endif
	{
		*r = s;
		err = mnvm_noErr;
	}

	return err;
}

LOCALFUNC tMacErr LoadMacRomFromHome(void)
{
	tMacErr err;
	char *s;
	char *t = NULL;
	char *t2 = NULL;
	char *t3 = NULL;

	if (mnvm_noErr == (err = FindUserHomeFolder(&s)))
	if (mnvm_noErr == (err = ChildPath(s, ".gryphel", &t)))
	if (mnvm_noErr == (err = ChildPath(t, "mnvm_rom", &t2)))
	if (mnvm_noErr == (err = ChildPath(t2, RomFileName, &t3)))
	{
		err = LoadMacRomFrom(t3);
	}

	MyMayFree(t3);
	MyMayFree(t2);
	MyMayFree(t);

	return err;
}

#if CanGetAppPath
LOCALFUNC tMacErr LoadMacRomFromAppPar(void)
{
	tMacErr err;
	char *d =
#if CanGetAppPath
		(NULL == d_arg) ? app_parent :
#endif
		d_arg;
	char *t = NULL;

	if (NULL == d) {
		err = mnvm_fnfErr;
	} else {
		if (mnvm_noErr == (err = ChildPath(d, RomFileName,
			&t)))
		{
			err = LoadMacRomFrom(t);
		}
	}

	MyMayFree(t);

	return err;
}
#endif

LOCALFUNC blnr LoadMacRom(void)
{
	tMacErr err;

	if ((NULL == rom_path)
		|| (mnvm_fnfErr == (err = LoadMacRomFrom(rom_path))))
	if (mnvm_fnfErr == (err = LoadMacRomFromHome()))
#if CanGetAppPath
	if (mnvm_fnfErr == (err = LoadMacRomFromAppPar()))
#endif
	if (mnvm_fnfErr == (err = LoadMacRomFrom(RomFileName)))
	{
	}

	if (mnvm_noErr != err) {
		if (mnvm_fnfErr == err) {
			MacMsg(kStrNoROMTitle, kStrNoROMMessage, trueblnr);
		} else if (mnvm_eofErr == err) {
			MacMsg(kStrShortROMTitle, kStrShortROMMessage,
				trueblnr);
		} else {
			MacMsg(kStrNoReadROMTitle, kStrNoReadROMMessage,
				trueblnr);
		}

		SpeedStopped = trueblnr;
	}

	return trueblnr; /* keep launching Mini vMac, regardless */
}

#if UseActvFile

#define ActvCodeFileName "act_1"

LOCALFUNC tMacErr ActvCodeFileLoad(ui3p p)
{
	tMacErr err;
	char *s;
	char *t = NULL;
	char *t2 = NULL;
	char *t3 = NULL;

	if (mnvm_noErr == (err = FindUserHomeFolder(&s)))
	if (mnvm_noErr == (err = ChildPath(s, ".gryphel", &t)))
	if (mnvm_noErr == (err = ChildPath(t, "mnvm_act", &t2)))
	if (mnvm_noErr == (err = ChildPath(t2, ActvCodeFileName, &t3)))
	{
		FILE *Actv_File;
		int File_Size;

		Actv_File = fopen(t3, "rb");
		if (NULL == Actv_File) {
			err = mnvm_fnfErr;
		} else {
			File_Size = fread(p, 1, ActvCodeFileLen, Actv_File);
			if (File_Size != ActvCodeFileLen) {
				if (feof(Actv_File)) {
					err = mnvm_eofErr;
				} else {
					err = mnvm_miscErr;
				}
			} else {
				err = mnvm_noErr;
			}
			fclose(Actv_File);
		}
	}

	MyMayFree(t3);
	MyMayFree(t2);
	MyMayFree(t);

	return err;
}

LOCALFUNC tMacErr ActvCodeFileSave(ui3p p)
{
	tMacErr err;
	char *s;
	char *t = NULL;
	char *t2 = NULL;
	char *t3 = NULL;

	if (mnvm_noErr == (err = FindUserHomeFolder(&s)))
	if (mnvm_noErr == (err = FindOrMakeChild(s, ".gryphel", &t)))
	if (mnvm_noErr == (err = FindOrMakeChild(t, "mnvm_act", &t2)))
	if (mnvm_noErr == (err = ChildPath(t2, ActvCodeFileName, &t3)))
	{
		FILE *Actv_File;
		int File_Size;

		Actv_File = fopen(t3, "wb+");
		if (NULL == Actv_File) {
			err = mnvm_fnfErr;
		} else {
			File_Size = fwrite(p, 1, ActvCodeFileLen, Actv_File);
			if (File_Size != ActvCodeFileLen) {
				err = mnvm_miscErr;
			} else {
				err = mnvm_noErr;
			}
			fclose(Actv_File);
		}
	}

	MyMayFree(t3);
	MyMayFree(t2);
	MyMayFree(t);

	return err;
}

#endif /* UseActvFile */

/* --- video out --- */

LOCALVAR Window my_main_wind = 0;
LOCALVAR GC my_gc = NULL;
LOCALVAR blnr NeedFinishOpen1 = falseblnr;
LOCALVAR blnr NeedFinishOpen2 = falseblnr;

LOCALVAR XColor x_black;
LOCALVAR XColor x_white;

#if MayFullScreen
LOCALVAR short hOffset;
LOCALVAR short vOffset;
#endif

#if VarFullScreen
LOCALVAR blnr UseFullScreen = (WantInitFullScreen != 0);
#endif

#if EnableMagnify
LOCALVAR blnr UseMagnify = (WantInitMagnify != 0);
#endif

LOCALVAR blnr gBackgroundFlag = falseblnr;
LOCALVAR blnr gTrueBackgroundFlag = falseblnr;
LOCALVAR blnr CurSpeedStopped = trueblnr;

LOCALVAR XImage *my_image = NULL;

#if EnableMagnify
LOCALVAR XImage *my_Scaled_image = NULL;
#endif

#if 0 != vMacScreenDepth
LOCALVAR XImage *my_Color_image = NULL;
#endif

#if EnableMagnify && (0 != vMacScreenDepth)
LOCALVAR XImage *my_ScaledColor_image = NULL;
#endif


#if EnableMagnify
#define MaxScale MyWindowScale
#else
#define MaxScale 1
#endif


#define WantScalingTabl (EnableMagnify \
	|| ((0 != vMacScreenDepth) && (vMacScreenDepth < 4)))

#if WantScalingTabl

LOCALVAR ui3p ScalingTabl = nullpr;

#if EnableMagnify

#define ScalingTablsz1 (256 * MyWindowScale)

#else
#define ScalingTablsz1 0
#endif

#if (0 != vMacScreenDepth) && (vMacScreenDepth < 4)

#define CLUT_finalClrSz ((256 * MaxScale) << (5 - vMacScreenDepth))

#define ScalingTablsz ((CLUT_finalClrSz > ScalingTablsz1) \
	? CLUT_finalClrSz : ScalingTablsz1)

#else
#define ScalingTablsz ScalingTablsz1
#endif

#endif /* WantScalingTabl */


#define WantScalingBuff (EnableMagnify \
	|| ((0 != vMacScreenDepth) && (vMacScreenDepth < 5)))

#if WantScalingBuff

LOCALVAR ui3p ScalingBuff = nullpr;

#if EnableMagnify

#define ScalingBuffsz1 ((long)vMacScreenNumBytes \
	* MyWindowScale * MyWindowScale)

#else
#define ScalingBuffsz1 0
#endif

#if (0 != vMacScreenDepth)

#define ScalingBuffColorsz \
	(vMacScreenNumPixels * 4 * MaxScale * MaxScale)

#define ScalingBuffsz ((ScalingBuffColorsz > ScalingBuffsz1) \
	? ScalingBuffColorsz : ScalingBuffsz1)

#else
#define ScalingBuffsz ScalingBuffsz1
#endif

#endif /* WantScalingBuff */


#if EnableMagnify
LOCALPROC SetUpScalingTabl(void)
{
	ui3b *p4;
	int i;
	int j;
	int k;
	ui3r bitsRemaining;
	ui3b t1;
	ui3b t2;

	p4 = ScalingTabl;
	for (i = 0; i < 256; ++i) {
		bitsRemaining = 8;
		t2 = 0;
		for (j = 8; --j >= 0; ) {
			t1 = (i >> j) & 1;
			for (k = MyWindowScale; --k >= 0; ) {
				t2 = (t2 << 1) | t1;
				if (--bitsRemaining == 0) {
					*p4++ = t2;
					bitsRemaining = 8;
					t2 = 0;
				}
			}
		}
	}
}
#endif

#if EnableMagnify && (0 != vMacScreenDepth) && (vMacScreenDepth < 4)
LOCALPROC SetUpColorScalingTabl(void)
{
	int i;
	int j;
	int k;
	int a;
	ui5r v;
	ui5p p4;

	p4 = (ui5p)ScalingTabl;
	for (i = 0; i < 256; ++i) {
		for (k = 1 << (3 - vMacScreenDepth); --k >= 0; ) {
			j = (i >> (k << vMacScreenDepth)) & (CLUT_size - 1);
			v = (((long)CLUT_reds[j] & 0xFF00) << 8)
				| ((long)CLUT_greens[j] & 0xFF00)
				| (((long)CLUT_blues[j] & 0xFF00) >> 8);
			for (a = MyWindowScale; --a >= 0; ) {
				*p4++ = v;
			}
		}
	}
}
#endif

#if (0 != vMacScreenDepth) && (vMacScreenDepth < 4)
LOCALPROC SetUpColorTabl(void)
{
	int i;
	int j;
	int k;
	ui5p p4;

	p4 = (ui5p)ScalingTabl;
	for (i = 0; i < 256; ++i) {
		for (k = 1 << (3 - vMacScreenDepth); --k >= 0; ) {
			j = (i >> (k << vMacScreenDepth)) & (CLUT_size - 1);
			*p4++ = (((long)CLUT_reds[j] & 0xFF00) << 8)
				| ((long)CLUT_greens[j] & 0xFF00)
				| (((long)CLUT_blues[j] & 0xFF00) >> 8);
		}
	}
}
#endif

#if EnableMagnify

#define ScrnMapr_DoMap UpdateScaledBWCopy
#define ScrnMapr_Src GetCurDrawBuff()
#define ScrnMapr_Dst ScalingBuff
#define ScrnMapr_SrcDepth 0
#define ScrnMapr_DstDepth 0
#define ScrnMapr_Map ScalingTabl
#define ScrnMapr_Scale MyWindowScale

#include "SCRNMAPR.h"

#endif


#if (0 != vMacScreenDepth) && (vMacScreenDepth < 4)

#define ScrnMapr_DoMap UpdateMappedColorCopy
#define ScrnMapr_Src GetCurDrawBuff()
#define ScrnMapr_Dst ScalingBuff
#define ScrnMapr_SrcDepth vMacScreenDepth
#define ScrnMapr_DstDepth 5
#define ScrnMapr_Map ScalingTabl

#include "SCRNMAPR.h"

#endif


#if EnableMagnify && (0 != vMacScreenDepth) && (vMacScreenDepth < 4)

#define ScrnMapr_DoMap UpdateMappedScaledColorCopy
#define ScrnMapr_Src GetCurDrawBuff()
#define ScrnMapr_Dst ScalingBuff
#define ScrnMapr_SrcDepth vMacScreenDepth
#define ScrnMapr_DstDepth 5
#define ScrnMapr_Map ScalingTabl
#define ScrnMapr_Scale MyWindowScale

#include "SCRNMAPR.h"

#endif


#if vMacScreenDepth == 4

#define ScrnTrns_DoTrans UpdateTransColorCopy
#define ScrnTrns_Src GetCurDrawBuff()
#define ScrnTrns_Dst ScalingBuff
#define ScrnTrns_SrcDepth vMacScreenDepth
#define ScrnTrns_DstDepth 5

#include "SCRNTRNS.h"

#endif

#if EnableMagnify && (vMacScreenDepth >= 4)

#define ScrnTrns_DoTrans UpdateTransScaledColorCopy
#define ScrnTrns_Src GetCurDrawBuff()
#define ScrnTrns_Dst ScalingBuff
#define ScrnTrns_SrcDepth vMacScreenDepth
#define ScrnTrns_DstDepth 5
#define ScrnTrns_Scale MyWindowScale

#include "SCRNTRNS.h"

#endif

LOCALPROC HaveChangedScreenBuff(ui4r top, ui4r left,
	ui4r bottom, ui4r right)
{
	int XDest;
	int YDest;
	XImage *the_image;
	char *the_data;

	//	fprintf(stderr, "have changed screen buf %d,%d %d,%d\n", top, left, bottom, right);

	top = ViewVStart;
	left = ViewHStart;
	bottom = ViewVStart + ViewVSize - 1;
	right = ViewHStart + ViewHSize - 1;
	
#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		if (top < ViewVStart) {
			top = ViewVStart;
		}
		if (left < ViewHStart) {
			left = ViewHStart;
		}
		if (bottom >= ViewVStart + ViewVSize) {
			bottom = ViewVStart + ViewVSize - 1;
		}
		if (right >= ViewHStart + ViewHSize) {
			right = ViewHStart + ViewHSize - 1;
		}

		if ((top >= bottom) || (left >= right)) {
			goto label_exit;
		}
	}
#endif

	XDest = left;
	YDest = top;

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		XDest -= ViewHStart;
		YDest -= ViewVStart;
	}
#endif

#if EnableMagnify
	if (UseMagnify) {
		XDest *= MyWindowScale;
		YDest *= MyWindowScale;
	}
#endif

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		XDest += hOffset;
		YDest += vOffset;
	}
#endif

#if 0 != vMacScreenDepth
	if (UseColorMode) {

#if EnableMagnify
		if (UseMagnify) {
			the_image = my_ScaledColor_image;

#if vMacScreenDepth < 4
			if (! ColorTransValid) {
				SetUpColorScalingTabl();
				ColorTransValid = trueblnr;
			}

			UpdateMappedScaledColorCopy(top, left, bottom, right);
#else
			UpdateTransScaledColorCopy(top, left, bottom, right);
#endif

			the_data = (char *)ScalingBuff;
		} else
#endif
		{
			the_image = my_Color_image;

#if vMacScreenDepth < 4

			if (! ColorTransValid) {
				SetUpColorTabl();
				ColorTransValid = trueblnr;
			}

			UpdateMappedColorCopy(top, left, bottom, right);

			the_data = (char *)ScalingBuff;
#elif vMacScreenDepth == 4
			UpdateTransColorCopy(top, left, bottom, right);

			the_data = (char *)ScalingBuff;
#else
			the_data = (char *)GetCurDrawBuff();
#endif
		}
	} else
#endif
	{
#if EnableMagnify
		if (UseMagnify) {
			the_image = my_Scaled_image;

			if (! ColorTransValid) {
				SetUpScalingTabl();
				ColorTransValid = trueblnr;
			}

			UpdateScaledBWCopy(top, left, bottom, right);

			the_data = (char *)ScalingBuff;
		} else
#endif
		{
			the_image = my_image;
			the_data = (char *)GetCurDrawBuff();
		}
	}

	{
		char *saveData = the_image->data;
		the_image->data = the_data;

#if EnableMagnify
		if (UseMagnify) {
			XPutImage(x_display, my_main_wind, my_gc, the_image,
				left * MyWindowScale, top * MyWindowScale,
				XDest, YDest,
				(right - left) * MyWindowScale,
				(bottom - top) * MyWindowScale);
		} else
#endif
		{
			XPutImage(x_display, my_main_wind, my_gc, the_image,
				left, top, XDest, YDest,
				right - left, bottom - top);
		}

		the_image->data = saveData;
	}

#if MayFullScreen
label_exit:
	;
#endif
}

LOCALPROC MyDrawChangesAndClear(void)
{
	if (ScreenChangedBottom > ScreenChangedTop) {
		HaveChangedScreenBuff(ScreenChangedTop, ScreenChangedLeft,
			ScreenChangedBottom, ScreenChangedRight);
		ScreenClearChanges();
	}
}

/* --- mouse --- */

/* cursor hiding */

LOCALVAR blnr HaveCursorHidden = falseblnr;
LOCALVAR blnr WantCursorHidden = falseblnr;

LOCALPROC ForceShowCursor(void)
{
	if (HaveCursorHidden) {
		HaveCursorHidden = falseblnr;
		if (my_main_wind) {
			XUndefineCursor(x_display, my_main_wind);
		}
	}
}

LOCALVAR Cursor blankCursor = None;

LOCALFUNC blnr CreateMyBlankCursor(Window rootwin)
/*
	adapted from X11_CreateNullCursor in context.x11.c
	in quakeforge 0.5.5, copyright Id Software, Inc.
	Zephaniah E. Hull, and Jeff Teunissen.
*/
{
	Pixmap cursormask;
	XGCValues xgc;
	GC gc;
	blnr IsOk = falseblnr;

	cursormask = XCreatePixmap(x_display, rootwin, 1, 1, 1);
	if (None == cursormask) {
		WriteExtraErr("XCreatePixmap failed.");
	} else {
		xgc.function = GXclear;
		gc = XCreateGC(x_display, cursormask, GCFunction, &xgc);
		if (None == gc) {
			WriteExtraErr("XCreateGC failed.");
		} else {
			XFillRectangle(x_display, cursormask, gc, 0, 0, 1, 1);
			XFreeGC(x_display, gc);

			blankCursor = XCreatePixmapCursor(x_display, cursormask,
							cursormask, &x_black, &x_white, 0, 0);
			if (None == blankCursor) {
				WriteExtraErr("XCreatePixmapCursor failed.");
			} else {
				IsOk = trueblnr;
			}
		}

		XFreePixmap(x_display, cursormask);
		/*
			assuming that XCreatePixmapCursor doesn't think it
			owns the pixmaps passed to it. I've seen code that
			assumes this, and other code that seems to assume
			the opposite.
		*/
	}
	return IsOk;
}

/* cursor moving */

LOCALFUNC blnr MyMoveMouse(si4b h, si4b v)
{
	int NewMousePosh;
	int NewMousePosv;
	int root_x_return;
	int root_y_return;
	Window root_return;
	Window child_return;
	unsigned int mask_return;
	blnr IsOk;
	int attempts = 0;

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		h -= ViewHStart;
		v -= ViewVStart;
	}
#endif

#if EnableMagnify
	if (UseMagnify) {
		h *= MyWindowScale;
		v *= MyWindowScale;
	}
#endif

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		h += hOffset;
		v += vOffset;
	}
#endif

	do {
		XWarpPointer(x_display, None, my_main_wind, 0, 0, 0, 0, h, v);
		XQueryPointer(x_display, my_main_wind,
			&root_return, &child_return,
			&root_x_return, &root_y_return,
			&NewMousePosh, &NewMousePosv,
			&mask_return);
		IsOk = (h == NewMousePosh) && (v == NewMousePosv);
		++attempts;
	} while ((! IsOk) && (attempts < 10));
	return IsOk;
}

#if EnableMouseMotion && MayFullScreen
LOCALPROC StartSaveMouseMotion(void)
{
	if (! HaveMouseMotion) {
		if (MyMoveMouse(ViewHStart + (ViewHSize / 2),
			ViewVStart + (ViewVSize / 2)))
		{
			SavedMouseH = ViewHStart + (ViewHSize / 2);
			SavedMouseV = ViewVStart + (ViewVSize / 2);
			HaveMouseMotion = trueblnr;
		}
	}
}
#endif

#if EnableMouseMotion && MayFullScreen
LOCALPROC StopSaveMouseMotion(void)
{
	if (HaveMouseMotion) {
		(void) MyMoveMouse(CurMouseH, CurMouseV);
		HaveMouseMotion = falseblnr;
	}
}
#endif

/* cursor state */

#if EnableMouseMotion && MayFullScreen
LOCALPROC MyMouseConstrain(void)
{
	si4b shiftdh;
	si4b shiftdv;

	if (SavedMouseH < ViewHStart + (ViewHSize / 4)) {
		shiftdh = ViewHSize / 2;
	} else if (SavedMouseH > ViewHStart + ViewHSize - (ViewHSize / 4)) {
		shiftdh = - ViewHSize / 2;
	} else {
		shiftdh = 0;
	}
	if (SavedMouseV < ViewVStart + (ViewVSize / 4)) {
		shiftdv = ViewVSize / 2;
	} else if (SavedMouseV > ViewVStart + ViewVSize - (ViewVSize / 4)) {
		shiftdv = - ViewVSize / 2;
	} else {
		shiftdv = 0;
	}
	if ((shiftdh != 0) || (shiftdv != 0)) {
		SavedMouseH += shiftdh;
		SavedMouseV += shiftdv;
		if (! MyMoveMouse(SavedMouseH, SavedMouseV)) {
			HaveMouseMotion = falseblnr;
		}
	}
}
#endif

LOCALPROC MousePositionNotify(int NewMousePosh, int NewMousePosv)
{
	blnr ShouldHaveCursorHidden = trueblnr;

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		NewMousePosh -= hOffset;
		NewMousePosv -= vOffset;
	}
#endif

#if EnableMagnify
	if (UseMagnify) {
		NewMousePosh /= MyWindowScale;
		NewMousePosv /= MyWindowScale;
	}
#endif

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		NewMousePosh += ViewHStart;
		NewMousePosv += ViewVStart;
	}
#endif

#if EnableMouseMotion && MayFullScreen
	if (HaveMouseMotion) {
		MyMousePositionSetDelta(NewMousePosh - SavedMouseH,
			NewMousePosv - SavedMouseV);
		SavedMouseH = NewMousePosh;
		SavedMouseV = NewMousePosv;
	} else
#endif
	{
		if (NewMousePosh < 0) {
			NewMousePosh = 0;
			ShouldHaveCursorHidden = falseblnr;
		} else if (NewMousePosh >= vMacScreenWidth) {
			NewMousePosh = vMacScreenWidth - 1;
			ShouldHaveCursorHidden = falseblnr;
		}
		if (NewMousePosv < 0) {
			NewMousePosv = 0;
			ShouldHaveCursorHidden = falseblnr;
		} else if (NewMousePosv >= vMacScreenHeight) {
			NewMousePosv = vMacScreenHeight - 1;
			ShouldHaveCursorHidden = falseblnr;
		}

#if VarFullScreen
		if (UseFullScreen)
#endif
#if MayFullScreen
		{
			ShouldHaveCursorHidden = trueblnr;
		}
#endif

		/* if (ShouldHaveCursorHidden || CurMouseButton) */
		/*
			for a game like arkanoid, would like mouse to still
			move even when outside window in one direction
		*/
		MyMousePositionSet(NewMousePosh, NewMousePosv);
	}

	WantCursorHidden = ShouldHaveCursorHidden;
}

LOCALPROC CheckMouseState(void)
{
	int NewMousePosh;
	int NewMousePosv;
	int root_x_return;
	int root_y_return;
	Window root_return;
	Window child_return;
	unsigned int mask_return;

	XQueryPointer(x_display, my_main_wind,
		&root_return, &child_return,
		&root_x_return, &root_y_return,
		&NewMousePosh, &NewMousePosv,
		&mask_return);
	MousePositionNotify(NewMousePosh, NewMousePosv);
}

/* --- keyboard input --- */

LOCALVAR KeyCode TheCapsLockCode;

LOCALVAR si3b KC2MKC[256];

LOCALPROC KC2MKCAssignOne(KeySym ks, int key)
{
	KeyCode code = XKeysymToKeycode(x_display, ks);
	if (code != NoSymbol) {
		KC2MKC[code] = key;
	}
#if 0
	fprintf(stderr, "%d %d %d\n", (int)ks, key, (int)code);
#endif
}

LOCALFUNC blnr KC2MKCInit(void)
{
	int i;

	for (i = 0; i < 256; ++i) {
		KC2MKC[i] = -1;
	}

#if 0 /* find Keysym for a code */
	for (i = 0; i < 64 * 1024; ++i) {
		KeyCode code = XKeysymToKeycode(x_display, i);
		if (115 == code) {
			fprintf(stderr, "i %d\n", i);
		}
	}
#endif

	/*
	start with redundant mappings, should get overwritten
	by main mappings but define them just in case
	*/

#ifdef XK_KP_Insert
	KC2MKCAssignOne(XK_KP_Insert, MKC_KP0);
#endif
#ifdef XK_KP_End
	KC2MKCAssignOne(XK_KP_End, MKC_KP1);
#endif
#ifdef XK_KP_Down
	KC2MKCAssignOne(XK_KP_Down, MKC_KP2);
#endif
#ifdef XK_KP_Next
	KC2MKCAssignOne(XK_KP_Next, MKC_KP3);
#endif
#ifdef XK_KP_Left
	KC2MKCAssignOne(XK_KP_Left, MKC_KP4);
#endif
#ifdef XK_KP_Begin
	KC2MKCAssignOne(XK_KP_Begin, MKC_KP5);
#endif
#ifdef XK_KP_Right
	KC2MKCAssignOne(XK_KP_Right, MKC_KP6);
#endif
#ifdef XK_KP_Home
	KC2MKCAssignOne(XK_KP_Home, MKC_KP7);
#endif
#ifdef XK_KP_Up
	KC2MKCAssignOne(XK_KP_Up, MKC_KP8);
#endif
#ifdef XK_KP_Prior
	KC2MKCAssignOne(XK_KP_Prior, MKC_KP9);
#endif
#ifdef XK_KP_Delete
	KC2MKCAssignOne(XK_KP_Delete, MKC_Decimal);
#endif

	KC2MKCAssignOne(XK_asciitilde, MKC_Grave);
	KC2MKCAssignOne(XK_underscore, MKC_Minus);
	KC2MKCAssignOne(XK_plus, MKC_Equal);
	KC2MKCAssignOne(XK_braceleft, MKC_LeftBracket);
	KC2MKCAssignOne(XK_braceright, MKC_RightBracket);
	KC2MKCAssignOne(XK_bar, MKC_BackSlash);
	KC2MKCAssignOne(XK_colon, MKC_SemiColon);
	KC2MKCAssignOne(XK_quotedbl, MKC_SingleQuote);
	KC2MKCAssignOne(XK_less, MKC_Comma);
	KC2MKCAssignOne(XK_greater, MKC_Period);
	KC2MKCAssignOne(XK_question, MKC_Slash);

	KC2MKCAssignOne(XK_a, MKC_A);
	KC2MKCAssignOne(XK_b, MKC_B);
	KC2MKCAssignOne(XK_c, MKC_C);
	KC2MKCAssignOne(XK_d, MKC_D);
	KC2MKCAssignOne(XK_e, MKC_E);
	KC2MKCAssignOne(XK_f, MKC_F);
	KC2MKCAssignOne(XK_g, MKC_G);
	KC2MKCAssignOne(XK_h, MKC_H);
	KC2MKCAssignOne(XK_i, MKC_I);
	KC2MKCAssignOne(XK_j, MKC_J);
	KC2MKCAssignOne(XK_k, MKC_K);
	KC2MKCAssignOne(XK_l, MKC_L);
	KC2MKCAssignOne(XK_m, MKC_M);
	KC2MKCAssignOne(XK_n, MKC_N);
	KC2MKCAssignOne(XK_o, MKC_O);
	KC2MKCAssignOne(XK_p, MKC_P);
	KC2MKCAssignOne(XK_q, MKC_Q);
	KC2MKCAssignOne(XK_r, MKC_R);
	KC2MKCAssignOne(XK_s, MKC_S);
	KC2MKCAssignOne(XK_t, MKC_T);
	KC2MKCAssignOne(XK_u, MKC_U);
	KC2MKCAssignOne(XK_v, MKC_V);
	KC2MKCAssignOne(XK_w, MKC_W);
	KC2MKCAssignOne(XK_x, MKC_X);
	KC2MKCAssignOne(XK_y, MKC_Y);
	KC2MKCAssignOne(XK_z, MKC_Z);

	/*
	main mappings
	*/

	KC2MKCAssignOne(XK_F1, MKC_F1);
	KC2MKCAssignOne(XK_F2, MKC_F2);
	KC2MKCAssignOne(XK_F3, MKC_F3);
	KC2MKCAssignOne(XK_F4, MKC_F4);
	KC2MKCAssignOne(XK_F5, MKC_F5);
	KC2MKCAssignOne(XK_F6, MKC_F6);
	KC2MKCAssignOne(XK_F7, MKC_F7);
	KC2MKCAssignOne(XK_F8, MKC_F8);
	KC2MKCAssignOne(XK_F9, MKC_F9);
	KC2MKCAssignOne(XK_F10, MKC_F10);
	KC2MKCAssignOne(XK_F11, MKC_F11);
	KC2MKCAssignOne(XK_F12, MKC_F12);

#ifdef XK_Delete
	KC2MKCAssignOne(XK_Delete, MKC_ForwardDel);
#endif
#ifdef XK_Insert
	KC2MKCAssignOne(XK_Insert, MKC_Help);
#endif
#ifdef XK_Help
	KC2MKCAssignOne(XK_Help, MKC_Help);
#endif
#ifdef XK_Home
	KC2MKCAssignOne(XK_Home, MKC_Home);
#endif
#ifdef XK_End
	KC2MKCAssignOne(XK_End, MKC_End);
#endif

#ifdef XK_Page_Up
	KC2MKCAssignOne(XK_Page_Up, MKC_PageUp);
#else
#ifdef XK_Prior
	KC2MKCAssignOne(XK_Prior, MKC_PageUp);
#endif
#endif

#ifdef XK_Page_Down
	KC2MKCAssignOne(XK_Page_Down, MKC_PageDown);
#else
#ifdef XK_Next
	KC2MKCAssignOne(XK_Next, MKC_PageDown);
#endif
#endif

#ifdef XK_Print
	KC2MKCAssignOne(XK_Print, MKC_Print);
#endif
#ifdef XK_Scroll_Lock
	KC2MKCAssignOne(XK_Scroll_Lock, MKC_ScrollLock);
#endif
#ifdef XK_Pause
	KC2MKCAssignOne(XK_Pause, MKC_Pause);
#endif

	KC2MKCAssignOne(XK_KP_Add, MKC_KPAdd);
	KC2MKCAssignOne(XK_KP_Subtract, MKC_KPSubtract);
	KC2MKCAssignOne(XK_KP_Multiply, MKC_KPMultiply);
	KC2MKCAssignOne(XK_KP_Divide, MKC_KPDevide);
	KC2MKCAssignOne(XK_KP_Enter, MKC_Enter);
	KC2MKCAssignOne(XK_KP_Equal, MKC_KPEqual);

	KC2MKCAssignOne(XK_KP_0, MKC_KP0);
	KC2MKCAssignOne(XK_KP_1, MKC_KP1);
	KC2MKCAssignOne(XK_KP_2, MKC_KP2);
	KC2MKCAssignOne(XK_KP_3, MKC_KP3);
	KC2MKCAssignOne(XK_KP_4, MKC_KP4);
	KC2MKCAssignOne(XK_KP_5, MKC_KP5);
	KC2MKCAssignOne(XK_KP_6, MKC_KP6);
	KC2MKCAssignOne(XK_KP_7, MKC_KP7);
	KC2MKCAssignOne(XK_KP_8, MKC_KP8);
	KC2MKCAssignOne(XK_KP_9, MKC_KP9);
	KC2MKCAssignOne(XK_KP_Decimal, MKC_Decimal);

	KC2MKCAssignOne(XK_Left, MKC_Left);
	KC2MKCAssignOne(XK_Right, MKC_Right);
	KC2MKCAssignOne(XK_Up, MKC_Up);
	KC2MKCAssignOne(XK_Down, MKC_Down);

	KC2MKCAssignOne(XK_grave, MKC_Grave);
	KC2MKCAssignOne(XK_minus, MKC_Minus);
	KC2MKCAssignOne(XK_equal, MKC_Equal);
	KC2MKCAssignOne(XK_bracketleft, MKC_LeftBracket);
	KC2MKCAssignOne(XK_bracketright, MKC_RightBracket);
	KC2MKCAssignOne(XK_backslash, MKC_BackSlash);
	KC2MKCAssignOne(XK_semicolon, MKC_SemiColon);
	KC2MKCAssignOne(XK_apostrophe, MKC_SingleQuote);
	KC2MKCAssignOne(XK_comma, MKC_Comma);
	KC2MKCAssignOne(XK_period, MKC_Period);
	KC2MKCAssignOne(XK_slash, MKC_Slash);

	KC2MKCAssignOne(XK_Escape, MKC_Escape);

	KC2MKCAssignOne(XK_Tab, MKC_Tab);
	KC2MKCAssignOne(XK_Return, MKC_Return);
	KC2MKCAssignOne(XK_space, MKC_Space);
	KC2MKCAssignOne(XK_BackSpace, MKC_BackSpace);

	KC2MKCAssignOne(XK_Caps_Lock, MKC_CapsLock);
	KC2MKCAssignOne(XK_Num_Lock, MKC_Clear);

#ifndef MKC_for_Meta
#define MKC_for_Meta MKC_Command
#endif

#ifndef MKC_for_Meta_L
#define MKC_for_Meta_L MKC_for_Meta
#endif
	KC2MKCAssignOne(XK_Meta_L, MKC_for_Meta_L);

#ifndef MKC_for_Meta_R
#define MKC_for_Meta_R MKC_for_Meta
#endif
	KC2MKCAssignOne(XK_Meta_R, MKC_for_Meta_R);

	KC2MKCAssignOne(XK_Mode_switch, MKC_Option);
	KC2MKCAssignOne(XK_Menu, MKC_Option);
	KC2MKCAssignOne(XK_Super_L, MKC_Option);
	KC2MKCAssignOne(XK_Super_R, MKC_Option);
	KC2MKCAssignOne(XK_Hyper_L, MKC_Option);
	KC2MKCAssignOne(XK_Hyper_R, MKC_Option);

	KC2MKCAssignOne(XK_F13, MKC_Option);
		/*
			seen being used in Mandrake Linux 9.2
			for windows key
		*/

	KC2MKCAssignOne(XK_Shift_L, MKC_Shift);
	KC2MKCAssignOne(XK_Shift_R, MKC_Shift);

#ifndef MKC_for_Alt
#define MKC_for_Alt MKC_Command
#endif

#ifndef MKC_for_Alt_L
#define MKC_for_Alt_L MKC_for_Alt
#endif
	KC2MKCAssignOne(XK_Alt_L, MKC_for_Alt_L);

#ifndef MKC_for_Alt_R
#define MKC_for_Alt_R MKC_for_Alt
#endif
	KC2MKCAssignOne(XK_Alt_R, MKC_for_Alt_R);

#ifndef MKC_for_Control
#define MKC_for_Control MKC_Control
#endif

#ifndef MKC_for_Control_L
#define MKC_for_Control_L MKC_for_Control
#endif
	KC2MKCAssignOne(XK_Control_L, MKC_for_Control_L);

#ifndef MKC_for_Control_R
#define MKC_for_Control_R MKC_for_Control
#endif
	KC2MKCAssignOne(XK_Control_R, MKC_for_Control_R);

	KC2MKCAssignOne(XK_1, MKC_1);
	KC2MKCAssignOne(XK_2, MKC_2);
	KC2MKCAssignOne(XK_3, MKC_3);
	KC2MKCAssignOne(XK_4, MKC_4);
	KC2MKCAssignOne(XK_5, MKC_5);
	KC2MKCAssignOne(XK_6, MKC_6);
	KC2MKCAssignOne(XK_7, MKC_7);
	KC2MKCAssignOne(XK_8, MKC_8);
	KC2MKCAssignOne(XK_9, MKC_9);
	KC2MKCAssignOne(XK_0, MKC_0);

	KC2MKCAssignOne(XK_A, MKC_A);
	KC2MKCAssignOne(XK_B, MKC_B);
	KC2MKCAssignOne(XK_C, MKC_C);
	KC2MKCAssignOne(XK_D, MKC_D);
	KC2MKCAssignOne(XK_E, MKC_E);
	KC2MKCAssignOne(XK_F, MKC_F);
	KC2MKCAssignOne(XK_G, MKC_G);
	KC2MKCAssignOne(XK_H, MKC_H);
	KC2MKCAssignOne(XK_I, MKC_I);
	KC2MKCAssignOne(XK_J, MKC_J);
	KC2MKCAssignOne(XK_K, MKC_K);
	KC2MKCAssignOne(XK_L, MKC_L);
	KC2MKCAssignOne(XK_M, MKC_M);
	KC2MKCAssignOne(XK_N, MKC_N);
	KC2MKCAssignOne(XK_O, MKC_O);
	KC2MKCAssignOne(XK_P, MKC_P);
	KC2MKCAssignOne(XK_Q, MKC_Q);
	KC2MKCAssignOne(XK_R, MKC_R);
	KC2MKCAssignOne(XK_S, MKC_S);
	KC2MKCAssignOne(XK_T, MKC_T);
	KC2MKCAssignOne(XK_U, MKC_U);
	KC2MKCAssignOne(XK_V, MKC_V);
	KC2MKCAssignOne(XK_W, MKC_W);
	KC2MKCAssignOne(XK_X, MKC_X);
	KC2MKCAssignOne(XK_Y, MKC_Y);
	KC2MKCAssignOne(XK_Z, MKC_Z);

	TheCapsLockCode = XKeysymToKeycode(x_display, XK_Caps_Lock);

	InitKeyCodes();

	return trueblnr;
}

LOCALPROC CheckTheCapsLock(void)
{
	int NewMousePosh;
	int NewMousePosv;
	int root_x_return;
	int root_y_return;
	Window root_return;
	Window child_return;
	unsigned int mask_return;

	XQueryPointer(x_display, my_main_wind,
		&root_return, &child_return,
		&root_x_return, &root_y_return,
		&NewMousePosh, &NewMousePosv,
		&mask_return);

	Keyboard_UpdateKeyMap2(MKC_CapsLock, (mask_return & LockMask) != 0);
}

LOCALPROC DoKeyCode0(int i, blnr down)
{
	int key = KC2MKC[i];
	if (key >= 0) {
		Keyboard_UpdateKeyMap2(key, down);
	}
}

LOCALPROC DoKeyCode(int i, blnr down)
{
	if (i == TheCapsLockCode) {
		CheckTheCapsLock();
	} else if (i >= 0 && i < 256) {
		DoKeyCode0(i, down);
	}
}

#if MayFullScreen
LOCALVAR blnr KeyboardIsGrabbed = falseblnr;
#endif

#if MayFullScreen
LOCALPROC MyGrabKeyboard(void)
{
	if (! KeyboardIsGrabbed) {
		(void) XGrabKeyboard(x_display, my_main_wind,
			False, GrabModeAsync, GrabModeAsync,
			CurrentTime);
		KeyboardIsGrabbed = trueblnr;
	}
}
#endif

#if MayFullScreen
LOCALPROC MyUnGrabKeyboard(void)
{
	if (KeyboardIsGrabbed && my_main_wind) {
		XUngrabKeyboard(x_display, CurrentTime);
		KeyboardIsGrabbed = falseblnr;
	}
}
#endif

LOCALVAR blnr NoKeyRepeat = falseblnr;
LOCALVAR int SaveKeyRepeat;

LOCALPROC DisableKeyRepeat(void)
{
	XKeyboardState r;
	XKeyboardControl k;

	if ((! NoKeyRepeat) && (x_display != NULL)) {
		NoKeyRepeat = trueblnr;

		XGetKeyboardControl(x_display, &r);
		SaveKeyRepeat = r.global_auto_repeat;

		k.auto_repeat_mode = AutoRepeatModeOff;
		XChangeKeyboardControl(x_display, KBAutoRepeatMode, &k);
	}
}

LOCALPROC RestoreKeyRepeat(void)
{
	XKeyboardControl k;

	if (NoKeyRepeat && (x_display != NULL)) {
		NoKeyRepeat = falseblnr;

		k.auto_repeat_mode = SaveKeyRepeat;
		XChangeKeyboardControl(x_display, KBAutoRepeatMode, &k);
	}
}

LOCALVAR blnr WantCmdOptOnReconnect = falseblnr;

LOCALPROC GetTheDownKeys(void)
{
	char keys_return[32];
	int i;
	int v;
	int j;

	XQueryKeymap(x_display, keys_return);

	for (i = 0; i < 32; ++i) {
		v = keys_return[i];
		for (j = 0; j < 8; ++j) {
			if (0 != ((1 << j) & v)) {
				int k = i * 8 + j;
				if (k != TheCapsLockCode) {
					DoKeyCode0(k, trueblnr);
				}
			}
		}
	}
}

LOCALPROC ReconnectKeyCodes3(void)
{
	CheckTheCapsLock();

	if (WantCmdOptOnReconnect) {
		WantCmdOptOnReconnect = falseblnr;

		GetTheDownKeys();
	}
}

LOCALPROC DisconnectKeyCodes3(void)
{
	DisconnectKeyCodes2();
	MyMouseButtonSet(falseblnr);
}

/* --- time, date, location --- */

LOCALVAR ui5b TrueEmulatedTime = 0;
LOCALVAR ui5b CurEmulatedTime = 0;

#include "DATE2SEC.h"

#define TicksPerSecond 1000000

LOCALVAR blnr HaveTimeDelta = falseblnr;
LOCALVAR ui5b TimeDelta;

LOCALVAR ui5b NewMacDateInSeconds;

LOCALVAR ui5b LastTimeSec;
LOCALVAR ui5b LastTimeUsec;

LOCALPROC GetCurrentTicks(void)
{
	struct timeval t;

	gettimeofday(&t, NULL);
	if (! HaveTimeDelta) {
		time_t Current_Time;
		struct tm *s;

		(void) time(&Current_Time);
		s = localtime(&Current_Time);
		TimeDelta = Date2MacSeconds(s->tm_sec, s->tm_min, s->tm_hour,
			s->tm_mday, 1 + s->tm_mon, 1900 + s->tm_year) - t.tv_sec;
#if 0 /* how portable is this ? */
		CurMacDelta = ((ui5b)(s->tm_gmtoff) & 0x00FFFFFF)
			| ((s->tm_isdst ? 0x80 : 0) << 24);
#endif
		HaveTimeDelta = trueblnr;
	}

	NewMacDateInSeconds = t.tv_sec + TimeDelta;
	LastTimeSec = (ui5b)t.tv_sec;
	LastTimeUsec = (ui5b)t.tv_usec;
}

#define MyInvTimeStep 16626 /* TicksPerSecond / 60.14742 */

LOCALVAR ui5b NextTimeSec;
LOCALVAR ui5b NextTimeUsec;

LOCALPROC IncrNextTime(void)
{
	NextTimeUsec += MyInvTimeStep;
	if (NextTimeUsec >= TicksPerSecond) {
		NextTimeUsec -= TicksPerSecond;
		NextTimeSec += 1;
	}
}

LOCALPROC InitNextTime(void)
{
	NextTimeSec = LastTimeSec;
	NextTimeUsec = LastTimeUsec;
	IncrNextTime();
}

LOCALPROC StartUpTimeAdjust(void)
{
	GetCurrentTicks();
	InitNextTime();
}

LOCALFUNC si5b GetTimeDiff(void)
{
	return ((si5b)(LastTimeSec - NextTimeSec)) * TicksPerSecond
		+ ((si5b)(LastTimeUsec - NextTimeUsec));
}

LOCALPROC UpdateTrueEmulatedTime(void)
{
	si5b TimeDiff;

	GetCurrentTicks();

	TimeDiff = GetTimeDiff();
	if (TimeDiff >= 0) {
		if (TimeDiff > 4 * MyInvTimeStep) {
			/* emulation interrupted, forget it */
			++TrueEmulatedTime;
			InitNextTime();
		} else {
			do {
				++TrueEmulatedTime;
				IncrNextTime();
				TimeDiff -= TicksPerSecond;
			} while (TimeDiff >= 0);
		}
	} else if (TimeDiff < - 2 * MyInvTimeStep) {
		/* clock goofed if ever get here, reset */
		InitNextTime();
	}
}

LOCALFUNC blnr CheckDateTime(void)
{
	if (CurMacDateInSeconds != NewMacDateInSeconds) {
		CurMacDateInSeconds = NewMacDateInSeconds;
		return trueblnr;
	} else {
		return falseblnr;
	}
}

LOCALFUNC blnr InitLocationDat(void)
{
	GetCurrentTicks();
	CurMacDateInSeconds = NewMacDateInSeconds;

	return trueblnr;
}

/* --- sound --- */

#if MySoundEnabled

#define kLn2SoundBuffers 4 /* kSoundBuffers must be a power of two */
#define kSoundBuffers (1 << kLn2SoundBuffers)
#define kSoundBuffMask (kSoundBuffers - 1)

#define DesiredMinFilledSoundBuffs 3
	/*
		if too big then sound lags behind emulation.
		if too small then sound will have pauses.
	*/

#define kLnOneBuffLen 9
#define kLnAllBuffLen (kLn2SoundBuffers + kLnOneBuffLen)
#define kOneBuffLen (1UL << kLnOneBuffLen)
#define kAllBuffLen (1UL << kLnAllBuffLen)
#define kLnOneBuffSz (kLnOneBuffLen + kLn2SoundSampSz - 3)
#define kLnAllBuffSz (kLnAllBuffLen + kLn2SoundSampSz - 3)
#define kOneBuffSz (1UL << kLnOneBuffSz)
#define kAllBuffSz (1UL << kLnAllBuffSz)
#define kOneBuffMask (kOneBuffLen - 1)
#define kAllBuffMask (kAllBuffLen - 1)
#define dbhBufferSize (kAllBuffSz + kOneBuffSz)

LOCALVAR tpSoundSamp TheSoundBuffer = nullpr;
LOCALVAR ui4b ThePlayOffset;
LOCALVAR ui4b TheFillOffset;
LOCALVAR ui4b TheWriteOffset;
LOCALVAR ui4b MinFilledSoundBuffs;

LOCALPROC MySound_Start0(void)
{
	/* Reset variables */
	ThePlayOffset = 0;
	TheFillOffset = 0;
	TheWriteOffset = 0;
	MinFilledSoundBuffs = kSoundBuffers;
}

GLOBALFUNC tpSoundSamp MySound_BeginWrite(ui4r n, ui4r *actL)
{
	ui4b ToFillLen = kAllBuffLen - (TheWriteOffset - ThePlayOffset);
	ui4b WriteBuffContig =
		kOneBuffLen - (TheWriteOffset & kOneBuffMask);

	if (WriteBuffContig < n) {
		n = WriteBuffContig;
	}
	if (ToFillLen < n) {
		/* overwrite previous buffer */
		TheWriteOffset -= kOneBuffLen;
	}

	*actL = n;
	return TheSoundBuffer + (TheWriteOffset & kAllBuffMask);
}

LOCALFUNC blnr MySound_EndWrite0(ui4r actL)
{
	blnr v;

	TheWriteOffset += actL;

	if (0 != (TheWriteOffset & kOneBuffMask)) {
		v = falseblnr;
	} else {
		/* just finished a block */

		TheFillOffset = TheWriteOffset;

		v = trueblnr;
	}

	return v;
}

LOCALPROC MySound_SecondNotify0(void)
{
	if (MinFilledSoundBuffs > DesiredMinFilledSoundBuffs) {
		++CurEmulatedTime;
	} else if (MinFilledSoundBuffs < DesiredMinFilledSoundBuffs) {
		--CurEmulatedTime;
	}
	MinFilledSoundBuffs = kSoundBuffers;
}

#define SOUND_SAMPLERATE 22255 /* = round(7833600 * 2 / 704) */

#include "SOUNDGLU.h"

#endif

/* --- basic dialogs --- */

LOCALPROC CheckSavedMacMsg(void)
{
	/* called only on quit, if error saved but not yet reported */

	if (nullpr != SavedBriefMsg) {
		char briefMsg0[ClStrMaxLength + 1];
		char longMsg0[ClStrMaxLength + 1];

		NativeStrFromCStr(briefMsg0, SavedBriefMsg);
		NativeStrFromCStr(longMsg0, SavedLongMsg);

		fprintf(stderr, "%s\n", briefMsg0);
		fprintf(stderr, "%s\n", longMsg0);

		SavedBriefMsg = nullpr;
	}
}

/* --- clipboard --- */

#if IncludeHostTextClipExchange
LOCALVAR ui3p MyClipBuffer = NULL;
#endif

#if IncludeHostTextClipExchange
LOCALPROC FreeMyClipBuffer(void)
{
	if (MyClipBuffer != NULL) {
		free(MyClipBuffer);
		MyClipBuffer = NULL;
	}
}
#endif

#if IncludeHostTextClipExchange
GLOBALFUNC tMacErr HTCEexport(tPbuf i)
{
	tMacErr err = mnvm_miscErr;

	FreeMyClipBuffer();
	if (MacRomanTextToNativePtr(i, falseblnr,
		&MyClipBuffer))
	{
		XSetSelectionOwner(x_display, MyXA_CLIPBOARD,
			my_main_wind, CurrentTime);
		err = mnvm_noErr;
	}

	PbufDispose(i);

	return err;
}
#endif

#if IncludeHostTextClipExchange
LOCALFUNC blnr WaitForClipboardSelection(XEvent *xevent)
{
	struct timespec rqt;
	struct timespec rmt;
	int i;

	for (i = 100; --i >= 0; ) {
		while (XCheckTypedWindowEvent(x_display, my_main_wind,
			SelectionNotify, xevent))
		{
			if (xevent->xselection.selection != MyXA_CLIPBOARD) {
				/*
					not what we were looking for. lose it.
					(and hope it wasn't too important).
				*/
				WriteExtraErr("Discarding unwanted SelectionNotify");
			} else {
				/* this is our event */
				return trueblnr;
			}
		}

		rqt.tv_sec = 0;
		rqt.tv_nsec = 10000000;
		(void) nanosleep(&rqt, &rmt);
	}
	return falseblnr;
}
#endif

#if IncludeHostTextClipExchange
LOCALPROC HTCEimport_do(void)
{
	Window w = XGetSelectionOwner(x_display, MyXA_CLIPBOARD);

	if (w == my_main_wind) {
		/* We own the clipboard, already have MyClipBuffer */
	} else {
		FreeMyClipBuffer();
		if (w != None) {
			XEvent xevent;

			XDeleteProperty(x_display, my_main_wind,
				MyXA_MinivMac_Clip);
			XConvertSelection(x_display, MyXA_CLIPBOARD, XA_STRING,
				MyXA_MinivMac_Clip, my_main_wind, CurrentTime);

			if (WaitForClipboardSelection(&xevent)) {
				if (None == xevent.xselection.property) {
					/* oops, target not supported */
				} else {
					if (xevent.xselection.property
						!= MyXA_MinivMac_Clip)
					{
						/* not where we expected it */
					} else {
						Atom ret_type;
						int ret_format;
						unsigned long ret_item;
						unsigned long remain_byte;
						unsigned char *s = NULL;

						if ((Success != XGetWindowProperty(
							x_display, my_main_wind, MyXA_MinivMac_Clip,
							0, 65535, False, AnyPropertyType, &ret_type,
							&ret_format, &ret_item, &remain_byte, &s))
							|| (ret_type != XA_STRING)
							|| (ret_format != 8)
							|| (NULL == s))
						{
							WriteExtraErr(
								"XGetWindowProperty failed"
								" in HTCEimport_do");
						} else {
							MyClipBuffer = (ui3p)malloc(ret_item + 1);
							if (NULL == MyClipBuffer) {
								MacMsg(kStrOutOfMemTitle,
									kStrOutOfMemMessage, falseblnr);
							} else {
								MyMoveBytes((anyp)s, (anyp)MyClipBuffer,
									ret_item);
								MyClipBuffer[ret_item] = 0;
							}
							XFree(s);
						}
					}
					XDeleteProperty(x_display, my_main_wind,
						MyXA_MinivMac_Clip);
				}
			}
		}
	}
}
#endif

#if IncludeHostTextClipExchange
GLOBALFUNC tMacErr HTCEimport(tPbuf *r)
{
	HTCEimport_do();

	return NativeTextToMacRomanPbuf((char *)MyClipBuffer, r);
}
#endif

#if IncludeHostTextClipExchange
LOCALFUNC blnr HandleSelectionRequestClipboard(XEvent *theEvent)
{
	blnr RequestFilled = falseblnr;

#if MyDbgEvents
	dbglog_writeln("Requested MyXA_CLIPBOARD");
#endif

	if (NULL == MyClipBuffer) {
		/* our clipboard is empty */
	} else if (theEvent->xselectionrequest.target == MyXA_TARGETS) {
		Atom a[2];

		a[0] = MyXA_TARGETS;
		a[1] = XA_STRING;

		XChangeProperty(x_display,
			theEvent->xselectionrequest.requestor,
			theEvent->xselectionrequest.property,
			MyXA_TARGETS,
			32,
				/*
					most, but not all, other programs I've
					look at seem to use 8 here, but that
					can't be right. can it?
				*/
			PropModeReplace,
			(unsigned char *)a,
			sizeof(a) / sizeof(Atom));

		RequestFilled = trueblnr;
	} else if (theEvent->xselectionrequest.target == XA_STRING) {
		XChangeProperty(x_display,
			theEvent->xselectionrequest.requestor,
			theEvent->xselectionrequest.property,
			XA_STRING,
			8,
			PropModeReplace,
			(unsigned char *)MyClipBuffer,
			strlen((char *)MyClipBuffer));

		RequestFilled = trueblnr;
	}

	return RequestFilled;
}
#endif

/* --- drag and drop --- */

#if EnableDragDrop
LOCALPROC MyActivateWind(Time time)
{
	if (NetSupportedContains(MyXA_NetActiveWindow)) {
		XEvent xevent;
		Window rootwin = XRootWindow(x_display,
			DefaultScreen(x_display));

		memset(&xevent, 0, sizeof (xevent));

		xevent.xany.type = ClientMessage;
		xevent.xclient.send_event = True;
		xevent.xclient.window = my_main_wind;
		xevent.xclient.message_type = MyXA_NetActiveWindow;
		xevent.xclient.format = 32;
		xevent.xclient.data.l[0] = 1;
		xevent.xclient.data.l[1]= time;

		if (0 == XSendEvent(x_display, rootwin, 0,
			SubstructureRedirectMask | SubstructureNotifyMask,
			&xevent))
		{
			WriteExtraErr("XSendEvent failed in MyActivateWind");
		}
	}

	XRaiseWindow(x_display, my_main_wind);
		/*
			In RedHat 7.1, _NET_ACTIVE_WINDOW supported,
			but XSendEvent of _NET_ACTIVE_WINDOW
			doesn't raise the window. So just always
			call XRaiseWindow. Hopefully calling
			XRaiseWindow won't do any harm on window
			managers where it isn't needed.
			(Such as in Ubuntu 5.10)
		*/
	XSetInputFocus(x_display, my_main_wind,
		RevertToPointerRoot, time);
		/* And call this always too, just in case */
}
#endif

#if EnableDragDrop
LOCALPROC ParseOneUri(char *s)
{
	/* printf("ParseOneUri %s\n", s); */
	if (('f' == s[0]) && ('i' == s[1]) && ('l' == s[2])
		&& ('e' == s[3]) && (':' == s[4]))
	{
		s += 5;
		if (('/' == s[0]) && ('/' == s[1])) {
			/* skip hostname */
			char c;

			s += 2;
			while ((c = *s) != '/') {
				if (0 == c) {
					return;
				}
				++s;
			}
		}
		(void) Sony_Insert1(s, falseblnr);
	}
}
#endif

#if EnableDragDrop
LOCALFUNC int HexChar2Nib(char x)
{
	if ((x >= '0') && (x <= '9')) {
		return x - '0';
	} else if ((x >= 'A') && (x <= 'F')) {
		return x - 'A' + 10;
	} else if ((x >= 'a') && (x <= 'f')) {
		return x - 'a' + 10;
	} else {
		return -1;
	}
}
#endif

#if EnableDragDrop
LOCALPROC ParseUriList(char *s)
{
	char *p1 = s;
	char *p0 = s;
	char *p = s;
	char c;

	/* printf("ParseUriList %s\n", s); */
	while ((c = *p++) != 0) {
		if ('%' == c) {
			int a;
			int b;

			if (((a = HexChar2Nib(p[0])) >= 0) &&
				((b = HexChar2Nib(p[1])) >= 0))
			{
				p += 2;
				*p1++ = (a << 4) + b;
			} else {
				*p1++ = c;
			}
		} else if (('\n' == c) || ('\r' == c)) {
			*p1++ = 0;
			ParseOneUri(p0);
			p0 = p1;
		} else {
			*p1++ = c;
		}
	}
	*p1++ = 0;
	ParseOneUri(p0);
}
#endif

#if EnableDragDrop
LOCALVAR Window PendingDragWindow = None;
#endif

#if EnableDragDrop
LOCALPROC HandleSelectionNotifyDnd(XEvent *theEvent)
{
	blnr DropOk = falseblnr;

#if MyDbgEvents
	dbglog_writeln("Got MyXA_DndSelection");
#endif

	if ((theEvent->xselection.property == MyXA_MinivMac_DndXchng)
		&& (theEvent->xselection.target == MyXA_UriList))
	{
		Atom ret_type;
		int ret_format;
		unsigned long ret_item;
		unsigned long remain_byte;
		unsigned char *s = NULL;

		if ((Success != XGetWindowProperty(x_display, my_main_wind,
			MyXA_MinivMac_DndXchng,
			0, 65535, False, MyXA_UriList, &ret_type, &ret_format,
			&ret_item, &remain_byte, &s))
			|| (NULL == s))
		{
			WriteExtraErr(
				"XGetWindowProperty failed in SelectionNotify");
		} else {
			ParseUriList((char *)s);
			DropOk = trueblnr;
			XFree(s);
		}
	} else {
		WriteExtraErr("Got Unknown SelectionNotify");
	}

	XDeleteProperty(x_display, my_main_wind,
		MyXA_MinivMac_DndXchng);

	if (PendingDragWindow != None) {
		XEvent xevent;

		memset(&xevent, 0, sizeof(xevent));

		xevent.xany.type = ClientMessage;
		xevent.xany.display = x_display;
		xevent.xclient.window = PendingDragWindow;
		xevent.xclient.message_type = MyXA_DndFinished;
		xevent.xclient.format = 32;

		xevent.xclient.data.l[0] = my_main_wind;
		if (DropOk) {
			xevent.xclient.data.l[1] = 1;
		}
		xevent.xclient.data.l[2] = MyXA_DndActionPrivate;

		if (0 == XSendEvent(x_display,
			PendingDragWindow, 0, 0, &xevent))
		{
			WriteExtraErr("XSendEvent failed in SelectionNotify");
		}
	}
	if (DropOk && gTrueBackgroundFlag) {
		MyActivateWind(theEvent->xselection.time);

		WantCmdOptOnReconnect = trueblnr;
	}
}
#endif

#if EnableDragDrop
LOCALPROC HandleClientMessageDndPosition(XEvent *theEvent)
{
	XEvent xevent;
	int xr;
	int yr;
	unsigned int dr;
	unsigned int wr;
	unsigned int hr;
	unsigned int bwr;
	Window rr;
	Window srcwin = theEvent->xclient.data.l[0];

#if MyDbgEvents
	dbglog_writeln("Got XdndPosition");
#endif

	XGetGeometry(x_display, my_main_wind,
		&rr, &xr, &yr, &wr, &hr, &bwr, &dr);
	memset (&xevent, 0, sizeof(xevent));
	xevent.xany.type = ClientMessage;
	xevent.xany.display = x_display;
	xevent.xclient.window = srcwin;
	xevent.xclient.message_type = MyXA_DndStatus;
	xevent.xclient.format = 32;

	xevent.xclient.data.l[0] = theEvent->xclient.window;
		/* Target Window */
	xevent.xclient.data.l[1] = 1; /* Accept */
	xevent.xclient.data.l[2] = ((xr) << 16) | ((yr) & 0xFFFFUL);
	xevent.xclient.data.l[3] = ((wr) << 16) | ((hr) & 0xFFFFUL);
	xevent.xclient.data.l[4] = MyXA_DndActionPrivate; /* Action */

	if (0 == XSendEvent(x_display, srcwin, 0, 0, &xevent)) {
		WriteExtraErr(
			"XSendEvent failed in HandleClientMessageDndPosition");
	}
}
#endif

#if EnableDragDrop
LOCALPROC HandleClientMessageDndDrop(XEvent *theEvent)
{
	Time timestamp = theEvent->xclient.data.l[2];
	PendingDragWindow = (Window) theEvent->xclient.data.l[0];

#if MyDbgEvents
	dbglog_writeln("Got XdndDrop");
#endif

	XConvertSelection(x_display, MyXA_DndSelection, MyXA_UriList,
		MyXA_MinivMac_DndXchng, my_main_wind, timestamp);
}
#endif

#define UseMotionEvents 1

#if UseMotionEvents
LOCALVAR blnr CaughtMouse = falseblnr;
#endif

#if MayNotFullScreen
LOCALVAR int SavedTransH;
LOCALVAR int SavedTransV;
#endif

/* --- event handling for main window --- */

LOCALPROC HandleTheEvent(XEvent *theEvent)
{
	if (theEvent->xany.display != x_display) {
		WriteExtraErr("Got event for some other display");
	} else switch(theEvent->type) {
		case KeyPress:
			if (theEvent->xkey.window != my_main_wind) {
				WriteExtraErr("Got KeyPress for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - KeyPress");
#endif

				MousePositionNotify(theEvent->xkey.x, theEvent->xkey.y);
				DoKeyCode(theEvent->xkey.keycode, trueblnr);
			}
			break;
		case KeyRelease:
			if (theEvent->xkey.window != my_main_wind) {
				WriteExtraErr("Got KeyRelease for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - KeyRelease");
#endif

				MousePositionNotify(theEvent->xkey.x, theEvent->xkey.y);
				DoKeyCode(theEvent->xkey.keycode, falseblnr);
			}
			break;
		case ButtonPress:
			/* any mouse button, we don't care which */
			if (theEvent->xbutton.window != my_main_wind) {
				WriteExtraErr("Got ButtonPress for some other window");
			} else {
				/*
					could check some modifiers, but don't bother for now
					Keyboard_UpdateKeyMap2(MKC_CapsLock,
						(theEvent->xbutton.state & LockMask) != 0);
				*/
				MousePositionNotify(
					theEvent->xbutton.x, theEvent->xbutton.y);
				MyMouseButtonSet(trueblnr);
			}
			break;
		case ButtonRelease:
			/* any mouse button, we don't care which */
			if (theEvent->xbutton.window != my_main_wind) {
				WriteExtraErr(
					"Got ButtonRelease for some other window");
			} else {
				MousePositionNotify(
					theEvent->xbutton.x, theEvent->xbutton.y);
				MyMouseButtonSet(falseblnr);
			}
			break;
#if UseMotionEvents
		case MotionNotify:
			if (theEvent->xmotion.window != my_main_wind) {
				WriteExtraErr("Got MotionNotify for some other window");
			} else {
				MousePositionNotify(
					theEvent->xmotion.x, theEvent->xmotion.y);
			}
			break;
		case EnterNotify:
			if (theEvent->xcrossing.window != my_main_wind) {
				WriteExtraErr("Got EnterNotify for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - EnterNotify");
#endif

				CaughtMouse = trueblnr;
				MousePositionNotify(
					theEvent->xcrossing.x, theEvent->xcrossing.y);
			}
			break;
		case LeaveNotify:
			if (theEvent->xcrossing.window != my_main_wind) {
				WriteExtraErr("Got LeaveNotify for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - LeaveNotify");
#endif

				MousePositionNotify(
					theEvent->xcrossing.x, theEvent->xcrossing.y);
				CaughtMouse = falseblnr;
			}
			break;
#endif
		case Expose:
			if (theEvent->xexpose.window != my_main_wind) {
				WriteExtraErr(
					"Got SelectionRequest for some other window");
			} else {
				int x0 = theEvent->xexpose.x;
				int y0 = theEvent->xexpose.y;
				int x1 = x0 + theEvent->xexpose.width;
				int y1 = y0 + theEvent->xexpose.height;

#if 0 && MyDbgEvents
				dbglog_writeln("- event - Expose");
#endif

#if VarFullScreen
				if (UseFullScreen)
#endif
#if MayFullScreen
				{
					x0 -= hOffset;
					y0 -= vOffset;
					x1 -= hOffset;
					y1 -= vOffset;
				}
#endif

#if EnableMagnify
				if (UseMagnify) {
					x0 /= MyWindowScale;
					y0 /= MyWindowScale;
					x1 = (x1 + (MyWindowScale - 1)) / MyWindowScale;
					y1 = (y1 + (MyWindowScale - 1)) / MyWindowScale;
				}
#endif

#if VarFullScreen
				if (UseFullScreen)
#endif
#if MayFullScreen
				{
					x0 += ViewHStart;
					y0 += ViewVStart;
					x1 += ViewHStart;
					y1 += ViewVStart;
				}
#endif

				if (x0 < 0) {
					x0 = 0;
				}
				if (x1 > vMacScreenWidth) {
					x1 = vMacScreenWidth;
				}
				if (y0 < 0) {
					y0 = 0;
				}
				if (y1 > vMacScreenHeight) {
					y1 = vMacScreenHeight;
				}
				if ((x0 < x1) && (y0 < y1)) {
					HaveChangedScreenBuff(y0, x0, y1, x1);
				}

				NeedFinishOpen1 = falseblnr;
			}
			break;
#if IncludeHostTextClipExchange
		case SelectionRequest:
			if (theEvent->xselectionrequest.owner != my_main_wind) {
				WriteExtraErr(
					"Got SelectionRequest for some other window");
			} else {
				XEvent xevent;
				blnr RequestFilled = falseblnr;

#if MyDbgEvents
				dbglog_writeln("- event - SelectionRequest");
				WriteDbgAtom("selection",
					theEvent->xselectionrequest.selection);
				WriteDbgAtom("target",
					theEvent->xselectionrequest.target);
				WriteDbgAtom("property",
					theEvent->xselectionrequest.property);
#endif

				if (theEvent->xselectionrequest.selection ==
					MyXA_CLIPBOARD)
				{
					RequestFilled =
						HandleSelectionRequestClipboard(theEvent);
				}


				memset(&xevent, 0, sizeof(xevent));
				xevent.xselection.type = SelectionNotify;
				xevent.xselection.display = x_display;
				xevent.xselection.requestor =
					theEvent->xselectionrequest.requestor;
				xevent.xselection.selection =
					theEvent->xselectionrequest.selection;
				xevent.xselection.target =
					theEvent->xselectionrequest.target;
				xevent.xselection.property = (! RequestFilled) ? None
					: theEvent->xselectionrequest.property ;
				xevent.xselection.time =
					theEvent->xselectionrequest.time;

				if (0 == XSendEvent(x_display,
					xevent.xselection.requestor, False, 0, &xevent))
				{
					WriteExtraErr(
						"XSendEvent failed in SelectionRequest");
				}
			}
			break;
		case SelectionClear:
			if (theEvent->xselectionclear.window != my_main_wind) {
				WriteExtraErr(
					"Got SelectionClear for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - SelectionClear");
				WriteDbgAtom("selection",
					theEvent->xselectionclear.selection);
#endif

				if (theEvent->xselectionclear.selection ==
					MyXA_CLIPBOARD)
				{
					FreeMyClipBuffer();
				}
			}
			break;
#endif
#if EnableDragDrop
		case SelectionNotify:
			if (theEvent->xselection.requestor != my_main_wind) {
				WriteExtraErr(
					"Got SelectionNotify for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - SelectionNotify");
				WriteDbgAtom("selection",
					theEvent->xselection.selection);
				WriteDbgAtom("target", theEvent->xselection.target);
				WriteDbgAtom("property", theEvent->xselection.property);
#endif

				if (theEvent->xselection.selection == MyXA_DndSelection)
				{
					HandleSelectionNotifyDnd(theEvent);
				} else {
					WriteExtraErr(
						"Got Unknown selection in SelectionNotify");
				}
			}
			break;
#endif
		case ClientMessage:
			if (theEvent->xclient.window != my_main_wind) {
				WriteExtraErr(
					"Got ClientMessage for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - ClientMessage");
				WriteDbgAtom("message_type",
					theEvent->xclient.message_type);
#endif

#if EnableDragDrop
				if (theEvent->xclient.message_type == MyXA_DndEnter) {
					/* printf("Got XdndEnter\n"); */
				} else if (theEvent->xclient.message_type ==
					MyXA_DndLeave)
				{
					/* printf("Got XdndLeave\n"); */
				} else if (theEvent->xclient.message_type ==
					MyXA_DndPosition)
				{
					HandleClientMessageDndPosition(theEvent);
				} else if (theEvent->xclient.message_type ==
					MyXA_DndDrop)
				{
					HandleClientMessageDndDrop(theEvent);
				} else
#endif
				{
					if ((32 == theEvent->xclient.format) &&
						(theEvent->xclient.data.l[0] == MyXA_DeleteW))
					{
						/*
							I would think that should test that
								WM_PROTOCOLS == message_type
							but none of the other programs I looked
							at did.
						*/
						RequestMacOff = trueblnr;
					}
				}
			}
			break;
		case FocusIn:
			if (theEvent->xfocus.window != my_main_wind) {
				WriteExtraErr("Got FocusIn for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - FocusIn");
#endif

				gTrueBackgroundFlag = falseblnr;
#if UseMotionEvents
				CheckMouseState();
					/*
						Doesn't help on x11 for OS X,
						can't get new mouse position
						in any fashion until mouse moves.
					*/
#endif
			}
			break;
		case FocusOut:
			if (theEvent->xfocus.window != my_main_wind) {
				WriteExtraErr("Got FocusOut for some other window");
			} else {
#if MyDbgEvents
				dbglog_writeln("- event - FocusOut");
#endif

				gTrueBackgroundFlag = trueblnr;
			}
			break;
		default:
			break;
	}
}

/* --- main window creation and disposal --- */

LOCALVAR int my_argc;
LOCALVAR char **my_argv;

LOCALVAR char *display_name = NULL;

LOCALFUNC blnr Screen_Init(void)
{
	Window rootwin;
	int screen;
	Colormap Xcmap;
	Visual *Xvisual;

	x_display = XOpenDisplay(display_name);
	if (NULL == x_display) {
		fprintf(stderr, "Cannot connect to X server.\n");
		return falseblnr;
	}

	screen = DefaultScreen(x_display);

	rootwin = XRootWindow(x_display, screen);

	Xcmap = DefaultColormap(x_display, screen);

	Xvisual = DefaultVisual(x_display, screen);

	LoadMyXA();

	XParseColor(x_display, Xcmap, "#000000", &x_black);
	if (! XAllocColor(x_display, Xcmap, &x_black)) {
		WriteExtraErr("XParseColor black fails");
	}
	XParseColor(x_display, Xcmap, "#ffffff", &x_white);
	if (! XAllocColor(x_display, Xcmap, &x_white)) {
		WriteExtraErr("XParseColor white fails");
	}

	if (! CreateMyBlankCursor(rootwin)) {
		return falseblnr;
	}

	my_image = XCreateImage(x_display, Xvisual, 1, XYBitmap, 0,
		NULL /* (char *)image_Mem1 */,
		vMacScreenWidth, vMacScreenHeight, 32,
		vMacScreenMonoByteWidth);
	if (NULL == my_image) {
		fprintf(stderr, "XCreateImage failed.\n");
		return falseblnr;
	}

#if 1
	fprintf(stderr, "bitmap_bit_order = %d\n",
		(int)my_image->bitmap_bit_order);
	fprintf(stderr, "byte_order = %d\n", (int)my_image->byte_order);
#endif

	my_image->bitmap_bit_order = MSBFirst;
	my_image->byte_order = MSBFirst;

#if EnableMagnify
	my_Scaled_image = XCreateImage(x_display, Xvisual, 1, XYBitmap, 0,
		NULL /* (char *)image_Mem1 */,
		vMacScreenWidth * MyWindowScale,
		vMacScreenHeight * MyWindowScale,
		32, vMacScreenMonoByteWidth * MyWindowScale);
	if (NULL == my_Scaled_image) {
		fprintf(stderr, "XCreateImage failed.\n");
		return falseblnr;
	}

	my_Scaled_image->bitmap_bit_order = MSBFirst;
	my_Scaled_image->byte_order = MSBFirst;
#endif

#if 0 != vMacScreenDepth
	my_Color_image = XCreateImage(x_display, Xvisual, 24, ZPixmap, 0,
		NULL /* (char *)image_Mem1 */,
		vMacScreenWidth, vMacScreenHeight, 32,
			4 * (ui5r)vMacScreenWidth);
	if (NULL == my_Color_image) {
		fprintf(stderr, "XCreateImage Color failed.\n");
	} else {

#if 0
		fprintf(stderr, "DefaultDepth = %d\n",
			(int)DefaultDepth(x_display, screen));

		fprintf(stderr, "MSBFirst = %d\n", (int)MSBFirst);
		fprintf(stderr, "LSBFirst = %d\n", (int)LSBFirst);

		fprintf(stderr, "bitmap_bit_order = %d\n",
			(int)my_Color_image->bitmap_bit_order);
		fprintf(stderr, "byte_order = %d\n",
			(int)my_Color_image->byte_order);
		fprintf(stderr, "bitmap_unit = %d\n",
			(int)my_Color_image->bitmap_unit);
		fprintf(stderr, "bits_per_pixel = %d\n",
			(int)my_Color_image->bits_per_pixel);
		fprintf(stderr, "red_mask = %d\n",
			(int)my_Color_image->red_mask);
		fprintf(stderr, "green_mask = %d\n",
			(int)my_Color_image->green_mask);
		fprintf(stderr, "blue_mask = %d\n",
			(int)my_Color_image->blue_mask);
#endif

#if 5 == vMacScreenDepth
		/*
			In this specific case, can pass mac screen
			buffer directly to X, once set byte order.
		*/
		my_Color_image->bitmap_bit_order = MSBFirst;
		my_Color_image->byte_order = MSBFirst;
#endif

#if EnableMagnify
		my_ScaledColor_image = XCreateImage(x_display, Xvisual,
			24, ZPixmap, 0,
			NULL /* (char *)image_Mem1 */,
			vMacScreenWidth * MyWindowScale,
			vMacScreenHeight * MyWindowScale,
			32, 4 * (ui5r)vMacScreenWidth * MyWindowScale);
		if (NULL == my_ScaledColor_image) {
			fprintf(stderr, "XCreateImage Scaled Color failed.\n");
		} else
#endif
		{
			ColorModeWorks = trueblnr;
		}

	} /* XCreateImage my_Scaled_image */
#endif /* 0 != vMacScreenDepth */

	DisableKeyRepeat();

	return trueblnr;
}

LOCALPROC CloseMainWindow(void)
{
	if (my_gc != NULL) {
		XFreeGC(x_display, my_gc);
		my_gc = NULL;
	}
	if (my_main_wind) {
		XDestroyWindow(x_display, my_main_wind);
		my_main_wind = 0;
	}
}

enum {
	kMagStateNormal,
#if EnableMagnify
	kMagStateMagnifgy,
#endif
	kNumMagStates
};

#define kMagStateAuto kNumMagStates

#if MayNotFullScreen
LOCALVAR int CurWinIndx;
LOCALVAR blnr HavePositionWins[kNumMagStates];
LOCALVAR int WinPositionWinsH[kNumMagStates];
LOCALVAR int WinPositionWinsV[kNumMagStates];
#endif

LOCALPROC ZapMyWState(void)
{
	my_main_wind = 0;
	my_gc = NULL;
}

LOCALFUNC blnr CreateMainWindow(void)
{
	Window rootwin;
	int screen;
	int xr;
	int yr;
	unsigned int dr;
	unsigned int wr;
	unsigned int hr;
	unsigned int bwr;
	Window rr;
	int leftPos;
	int topPos;
#if MayNotFullScreen
	int WinIndx;
#endif
#if EnableDragDrop
	long int xdnd_version = 5;
#endif
	int NewWindowHeight = vMacScreenHeight;
	int NewWindowWidth = vMacScreenWidth;

	/* Get connection to X Server */
	screen = DefaultScreen(x_display);

	rootwin = XRootWindow(x_display, screen);

	XGetGeometry(x_display, rootwin,
		&rr, &xr, &yr, &wr, &hr, &bwr, &dr);

#if EnableMagnify
	if (UseMagnify) {
		NewWindowHeight *= MyWindowScale;
		NewWindowWidth *= MyWindowScale;
	}
#endif

	if (wr > NewWindowWidth) {
		leftPos = (wr - NewWindowWidth) / 2;
	} else {
		leftPos = 0;
	}
	if (hr > NewWindowHeight) {
		topPos = (hr - NewWindowHeight) / 2;
	} else {
		topPos = 0;
	}

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		ViewHSize = wr;
		ViewVSize = hr;
#if EnableMagnify
		if (UseMagnify) {
			ViewHSize /= MyWindowScale;
			ViewVSize /= MyWindowScale;
		}
#endif
		if (ViewHSize >= vMacScreenWidth) {
			ViewHStart = 0;
			ViewHSize = vMacScreenWidth;
		} else {
			ViewHSize &= ~ 1;
		}
		if (ViewVSize >= vMacScreenHeight) {
			ViewVStart = 0;
			ViewVSize = vMacScreenHeight;
		} else {
			ViewVSize &= ~ 1;
		}
	}
#endif

#if VarFullScreen
	if (! UseFullScreen)
#endif
#if MayNotFullScreen
	{
#if EnableMagnify
		if (UseMagnify) {
			WinIndx = kMagStateMagnifgy;
		} else
#endif
		{
			WinIndx = kMagStateNormal;
		}

		if (! HavePositionWins[WinIndx]) {
			WinPositionWinsH[WinIndx] = leftPos;
			WinPositionWinsV[WinIndx] = topPos;
			HavePositionWins[WinIndx] = trueblnr;
		} else {
			leftPos = WinPositionWinsH[WinIndx];
			topPos = WinPositionWinsV[WinIndx];
		}
	}
#endif

#if VarFullScreen
	if (UseFullScreen)
#endif
#if MayFullScreen
	{
		XSetWindowAttributes xattr;
		xattr.override_redirect = True;
		xattr.background_pixel = x_black.pixel;
		xattr.border_pixel = x_white.pixel;

		my_main_wind = XCreateWindow(x_display, rr,
			0, 0, wr, hr, 0,
			CopyFromParent, /* depth */
			InputOutput, /* class */
			CopyFromParent, /* visual */
			CWOverrideRedirect | CWBackPixel | CWBorderPixel,
				/* valuemask */
			&xattr /* attributes */);
	}
#endif
#if VarFullScreen
	else
#endif
#if MayNotFullScreen
	{
		my_main_wind = XCreateSimpleWindow(x_display, rootwin,
			leftPos,
			topPos,
			NewWindowWidth, NewWindowHeight, 4,
			x_white.pixel,
			x_black.pixel);
	}
#endif

	if (! my_main_wind) {
		WriteExtraErr("XCreateSimpleWindow failed.");
		return falseblnr;
	} else {
		char *win_name =
			(NULL != n_arg) ? n_arg : (
#if CanGetAppPath
			(NULL != app_name) ? app_name :
#endif
			kStrAppName);
		XSelectInput(x_display, my_main_wind,
			ExposureMask | KeyPressMask | KeyReleaseMask
			| ButtonPressMask | ButtonReleaseMask
#if UseMotionEvents
			| PointerMotionMask | EnterWindowMask | LeaveWindowMask
#endif
			| FocusChangeMask);

		XStoreName(x_display, my_main_wind, win_name);
		XSetIconName(x_display, my_main_wind, win_name);

		{
			XClassHint *hints = XAllocClassHint();
			if (hints) {
				hints->res_name = "minivmac";
				hints->res_class = "minivmac";
				XSetClassHint(x_display, my_main_wind, hints);
				XFree(hints);
			}
		}

		{
			XWMHints *hints = XAllocWMHints();
			if (hints) {
				hints->input = True;
				hints->initial_state = NormalState;
				hints->flags = InputHint | StateHint;
				XSetWMHints(x_display, my_main_wind, hints);
				XFree(hints);
			}

		}

		XSetCommand(x_display, my_main_wind, my_argv, my_argc);

		/* let us handle a click on the close box */
		XSetWMProtocols(x_display, my_main_wind, &MyXA_DeleteW, 1);

#if EnableDragDrop
		XChangeProperty (x_display, my_main_wind, MyXA_DndAware,
			XA_ATOM, 32, PropModeReplace,
			(unsigned char *) &xdnd_version, 1);
#endif

		my_gc = XCreateGC(x_display, my_main_wind, 0, NULL);
		if (NULL == my_gc) {
			WriteExtraErr("XCreateGC failed.");
			return falseblnr;
		}
		XSetState(x_display, my_gc, x_black.pixel, x_white.pixel,
			GXcopy, AllPlanes);

#if VarFullScreen
		if (! UseFullScreen)
#endif
#if MayNotFullScreen
		{
			XSizeHints *hints = XAllocSizeHints();
			if (hints) {
				hints->min_width = NewWindowWidth;
				hints->max_width = NewWindowWidth;
				hints->min_height = NewWindowHeight;
				hints->max_height = NewWindowHeight;

				/*
					Try again to say where the window ought to go.
					I've seen this described as obsolete, but it
					seems to work on all x implementations tried
					so far, and nothing else does.
				*/
				hints->x = leftPos;
				hints->y = topPos;
				hints->width = NewWindowWidth;
				hints->height = NewWindowHeight;

				hints->flags = PMinSize | PMaxSize | PPosition | PSize;
				XSetWMNormalHints(x_display, my_main_wind, hints);
				XFree(hints);
			}
		}
#endif

#if VarFullScreen
		if (UseFullScreen)
#endif
#if MayFullScreen
		{
			hOffset = leftPos;
			vOffset = topPos;
		}
#endif

		DisconnectKeyCodes3();
			/* since will lose keystrokes to old window */

#if MayNotFullScreen
		CurWinIndx = WinIndx;
#endif

		XMapRaised(x_display, my_main_wind);

#if 0
		XSync(x_display, 0);
#endif

#if 0
		/*
			This helps in Red Hat 9 to get the new window
			activated, and I've seen other programs
			do similar things.
		*/
		/*
			In current scheme, haven't closed old window
			yet. If old window full screen, never receive
			expose event for new one.
		*/
		{
			XEvent event;

			do {
				XNextEvent(x_display, &event);
				HandleTheEvent(&event);
			} while (! ((Expose == event.type)
				&& (event.xexpose.window == my_main_wind)));
		}
#endif

		NeedFinishOpen1 = trueblnr;
		NeedFinishOpen2 = trueblnr;

		return trueblnr;
	}
}

#if MayFullScreen
LOCALVAR blnr GrabMachine = falseblnr;
#endif

#if MayFullScreen
LOCALPROC GrabTheMachine(void)
{
#if EnableMouseMotion && MayFullScreen
	StartSaveMouseMotion();
#endif
	MyGrabKeyboard();
}
#endif

#if MayFullScreen
LOCALPROC UngrabMachine(void)
{
#if EnableMouseMotion && MayFullScreen
	StopSaveMouseMotion();
#endif
	MyUnGrabKeyboard();
}
#endif

struct MyWState {
	Window f_my_main_wind;
	GC f_my_gc;
#if MayFullScreen
	short f_hOffset;
	short f_vOffset;
	ui4r f_ViewHSize;
	ui4r f_ViewVSize;
	ui4r f_ViewHStart;
	ui4r f_ViewVStart;
#endif
#if VarFullScreen
	blnr f_UseFullScreen;
#endif
#if EnableMagnify
	blnr f_UseMagnify;
#endif
};
typedef struct MyWState MyWState;

LOCALPROC GetMyWState(MyWState *r)
{
	r->f_my_main_wind = my_main_wind;
	r->f_my_gc = my_gc;
#if MayFullScreen
	r->f_hOffset = hOffset;
	r->f_vOffset = vOffset;
	r->f_ViewHSize = ViewHSize;
	r->f_ViewVSize = ViewVSize;
	r->f_ViewHStart = ViewHStart;
	r->f_ViewVStart = ViewVStart;
#endif
#if VarFullScreen
	r->f_UseFullScreen = UseFullScreen;
#endif
#if EnableMagnify
	r->f_UseMagnify = UseMagnify;
#endif
}

LOCALPROC SetMyWState(MyWState *r)
{
	my_main_wind = r->f_my_main_wind;
	my_gc = r->f_my_gc;
#if MayFullScreen
	hOffset = r->f_hOffset;
	vOffset = r->f_vOffset;
	ViewHSize = r->f_ViewHSize;
	ViewVSize = r->f_ViewVSize;
	ViewHStart = r->f_ViewHStart;
	ViewVStart = r->f_ViewVStart;
#endif
#if VarFullScreen
	UseFullScreen = r->f_UseFullScreen;
#endif
#if EnableMagnify
	UseMagnify = r->f_UseMagnify;
#endif
}

LOCALVAR blnr WantRestoreCursPos = falseblnr;
LOCALVAR ui4b RestoreMouseH;
LOCALVAR ui4b RestoreMouseV;

LOCALFUNC blnr ReCreateMainWindow(void)
{
	MyWState old_state;
	MyWState new_state;
#if IncludeHostTextClipExchange
	blnr OwnClipboard = falseblnr;
#endif

	if (HaveCursorHidden) {
		WantRestoreCursPos = trueblnr;
		RestoreMouseH = CurMouseH;
		RestoreMouseV = CurMouseV;
	}

	ForceShowCursor(); /* hide/show cursor api is per window */

#if MayNotFullScreen
#if VarFullScreen
	if (! UseFullScreen)
#endif
	if (my_main_wind)
	if (! NeedFinishOpen2)
	{
		/* save old position */
		int xr;
		int yr;
		unsigned int dr;
		unsigned int wr;
		unsigned int hr;
		unsigned int bwr;
		Window rr;
		Window rr2;

		/* Get connection to X Server */
		int screen = DefaultScreen(x_display);

		Window rootwin = XRootWindow(x_display, screen);

		XGetGeometry(x_display, rootwin,
			&rr, &xr, &yr, &wr, &hr, &bwr, &dr);

		/*
			Couldn't reliably find out where window
			is now, due to what seem to be some
			broken X implementations, and so instead
			track how far window has moved.
		*/
		XSync(x_display, 0);
		if (XTranslateCoordinates(x_display, my_main_wind, rootwin,
			0, 0, &xr, &yr, &rr2))
		{
			int newposh =
				WinPositionWinsH[CurWinIndx] + (xr - SavedTransH);
			int newposv =
				WinPositionWinsV[CurWinIndx] + (yr - SavedTransV);
			if ((newposv > 0) && (newposv < hr) && (newposh < wr)) {
				WinPositionWinsH[CurWinIndx] = newposh;
				WinPositionWinsV[CurWinIndx] = newposv;
				SavedTransH = xr;
				SavedTransV = yr;
			}
		}
	}
#endif

#if MayFullScreen
	if (GrabMachine) {
		GrabMachine = falseblnr;
		UngrabMachine();
	}
#endif

	GetMyWState(&old_state);
	ZapMyWState();

#if EnableMagnify
	UseMagnify = WantMagnify;
#endif
#if VarFullScreen
	UseFullScreen = WantFullScreen;
#endif

	ColorTransValid = falseblnr;

	if (! CreateMainWindow()) {
		CloseMainWindow();
		SetMyWState(&old_state);

		/* avoid retry */
#if VarFullScreen
		WantFullScreen = UseFullScreen;
#endif
#if EnableMagnify
		WantMagnify = UseMagnify;
#endif

		return falseblnr;
	} else {
		GetMyWState(&new_state);
		SetMyWState(&old_state);

#if IncludeHostTextClipExchange
		if (my_main_wind) {
			if (XGetSelectionOwner(x_display, MyXA_CLIPBOARD) ==
				my_main_wind)
			{
				OwnClipboard = trueblnr;
			}
		}
#endif

		CloseMainWindow();

		SetMyWState(&new_state);

#if IncludeHostTextClipExchange
		if (OwnClipboard) {
			XSetSelectionOwner(x_display, MyXA_CLIPBOARD,
				my_main_wind, CurrentTime);
		}
#endif
	}

	return trueblnr;
}

#if VarFullScreen && EnableMagnify
enum {
	kWinStateWindowed,
#if EnableMagnify
	kWinStateFullScreen,
#endif
	kNumWinStates
};
#endif

#if VarFullScreen && EnableMagnify
LOCALVAR int WinMagStates[kNumWinStates];
#endif

LOCALPROC ZapWinStateVars(void)
{
#if MayNotFullScreen
	{
		int i;

		for (i = 0; i < kNumMagStates; ++i) {
			HavePositionWins[i] = falseblnr;
		}
	}
#endif
#if VarFullScreen && EnableMagnify
	{
		int i;

		for (i = 0; i < kNumWinStates; ++i) {
			WinMagStates[i] = kMagStateAuto;
		}
	}
#endif
}

#if VarFullScreen
LOCALPROC ToggleWantFullScreen(void)
{
	WantFullScreen = ! WantFullScreen;

#if EnableMagnify
	{
		int OldWinState =
			UseFullScreen ? kWinStateFullScreen : kWinStateWindowed;
		int OldMagState =
			UseMagnify ? kMagStateMagnifgy : kMagStateNormal;

		int NewWinState =
			WantFullScreen ? kWinStateFullScreen : kWinStateWindowed;
		int NewMagState = WinMagStates[NewWinState];
		WinMagStates[OldWinState] = OldMagState;
		if (kMagStateAuto != NewMagState) {
			WantMagnify = (kMagStateMagnifgy == NewMagState);
		} else {
			WantMagnify = falseblnr;
			if (WantFullScreen) {
				Window rootwin;
				int xr;
				int yr;
				unsigned int dr;
				unsigned int wr;
				unsigned int hr;
				unsigned int bwr;
				Window rr;

				rootwin =
					XRootWindow(x_display, DefaultScreen(x_display));
				XGetGeometry(x_display, rootwin,
					&rr, &xr, &yr, &wr, &hr, &bwr, &dr);
				if ((wr >= vMacScreenWidth * MyWindowScale)
					&& (hr >= vMacScreenHeight * MyWindowScale)
					)
				{
					WantMagnify = trueblnr;
				}
			}
		}
	}
#endif
}
#endif

/* --- SavedTasks --- */

LOCALPROC LeaveBackground(void)
{
	ReconnectKeyCodes3();
	DisableKeyRepeat();
}

LOCALPROC EnterBackground(void)
{
	RestoreKeyRepeat();
	DisconnectKeyCodes3();

	ForceShowCursor();
}

LOCALPROC LeaveSpeedStopped(void)
{
#if MySoundEnabled
	MySound_Start();
#endif

	StartUpTimeAdjust();
}

LOCALPROC EnterSpeedStopped(void)
{
#if MySoundEnabled
	MySound_Stop();
#endif
}

LOCALPROC CheckForSavedTasks(void)
{
	if (MyEvtQNeedRecover) {
		MyEvtQNeedRecover = falseblnr;

		/* attempt cleanup, MyEvtQNeedRecover may get set again */
		MyEvtQTryRecoverFromFull();
	}

	if (NeedFinishOpen2 && ! NeedFinishOpen1) {
		NeedFinishOpen2 = falseblnr;

#if VarFullScreen
		if (UseFullScreen)
#endif
#if MayFullScreen
		{
			XSetInputFocus(x_display, my_main_wind,
				RevertToPointerRoot, CurrentTime);
		}
#endif
#if VarFullScreen
		else
#endif
#if MayNotFullScreen
		{
			Window rr;
			int screen = DefaultScreen(x_display);
			Window rootwin = XRootWindow(x_display, screen);
#if 0
			/*
				This doesn't work right in Red Hat 6, and may not
				be needed anymore, now that using PPosition hint.
			*/
			XMoveWindow(x_display, my_main_wind,
				leftPos, topPos);
				/*
					Needed after XMapRaised, because some window
					managers will apparently ignore where the
					window was asked to be put.
				*/
#endif

			XSync(x_display, 0);
				/*
					apparently, XTranslateCoordinates can be inaccurate
					without this
				*/
			XTranslateCoordinates(x_display, my_main_wind, rootwin,
				0, 0, &SavedTransH, &SavedTransV, &rr);
		}
#endif

		if (WantRestoreCursPos) {
#if EnableMouseMotion && MayFullScreen
			if (! HaveMouseMotion)
#endif
			{
				(void) MyMoveMouse(RestoreMouseH, RestoreMouseV);
				WantCursorHidden = trueblnr;
			}
			WantRestoreCursPos = falseblnr;
		}
	}

#if EnableMouseMotion && MayFullScreen
	if (HaveMouseMotion) {
		MyMouseConstrain();
	}
#endif

	if (RequestMacOff) {
		RequestMacOff = falseblnr;
		if (AnyDiskInserted()) {
			MacMsgOverride(kStrQuitWarningTitle,
				kStrQuitWarningMessage);
		} else {
			ForceMacOff = trueblnr;
		}
	}

	if (ForceMacOff) {
		return;
	}

	if (gTrueBackgroundFlag != gBackgroundFlag) {
		gBackgroundFlag = gTrueBackgroundFlag;
		if (gTrueBackgroundFlag) {
			EnterBackground();
		} else {
			LeaveBackground();
		}
	}

	if (CurSpeedStopped != (SpeedStopped ||
		(gBackgroundFlag && ! RunInBackground
#if EnableAutoSlow && 0
			&& (QuietSubTicks >= 4092)
#endif
		)))
	{
		CurSpeedStopped = ! CurSpeedStopped;
		if (CurSpeedStopped) {
			EnterSpeedStopped();
		} else {
			LeaveSpeedStopped();
		}
	}

#if MayFullScreen
	if (gTrueBackgroundFlag
#if VarFullScreen
		&& WantFullScreen
#endif
		)
	{
		/*
			Since often get here on Ubuntu Linux 5.10
			running on a slow machine (emulated) when
			attempt to enter full screen, don't abort
			full screen, but try to fix it.
		*/
#if 0
		ToggleWantFullScreen();
#else
		XRaiseWindow(x_display, my_main_wind);
		XSetInputFocus(x_display, my_main_wind,
			RevertToPointerRoot, CurrentTime);
#endif
	}
#endif

#if EnableMagnify || VarFullScreen
	if (0
#if EnableMagnify
		|| (UseMagnify != WantMagnify)
#endif
#if VarFullScreen
		|| (UseFullScreen != WantFullScreen)
#endif
		)
	{
		(void) ReCreateMainWindow();
	}
#endif


#if MayFullScreen
	if (GrabMachine != (
#if VarFullScreen
		UseFullScreen &&
#endif
		! (gTrueBackgroundFlag || CurSpeedStopped)))
	{
		GrabMachine = ! GrabMachine;
		if (GrabMachine) {
			GrabTheMachine();
		} else {
			UngrabMachine();
		}
	}
#endif

#if IncludeSonyNew
	if (vSonyNewDiskWanted) {
#if IncludeSonyNameNew
		if (vSonyNewDiskName != NotAPbuf) {
			ui3p NewDiskNameDat;
			if (MacRomanTextToNativePtr(vSonyNewDiskName, trueblnr,
				&NewDiskNameDat))
			{
				MakeNewDisk(vSonyNewDiskSize, (char *)NewDiskNameDat);
				free(NewDiskNameDat);
			}
			PbufDispose(vSonyNewDiskName);
			vSonyNewDiskName = NotAPbuf;
		} else
#endif
		{
			MakeNewDiskAtDefault(vSonyNewDiskSize);
		}
		vSonyNewDiskWanted = falseblnr;
			/* must be done after may have gotten disk */
	}
#endif

	if ((nullpr != SavedBriefMsg) & ! MacMsgDisplayed) {
		MacMsgDisplayOn();
	}

	if (NeedWholeScreenDraw) {
		NeedWholeScreenDraw = falseblnr;
		ScreenChangedAll();
	}

	MyDrawChangesAndClear();

	if (HaveCursorHidden != (WantCursorHidden
		&& ! (gTrueBackgroundFlag || CurSpeedStopped)))
	{
		HaveCursorHidden = ! HaveCursorHidden;
		if (HaveCursorHidden) {
			XDefineCursor(x_display, my_main_wind, blankCursor);
		} else {
			XUndefineCursor(x_display, my_main_wind);
		}
	}
}

/* --- command line parsing --- */

LOCALFUNC blnr ScanCommandLine(void)
{
	char *pa;
	int i = 1;

label_retry:
	if (i < my_argc) {
		pa = my_argv[i++];
		if ('-' == pa[0]) {
			if ((0 == strcmp(pa, "--display"))
				|| (0 == strcmp(pa, "-display")))
			{
				if (i < my_argc) {
					display_name = my_argv[i++];
					goto label_retry;
				}
			} else
			if ((0 == strcmp(pa, "--rom"))
				|| (0 == strcmp(pa, "-r")))
			{
				if (i < my_argc) {
					rom_path = my_argv[i++];
					goto label_retry;
				}
			} else
			if (0 == strcmp(pa, "-n"))
			{
				if (i < my_argc) {
					n_arg = my_argv[i++];
					goto label_retry;
				}
			} else
			if (0 == strcmp(pa, "-d"))
			{
				if (i < my_argc) {
					d_arg = my_argv[i++];
					goto label_retry;
				}
			} else
#ifndef UsingAlsa
#define UsingAlsa 0
#endif

#if UsingAlsa
			if ((0 == strcmp(pa, "--alsadev"))
				|| (0 == strcmp(pa, "-alsadev")))
			{
				if (i < my_argc) {
					alsadev_name = my_argv[i++];
					goto label_retry;
				}
			} else
#endif
#if 0
			if (0 == strcmp(pa, "-l")) {
				SpeedValue = 0;
				goto label_retry;
			} else
#endif
			{
				MacMsg(kStrBadArgTitle, kStrBadArgMessage, falseblnr);
			}
		} else {
			(void) Sony_Insert1(pa, falseblnr);
			goto label_retry;
		}
	}

	return trueblnr;
}

/* --- main program flow --- */

LOCALVAR ui5b OnTrueTime = 0;

GLOBALFUNC blnr ExtraTimeNotOver(void)
{
	UpdateTrueEmulatedTime();
	return TrueEmulatedTime == OnTrueTime;
}

/* --- platform independent code can be thought of as going here --- */

#include "PROGMAIN.h"

LOCALPROC RunEmulatedTicksToTrueTime(void)
{
	si3b n = OnTrueTime - CurEmulatedTime;

	if (n > 0) {
		if (CheckDateTime()) {
#if MySoundEnabled
			MySound_SecondNotify();
#endif
		}

		if ((! gBackgroundFlag)
#if UseMotionEvents
			&& (! CaughtMouse)
#endif
			)
		{
			CheckMouseState();
		}

		DoEmulateOneTick();
		++CurEmulatedTime;

#if EnableMouseMotion && MayFullScreen
		if (HaveMouseMotion) {
			AutoScrollScreen();
		}
#endif
		MyDrawChangesAndClear();

		if (n > 8) {
			/* emulation not fast enough */
			n = 8;
			CurEmulatedTime = OnTrueTime - n;
		}

		if (ExtraTimeNotOver() && (--n > 0)) {
			/* lagging, catch up */

			EmVideoDisable = trueblnr;

			do {
				DoEmulateOneTick();
				++CurEmulatedTime;
			} while (ExtraTimeNotOver()
				&& (--n > 0));

			EmVideoDisable = falseblnr;
		}

		EmLagTime = n;
	}
}

LOCALPROC RunOnEndOfSixtieth(void)
{
	while (ExtraTimeNotOver()) {
		struct timespec rqt;
		struct timespec rmt;

		si5b TimeDiff = GetTimeDiff();
		if (TimeDiff < 0) {
			rqt.tv_sec = 0;
			rqt.tv_nsec = (- TimeDiff) * 1000;
			(void) nanosleep(&rqt, &rmt);
		}
	}

	OnTrueTime = TrueEmulatedTime;
	RunEmulatedTicksToTrueTime();
}

LOCALPROC WaitForTheNextEvent(void)
{
	XEvent event;

	XNextEvent(x_display, &event);
	HandleTheEvent(&event);
}

LOCALPROC CheckForSystemEvents(void)
{
	int i = 10;

	while ((XEventsQueued(x_display, QueuedAfterReading) > 0)
		&& (--i >= 0))
	{
		WaitForTheNextEvent();
	}
	XFlush(x_display);
}

LOCALPROC MainEventLoop(void)
{
	for (; ; ) {
		CheckForSystemEvents();
		CheckForSavedTasks();
		if (ForceMacOff) {
			return;
		}

		if (CurSpeedStopped) {
			WaitForTheNextEvent();
		} else {
			DoEmulateExtraTime();
			RunOnEndOfSixtieth();
		}
	}
}

LOCALPROC ZapOSGLUVars(void)
{
	InitDrives();
	ZapWinStateVars();
}

LOCALPROC ReserveAllocAll(void)
{
#if dbglog_HAVE
	dbglog_ReserveAlloc();
#endif
	ReserveAllocOneBlock(&ROM, kROM_Size, 5, falseblnr);

	ReserveAllocOneBlock(&screencomparebuff,
		vMacScreenNumBytes, 5, trueblnr);
#if UseControlKeys
	ReserveAllocOneBlock(&CntrlDisplayBuff,
		vMacScreenNumBytes, 5, falseblnr);
#endif
#if WantScalingBuff
	ReserveAllocOneBlock(&ScalingBuff,
		ScalingBuffsz, 5, falseblnr);
#endif
#if WantScalingTabl
	ReserveAllocOneBlock(&ScalingTabl,
		ScalingTablsz, 5, falseblnr);
#endif

#if MySoundEnabled
	ReserveAllocOneBlock((ui3p *)&TheSoundBuffer,
		dbhBufferSize, 5, falseblnr);
#endif

	EmulationReserveAlloc();
}

LOCALFUNC blnr AllocMyMemory(void)
{
	uimr n;
	blnr IsOk = falseblnr;

	ReserveAllocOffset = 0;
	ReserveAllocBigBlock = nullpr;
	ReserveAllocAll();
	n = ReserveAllocOffset;
	ReserveAllocBigBlock = (ui3p)calloc(1, n);
	if (NULL == ReserveAllocBigBlock) {
		MacMsg(kStrOutOfMemTitle, kStrOutOfMemMessage, trueblnr);
	} else {
		ReserveAllocOffset = 0;
		ReserveAllocAll();
		if (n != ReserveAllocOffset) {
			/* oops, program error */
		} else {
			IsOk = trueblnr;
		}
	}

	return IsOk;
}

LOCALPROC UnallocMyMemory(void)
{
	if (nullpr != ReserveAllocBigBlock) {
		free((char *)ReserveAllocBigBlock);
	}
}

#if HaveAppPathLink
LOCALFUNC blnr ReadLink_Alloc(char *path, char **r)
{
	/*
		This should work to find size:

		struct stat r;

		if (lstat(path, &r) != -1) {
			r = r.st_size;
			IsOk = trueblnr;
		}

		But observed to return 0 in Ubuntu 10.04 x86-64
	*/

	char *s;
	int sz;
	char *p;
	blnr IsOk = falseblnr;
	size_t s_alloc = 256;

label_retry:
	s = (char *)malloc(s_alloc);
	if (NULL == s) {
		fprintf(stderr, "malloc failed.\n");
	} else {
		sz = readlink(path, s, s_alloc);
		if ((sz < 0) || (sz >= s_alloc)) {
			free(s);
			if (sz == s_alloc) {
				s_alloc <<= 1;
				goto label_retry;
			} else {
				fprintf(stderr, "readlink failed.\n");
			}
		} else {
			/* ok */
			p = (char *)malloc(sz + 1);
			if (NULL == p) {
				fprintf(stderr, "malloc failed.\n");
			} else {
				(void) memcpy(p, s, sz);
				p[sz] = 0;
				*r = p;
				IsOk = trueblnr;
			}
			free(s);
		}
	}

	return IsOk;
}
#endif

#if HaveSysctlPath
LOCALFUNC blnr ReadKernProcPathname(char **r)
{
	size_t s_alloc;
	char *s;
	int mib[] = {
		CTL_KERN,
		KERN_PROC,
		KERN_PROC_PATHNAME,
		-1
	};
	blnr IsOk = falseblnr;

	if (0 != sysctl(mib, sizeof(mib) / sizeof(int),
		NULL, &s_alloc, NULL, 0))
	{
		fprintf(stderr, "sysctl failed.\n");
	} else {
		s = (char *)malloc(s_alloc);
		if (NULL == s) {
			fprintf(stderr, "malloc failed.\n");
		} else {
			if (0 != sysctl(mib, sizeof(mib) / sizeof(int),
				s, &s_alloc, NULL, 0))
			{
				fprintf(stderr, "sysctl 2 failed.\n");
			} else {
				*r = s;
				IsOk = trueblnr;
			}
			if (! IsOk) {
				free(s);
			}
		}
	}

	return IsOk;
}
#endif

#if CanGetAppPath
LOCALFUNC blnr Path2ParentAndName(char *path,
	char **parent, char **name)
{
	blnr IsOk = falseblnr;

	char *t = strrchr(path, '/');
	if (NULL == t) {
		fprintf(stderr, "no directory.\n");
	} else {
		int par_sz = t - path;
		char *par = (char *)malloc(par_sz + 1);
		if (NULL == par) {
			fprintf(stderr, "malloc failed.\n");
		} else {
			(void) memcpy(par, path, par_sz);
			par[par_sz] = 0;
			{
				int s_sz = strlen(path);
				int child_sz = s_sz - par_sz - 1;
				char *child = (char *)malloc(child_sz + 1);
				if (NULL == child) {
					fprintf(stderr, "malloc failed.\n");
				} else {
					(void) memcpy(child, t + 1, child_sz);
					child[child_sz] = 0;

					*name = child;
					IsOk = trueblnr;
					/* free(child); */
				}
			}
			if (! IsOk) {
				free(par);
			} else {
				*parent = par;
			}
		}
	}

	return IsOk;
}
#endif

#if CanGetAppPath
LOCALFUNC blnr InitWhereAmI(void)
{
	char *s;

	if (!
#if HaveAppPathLink
		ReadLink_Alloc(TheAppPathLink, &s)
#endif
#if HaveSysctlPath
		ReadKernProcPathname(&s)
#endif
		)
	{
		fprintf(stderr, "InitWhereAmI fails.\n");
	} else {
		if (! Path2ParentAndName(s, &app_parent, &app_name)) {
			fprintf(stderr, "Path2ParentAndName fails.\n");
		} else {
			/* ok */
			/*
				fprintf(stderr, "parent = %s.\n", app_parent);
				fprintf(stderr, "name = %s.\n", app_name);
			*/
		}

		free(s);
	}

	return trueblnr; /* keep going regardless */
}
#endif

#if CanGetAppPath
LOCALPROC UninitWhereAmI(void)
{
	MyMayFree(app_parent);
	MyMayFree(app_name);
}
#endif

LOCALFUNC blnr InitOSGLU(void)
{
	if (AllocMyMemory())
#if CanGetAppPath
	if (InitWhereAmI())
#endif
#if dbglog_HAVE
	if (dbglog_open())
#endif
	if (ScanCommandLine())
	if (LoadInitialImages())
	if (LoadMacRom())
#if UseActvCode
	if (ActvCodeInit())
#endif
	if (InitLocationDat())
#if MySoundEnabled
	if (MySound_Init())
#endif
	if (Screen_Init())
	if (CreateMainWindow())
	if (KC2MKCInit())
	if (InitEmulation())
	{
		return trueblnr;
	}
	return falseblnr;
}

LOCALPROC UnInitOSGLU(void)
{
	if (MacMsgDisplayed) {
		MacMsgDisplayOff();
	}

	RestoreKeyRepeat();
#if MayFullScreen
	UngrabMachine();
#endif
#if MySoundEnabled
	MySound_Stop();
#endif
#if MySoundEnabled
	MySound_UnInit();
#endif
#if IncludeHostTextClipExchange
	FreeMyClipBuffer();
#endif
#if IncludePbufs
	UnInitPbufs();
#endif
	UnInitDrives();

	ForceShowCursor();
	if (blankCursor != None) {
		XFreeCursor(x_display, blankCursor);
	}

	if (my_image != NULL) {
		XDestroyImage(my_image);
	}
#if EnableMagnify
	if (my_Scaled_image != NULL) {
		XDestroyImage(my_Scaled_image);
	}
#endif
#if 0 != vMacScreenDepth
	if (my_Color_image != NULL) {
		XDestroyImage(my_Color_image);
	}
#endif
#if EnableMagnify && (0 != vMacScreenDepth)
	if (my_ScaledColor_image != NULL) {
		XDestroyImage(my_ScaledColor_image);
	}
#endif

	CloseMainWindow();
	if (x_display != NULL) {
		XCloseDisplay(x_display);
	}

#if dbglog_HAVE
	dbglog_close();
#endif

#if CanGetAppPath
	UninitWhereAmI();
#endif
	UnallocMyMemory();

	CheckSavedMacMsg();
}

int main(int argc, char **argv)
{
	my_argc = argc;
	my_argv = argv;

	ZapOSGLUVars();
	if (InitOSGLU()) {
		MainEventLoop();
	}
	UnInitOSGLU();

	return 0;
}
