#include "utils.h"

int strcmp(char const * a, char const * b)
{
	while (*a || *b)
	{
		if (*a<*b)
			return -1;
		else if (*a>*b)
			return 1;

		++a;
		++b;
	}
	return 0;
}

int stricmp(char const * a, char const * b)
{
	char buffer[128];
	char buffer2[128];
	stricpy(&buffer[0],a);
	stricpy(&buffer2[0],b);
	return strcmp(&buffer[0],&buffer2[0]);
}

void strcpy(char * dest, char const * src)
{
	while (*dest++=*src++);
}

void stricpy(char * dest, char const * src)
{
	while (*src)
	{
		char val = *src++;
		if (val>='A' && val<='Z') val+=-'A'+'a';

		*dest++ = val;
	}
	*dest = '\0';
}

int strlen(char const * a)
{
	int count;
	for (count=0; *a; ++a,++count);
	return count;
}

