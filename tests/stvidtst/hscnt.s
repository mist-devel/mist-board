	;; Hsync count test. Visualizes the relationship between
	;; hsync and vsync on a atari st
	;; (c) 2015 by Till Harbaum <till@harbaum.org>

start:
        	move.l  #msg,-(sp)              ; 
                move.w  #9,-(sp)                ; CConws
                trap    #1                      ; gemdos
                addq.l  #6,sp

		pea	do_test
		move.w	#38,-(sp) 		; Supexec	
		trap	#14			; xbios
		addq.l	#6,sp

do_test:
		move.w 	#$2700,sr
		move.l	#new_vbi,$70
		move.l	#new_hbi,$68

		move.b  #0,$FFFA07
		move.b  #0,$FFFA09
	
		move.w 	#$2100,sr

forever:	bra.s	forever
	
line_cnt:	dc.w	0
	
new_vbi:        move.w  #$474,$FF8240 ; green
		clr.w	line_cnt
		rte

new_hbi:	add.w	#$1,line_cnt
		cmp.w 	#102,line_cnt
		bne	hbi_done
		move.w  #$744,$FF8240 ; red
		rte
	
hbi_done:	move.w  #$447,$FF8240 ; blue
		rte

msg:	dc.b	"HSYNC count test!", 13,10,10,10,10
	dc.b    "Red line is exactly below this text!", 13, 10, 10, 10
	dc.b    "Color change under the word 'line'", 13, 10, 0
	even
