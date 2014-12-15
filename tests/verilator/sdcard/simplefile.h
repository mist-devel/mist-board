#pragma once

enum SimpleFileStatus {SimpleFile_OK, SimpleFile_FAIL};

struct SimpleFile;

// NB when switching file, the other file may loose its position, depending on implementation!

int file_struct_size();

void file_init(struct SimpleFile * file);

char const * file_path(struct SimpleFile * file);
char const * file_name(struct SimpleFile * file);
enum SimpleFileStatus file_read(struct SimpleFile * file, void * buffer, int bytes, int * bytesread);
enum SimpleFileStatus file_seek(struct SimpleFile * file, int offsetFromStart);
int file_size(struct SimpleFile * file);
int file_readonly(struct SimpleFile * file);

enum SimpleFileStatus file_write(struct SimpleFile * file, void * buffer, int bytes, int * byteswritten);
enum SimpleFileStatus file_write_flush();

