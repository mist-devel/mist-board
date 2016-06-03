/* conv.c

 Copyright (c) 2015, Stephen J. Leary
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the <organization> nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

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
