// boot_rom.c
// Boot ROM for the Z80 system on a chip (SoC)
// (c) 2016 Till Harbaum

// https://github.com/adamdunkels/uip


#include "uip.h"
#include "uip_arp.h"
#include "timer.h"

#include <stdio.h>
#include <string.h>

extern unsigned char font[];

unsigned char cur_x=0, cur_y=0;
void putchar(char c) {
  unsigned char *p;
  unsigned char *dptr = (unsigned char*)(160*(8*cur_y) + 8*cur_x);
  char i, j;

  if(c < 32) {
    if(c == '\r') 
      cur_x=0;

    if(c == '\n') {
      cur_y++;
      cur_x=0;

      if(cur_y >= 12)
	cur_y = 0;
    }
    return;
  }

  if(c < 0) return;

  p = font+8*(unsigned char)(c-32);
  for(i=0;i<8;i++) {
    unsigned char l = *p++;
    for(j=0;j<8;j++) {
      *dptr++ = (l & 0x80)?0xff:0x00;
      l <<= 1;
    }
    dptr += (160-8);
  }

  cur_x++;
  if(cur_x >= 20) {
    cur_x = 0;
    cur_y++;

    if(cur_y >= 12)
      cur_y = 0;
  }
}

void cls(void) {
  unsigned char i;
  unsigned char *p = (unsigned char*)0;

  for(i=0;i<100;i++) {
    memset(p, 0, 160);
    p+=160;
  }
  cur_x = 0;
  cur_y = 0;
}

// use vblank as a basis of the uip timer
volatile clock_time_t clock;
void isr(void) __interrupt {
  clock++;
  
  __asm
    ei    
  __endasm;
}

clock_time_t clock_time(void) {
  return clock;
}

void ei() {
  // set interrupt mode 1 and enable interrupts
  __asm
    im 1
    ei    
  __endasm;
}

/*---------------------------------------------------------------------------*/
__sfr __at 0x00 eth_cmd_status;  // write command, read status
__sfr __at 0x01 eth_len_hi;
__sfr __at 0x02 eth_len_lo;
__sfr __at 0x03 eth_data;

__sfr __at 0x10 eth_mac5;
__sfr __at 0x11 eth_mac4;
__sfr __at 0x12 eth_mac3;
__sfr __at 0x13 eth_mac2;
__sfr __at 0x14 eth_mac1;
__sfr __at 0x15 eth_mac0;

void eth_wait() {
  u8_t i;
  struct uip_eth_addr addr;

  printf("Wait for ETH ...\r");

  // wait for eth ready flag
  while(!(eth_cmd_status & 0x80));

  // read mac address from hardware ...
  addr.addr[0] = eth_mac0;
  addr.addr[1] = eth_mac1;
  addr.addr[2] = eth_mac2;
  addr.addr[3] = eth_mac3;
  addr.addr[4] = eth_mac4;
  addr.addr[5] = eth_mac5;

  // ... display it ...
  printf(" ");
  for(i=0;i<6;i++) {
    printf("%02x", addr.addr[i]);
    if(i<5) printf(":");
    else    printf("\n\n");
  }

  // ... and tell uip about it
  uip_setethaddr(addr);
}

u16_t eth_read() {
  u16_t cnt;
  u8_t *p = uip_buf;
  u16_t rx_len;

  // nothing to receive?
  if(!(eth_cmd_status & 1))
    return 0;

  // reading length also resets the rx buffer
  rx_len = (eth_len_hi << 8) + eth_len_lo;

  // read all bytes from buffer
  for(cnt = 0;cnt<rx_len;cnt++) 
    *p++ = eth_data;
  
  // acknowledge reception
  eth_cmd_status = 0x02;

  return rx_len;
}

void eth_send() {
  u16_t cnt;
  u8_t *p = uip_buf;
  
  // wait until TX buffer is free
  while(eth_cmd_status & 2);

  // writing length also resets TX buffer
  eth_len_hi = uip_len >> 8;
  eth_len_lo = uip_len & 0xff;

  // send all bytes to io controller
  for(cnt = 0;cnt<uip_len;cnt++) 
    eth_data = *p++;
  
  // and request transmission
  eth_cmd_status = 0x01;
}

/*---------------------------------------------------------------------------*/
#define BUF ((struct uip_eth_hdr *)&uip_buf[0])

void
main(void)
{
  int i;
  uip_ipaddr_t ipaddr;
  struct timer periodic_timer, arp_timer;
  int rx_cnt = 0, tx_cnt = 0;

  ei();
  cls();
  puts(" << Z80 SoC Net >>");
  
  // it takes some time for he ethernet to become ready as the io controller needs to
  // find the device on the USB and initialize it. Without ethernet dongle attached this
  // will wait forever
  eth_wait();

  timer_set(&periodic_timer, CLOCK_SECOND / 2);
  timer_set(&arp_timer, CLOCK_SECOND * 10);
  
  uip_init();

  uip_ipaddr(ipaddr, 192,168,0,2);
  puts("IP: 192.168.0.2");
  uip_sethostaddr(ipaddr);
  uip_ipaddr(ipaddr, 192,168,0,1);
  puts("GW: 192.168.0.1");
  uip_setdraddr(ipaddr);
  uip_ipaddr(ipaddr, 255,255,255,0);
  puts("MS: 255.255.255.0\n");
  uip_setnetmask(ipaddr);

  httpd_init();
  
  while(1) {
    printf("RX: %d TX: %d\r", rx_cnt, tx_cnt);

    uip_len = eth_read();
    if(uip_len > 0) {
      rx_cnt++;

      if(BUF->type == htons(UIP_ETHTYPE_IP)) {
	uip_arp_ipin();
	uip_input();
	/* If the above function invocation resulted in data that
	   should be sent out on the network, the global variable
	   uip_len is set to a value > 0. */
	if(uip_len > 0) {
	  uip_arp_out();
	  eth_send();
	  tx_cnt++;
	}
      } else if(BUF->type == htons(UIP_ETHTYPE_ARP)) {
	uip_arp_arpin();
	/* If the above function invocation resulted in data that
	   should be sent out on the network, the global variable
	   uip_len is set to a value > 0. */
	if(uip_len > 0) {
	  eth_send();
	  tx_cnt++;
	}
      }

    } else if(timer_expired(&periodic_timer)) {
      timer_reset(&periodic_timer);

      for(i = 0; i < UIP_CONNS; i++) {
	uip_periodic(i);
	/* If the above function invocation resulted in data that
	   should be sent out on the network, the global variable
	   uip_len is set to a value > 0. */
	if(uip_len > 0) {
	  uip_arp_out();
  	  eth_send();
	  tx_cnt++;
	}
      }

#if UIP_UDP
      for(i = 0; i < UIP_UDP_CONNS; i++) {
	uip_udp_periodic(i);
	/* If the above function invocation resulted in data that
	   should be sent out on the network, the global variable
	   uip_len is set to a value > 0. */
	if(uip_len > 0) {
	  uip_arp_out();
	  eth_send();
	  tx_cnt++;
	}
      }
#endif /* UIP_UDP */
      
      /* Call the ARP timer function every 10 seconds. */
      if(timer_expired(&arp_timer)) {
	timer_reset(&arp_timer);
	uip_arp_timer();
      }
    }
  }
}
