/* dummy for fat tests */

#define iprintf(a, ...) printf(a, ##__VA_ARGS__)
char BootPrint(const char *text);
void ErrorMessage(const char *message, unsigned char code);
