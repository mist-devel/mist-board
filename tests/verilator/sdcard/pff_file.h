#pragma once

#include "simplefile.h"
#include "simpledir.h"

#define MAX_DIR_LENGTH (9*5+1)
#define MAX_FILE_LENGTH (8+3+1+1)
#define MAX_PATH_LENGTH (9*5 + 8+3+1 + 1)

// Do not access these directly... They vary by architecture, just the simplefile/simpledir interface is the same
struct SimpleFile
{
	char path[MAX_PATH_LENGTH];
	int is_readonly;
	int size;
};

struct SimpleDirEntry
{
	char path[MAX_PATH_LENGTH];
	char * filename_ptr;
	char lfn[256];
	int size;
	int is_subdir;
	int is_readonly;
	struct SimpleDirEntry * next; // as linked list - want to allow sorting...
};

