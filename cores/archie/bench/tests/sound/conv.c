#include <stdio.h>
#include <stdlib.h>

int main (int argc, char **argv)
{
    unsigned char wp;
    while (fread(&wp,sizeof(unsigned char),1,stdin) > 0)
    {
	/*
	 * In the following loop we convert 4 bytes at once because
	 * it's all pure bit twiddling: there is no arithmetic to
	 * cause overflow/underflow or other such nasty effects.  Each
	 * byte is converted using the algorithm:
	 *
	 *   output = ~(((input >> 7) & 0x01) | 
	 *              ((input << 1) & 0xFE)  )
	 *
	 * i.e. we rotate the byte left by 1 then bitwise complement
	 * the result.  On ARM the actual conversion (not including
	 * the load & store) works out to take all of 4 S-cycles, and
	 * since we are doing 4 bytes at once this really ain't bad!
	 * Note that we don't worry about alignment on any odd bytes
	 * at the end of the buffer (unlikely anyway), we just convert
	 * all 4 bytes - the right number still get written.
	 */
	unsigned int xm = 0x01010101;

	unsigned char ss = wp;
	wp = ~(((ss >> 7) & xm) | (~xm & (ss << 1)));

	
	fwrite(&wp,sizeof(unsigned char),1,stdout);
    }

    return 0;
}
