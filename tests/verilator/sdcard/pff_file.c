#include "pff_file.h"

#include "pff.h"
#include "utils.h"
#include "diskio.h"
#include "simplefile.h"
//#include "printf.h"

struct SimpleFile * openfile;

void * dir_cache;
int dir_cache_size;

FATFS fatfs;
DIR dir;
FILINFO filinfo;

int write_pending;

#define translateStatus(res) (res == FR_OK ? SimpleFile_OK: SimpleFile_FAIL)
#define translateDStatus(res) (res == RES_OK ? SimpleFile_OK: SimpleFile_FAIL)

/*
enum SimpleFileStatus translateStatus(FRESULT res)
{
	return res == FR_OK ? SimpleFile_OK: SimpleFile_FAIL;
}

enum SimpleFileStatus translateDStatus(DSTATUS res)
{
	return res == RES_OK ? SimpleFile_OK: SimpleFile_FAIL;
}*/

char const * file_of(char const * path)
{
	char const * start = path + strlen(path);
	while (start!=path)
	{
		--start;
		if (*start == '/')
		{
			++start;
			break;
		}
	}
	return start;
}

void dir_of(char * dir, char const * path)
{
	char const * end = file_of(path);
	if (end != path) 
	{
		int len = end-path;
		while (len--)
		{
			*dir++ = *path++;
		}
		--dir;
	}

	*dir = '\0';
	return;
}

char const * file_name(struct SimpleFile * file)
{
	return file_of(&file->path[0]);
}

char const * file_path(struct SimpleFile * file)
{
	return &file->path[0];
}

void file_init(struct SimpleFile * file)
{
	file->path[0] = '\0';
	file->is_readonly = 1;
	file->size = 0;
}

void file_check_open(struct SimpleFile * file)
{
	if (openfile!=file)
	{
		file_write_flush();

		pf_open(&file->path[0]);
		openfile = file;
	}
}

enum SimpleFileStatus file_read(struct SimpleFile * file, void * buffer, int bytes, int * bytesread)
{
	UINT bytesread_word;
	FRESULT res;

	file_write_flush();
	file_check_open(file);

	res = pf_read(buffer, bytes, &bytesread_word);
	*bytesread = bytesread_word;

	return translateStatus(res);
}

enum SimpleFileStatus file_write(struct SimpleFile * file, void * buffer, int bytes, int * byteswritten)
{
	UINT byteswritten_word;
	FRESULT res;

	//printf("went\n");
	if (file->is_readonly) return SimpleFile_FAIL;

	file_check_open(file);

	int rem = bytes;
	while (rem>0)
	{
		int sector = fatfs.fptr>>9;
		int pos = fatfs.fptr&0x1ff;

		int bytes_this_cycle = rem;
		if (bytes_this_cycle>(512-pos))
			bytes_this_cycle = 512-pos;

		//printf("file_write:%d/%d - %d/%d\n",sector,pos,bytes_this_cycle,bytes);

		if (sector != write_pending)
		{
			file_write_flush();
		}

		if (write_pending <0)
		{
			// read the sector into our 512 byte buffer...
			pf_lseek(sector<<9);
			int fptr = fatfs.fptr;

			char temp_buffer[1];
			pf_read(&temp_buffer[0], 1, &byteswritten_word);

			//printf("Writing initial pos:%d\n",pos);

			// seek to the initial pos
			fatfs.fptr = fptr + pos;

			write_pending = sector;
		}

		res = disk_writep(buffer, pos, bytes_this_cycle);

		fatfs.fptr += bytes_this_cycle;
		rem-=bytes_this_cycle;
		buffer+=bytes_this_cycle;
	}
	*byteswritten = bytes;

	//printf("wend\n");
	return translateStatus(res);
}

enum SimpleFileStatus file_write_flush()
{
	if (write_pending >= 0)
	{
		//printf("wflush\n");
		disk_writeflush();
		write_pending = -1;
	}
	return SimpleFile_OK;
}

enum SimpleFileStatus file_seek(struct SimpleFile * file, int offsetFromStart)
{
	FRESULT res;

	int location = offsetFromStart>>9;
	if (write_pending >=0 && write_pending != offsetFromStart)
	{
		//printf("flush on seek\n");
		file_write_flush();
	}

	file_check_open(file);

	res = pf_lseek(offsetFromStart);
	return translateStatus(res);
}

int file_size(struct SimpleFile * file)
{
	return file->size;
}

int file_readonly(struct SimpleFile * file)
{
	return file->is_readonly;
}

int file_struct_size()
{
	return sizeof(struct SimpleFile);
}

enum SimpleFileStatus file_open_name_in_dir(struct SimpleDirEntry * entry, char const * filename, struct SimpleFile * file)
{
	file_write_flush();

	while (entry)
	{
		//printf("%s ",entry->filename_ptr);
		if (0==stricmp(filename,entry->filename_ptr))
		{
			return file_open_dir(entry, file);
		}
		entry = entry->next;
	}

	return SimpleFile_FAIL;
}

enum SimpleFileStatus file_open_name(char const * path, struct SimpleFile * file)
{
	char dirname[MAX_DIR_LENGTH];
	char const * filename = file_of(path);
	dir_of(&dirname[0], path);

	file_write_flush();

	//printf("filename:%s dirname:%s ", filename,&dirname[0]);

	struct SimpleDirEntry * entry = dir_entries(&dirname[0]);
	return file_open_name_in_dir(entry,filename, file);
}

enum SimpleFileStatus file_open_dir(struct SimpleDirEntry * dir, struct SimpleFile * file)
{
	FRESULT res;

	strcpy(&file->path[0],dir->path);
	file->is_readonly = dir->is_readonly;
	file->size = dir->size;

	file_write_flush();

	res = pf_open(&file->path[0]);
	openfile = file;

	return translateStatus(res);
}

enum SimpleFileStatus dir_init(void * mem, int space)
{
	FRESULT fres;
	DSTATUS res;

	write_pending = -1;

	//printf("dir_init\n");

	dir_cache = mem;
	dir_cache_size = space;

	//printf("disk_init go\n");
	res = disk_initialize();
	//printf("disk_init done\n");
	if (res!=RES_OK) return translateDStatus(res);

	//printf("pf_mount\n");
	fres = pf_mount(&fatfs);
	//printf("pf_mount done\n");

	return translateStatus(fres);
}

// Read entire dir into memory (i.e. give it a decent chunk of sdram)
struct SimpleDirEntry * dir_entries(char const * dirPath)
{
	return dir_entries_filtered(dirPath,0);
}

int dircmp(struct SimpleDirEntry * a, struct SimpleDirEntry * b)
{
	if (a->is_subdir==b->is_subdir)
		return strcmp(a->lfn,b->lfn);
	else
		return a->is_subdir<b->is_subdir;
}

void sort_ll(struct SimpleDirEntry * h)
{
//struct SimpleDirEntry
//{
//	char path[MAX_PATH_LENGTH];
//	char * filename_ptr;
//	int size;
//	int is_subdir;
//	struct SimpleDirEntry * next; // as linked list - want to allow sorting...
//};

	struct SimpleDirEntry * p,*temp,*prev;
	int i,j,n,sorted=0;
	temp=h;
	prev=0;
	for(n=0;temp!=0;temp=temp->next) n++;

	for(i=0;i<n-1 && !sorted;i++){
		p=h;sorted=1;
		prev=0;
		for(j=0;j<n-(i+1);j++){
	//		printf("p->issubdir:%d(%s) p->next->issubdir:%d(%s)",p->is_subdir,p->path,p->next->is_subdir,p->next->path);

			if(dircmp(p,p->next)>0) {
	//			printf("SWITCH!\n");
				struct SimpleDirEntry * a = p;
				struct SimpleDirEntry * b = p->next;
				a->next=b->next;
				b->next=a;
				if (prev)
					prev->next=b;
				p=b;

				sorted=0;
			}
			prev=p;
			p=p->next;
		}
	}

	//temp=h;
	//for(n=0;temp!=0;temp=temp->next) printf("POST:%s\n",temp->path);
}

struct SimpleDirEntry * dir_entries_filtered(char const * dirPath,int(* filter)(struct SimpleDirEntry *))
{
	int room = dir_cache_size/sizeof(struct SimpleDirEntry);

	file_write_flush();

	//printf("opendir ");
	if (FR_OK != pf_opendir(&dir,dirPath))
	{
		//printf("FAIL ");
		return 0;
	}
	//printf("OK ");

	struct SimpleDirEntry * prev = (struct SimpleDirEntry *)dir_cache;
	strcpy(prev->path,"..");
	strcpy(prev->lfn,"..");
	prev->filename_ptr = prev->path;
	prev->size = 0;
	prev->is_subdir = 1;
	prev->is_readonly = 1;
	prev->next = 0;
	--room;

	//int count=0;
	struct SimpleDirEntry * entry = prev + 1;
	while (room && FR_OK == pf_readdir(&dir,&filinfo) && filinfo.fname[0]!='\0')
	{
		char * ptr;

		if (filinfo.fattrib & AM_SYS)
		{
			continue;
		}
		if (filinfo.fattrib & AM_HID)
		{
			continue;
		}

		//printf("next %x %d ",entry,room);

		entry->is_subdir = (filinfo.fattrib & AM_DIR) ? 1 : 0;
		entry->is_readonly = (filinfo.fattrib & AM_RDO) ? 1 : 0;

		//printf("%s ",filinfo.fname);

		strcpy(&entry->path[0],dirPath);
		ptr = &entry->path[0];
		ptr += strlen(&entry->path[0]);
		*ptr++ = '/';
		entry->filename_ptr = ptr;
		strcpy(ptr,filinfo.fname);
		entry->size = filinfo.fsize;

		//printf("LFN:%s\n",&filinfo.lfname[0]);
		strcpy(&entry->lfn[0],&filinfo.lfname[0]);

		//int count;
		//printf("%d %s %s\n",count++, filinfo.fname, filinfo.lfname);


		if (filter && !filter(entry))
		{
			continue;
		}

		entry->next = 0;

		if (prev)
			prev->next = entry;
		prev = entry;
		entry++;
		room--;

		//printf("n %d %d %x ",filinfo.fsize, entry->size, entry->next);
	}

	//printf("dir_entries done ");

	/*struct SimpleDirEntry * begin = (struct SimpleDirEntry *) dir_cache;
	int count = 0;
	while (begin)
	{
		printf("%d %s\n",count++, begin->path);
		begin = begin->next;
	}*/

	if (filter)
	{
		sort_ll((struct SimpleDirEntry *) dir_cache);
	}
	return (struct SimpleDirEntry *) dir_cache;
}

char const * dir_path(struct SimpleDirEntry * entry)
{
	return &entry->path[0];
}

char const * dir_filename(struct SimpleDirEntry * entry)
{
	//return entry->filename_ptr;
	return &entry->lfn[0];
}

int dir_filesize(struct SimpleDirEntry * entry)
{
	return entry->size;
}

struct SimpleDirEntry * dir_next(struct SimpleDirEntry * entry)
{
	return entry->next;
}

int dir_is_subdir(struct SimpleDirEntry * entry)
{
	return entry->is_subdir;
}


