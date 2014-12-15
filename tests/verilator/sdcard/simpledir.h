#pragma once

#include "simplefile.h"

// Extends simple dir with way of opening files and looking at dirs!
// Not all systems provide this...

struct SimpleDirEntry;

enum SimpleFileStatus file_open_name(char const * path, struct SimpleFile * file);
enum SimpleFileStatus file_open_name_in_dir(struct SimpleDirEntry * entries, char const * filename, struct SimpleFile * file);
enum SimpleFileStatus file_open_dir(struct SimpleDirEntry * filename, struct SimpleFile * file);

// Reads entire dir into memory (i.e. give it a decent chunk of sdram)
enum SimpleFileStatus dir_init(void * mem, int space);
struct SimpleDirEntry * dir_entries_filtered(char const * dirPath, int (*filter)(struct SimpleDirEntry *));
struct SimpleDirEntry * dir_entries(char const * dirPath);

char const * dir_filename(struct SimpleDirEntry *);
char const * dir_path(struct SimpleDirEntry *);
int dir_filesize(struct SimpleDirEntry *);
struct SimpleDirEntry * dir_next(struct SimpleDirEntry *);
int dir_is_subdir(struct SimpleDirEntry *);

