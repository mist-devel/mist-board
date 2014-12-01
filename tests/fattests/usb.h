/* dummy for fat tests */

extern uint8_t storage_devices;
extern unsigned char usb_storage_read(unsigned long lba, unsigned char *pReadBuffer);
extern unsigned char usb_storage_write(unsigned long lba, unsigned char *pWriteBuffer);
