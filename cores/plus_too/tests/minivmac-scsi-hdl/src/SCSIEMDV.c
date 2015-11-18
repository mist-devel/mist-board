/*
	SCSIEMDV.c

	Copyright (C) 2004 Philip Cummins, Paul C. Pratt

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
	Small Computer System Interface EMulated DeVice

	Emulates the SCSI found in the Mac Plus.

	This code adapted from "SCSI.c" in vMac by Philip Cummins.

	http://www.seagate.com/staticfiles/support/disc/manuals/scsi/100293068a.pdf
*/

/* NCR5380 chip emulation by Yoav Shadmi, 1998 */

#include <stdio.h>

#ifndef AllFiles
#include "SYSDEPNS.h"

#include "ENDIANAC.h"
#include "MYOSGLUE.h"
#include "EMCONFIG.h"
#include "GLOBGLUE.h"
#endif

#include "SCSIEMDV.h"

#include "../ncr5380_tb.h"

GLOBALPROC SCSI_Reset(void) { }

GLOBALFUNC ui5b SCSI_Access(ui5b Data, blnr WriteMem, CPTR addr) {
  return ncr_poll(Data, WriteMem, addr);
}
  
