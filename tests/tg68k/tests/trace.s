	;; trace trap tests

	;; musashi 68000
	;mem_write(0x000103fe,3) = 0106
	;mem_write(0x000103fc,3) = 0000
	;mem_write(0x000103fa,3) = a700
	
	;; tg68k 68000:
	;mem_write(0x000103fe,3) = 0106
	;mem_write(0x000103fc,3) = 0000
	;mem_write(0x000103fa,3) = a700
	
	;; musashi 68020    ; six word stack frame format 2
	;mem_write(0x000103fe,3) = 0104
	;mem_write(0x000103fc,3) = 0000
	;mem_write(0x000103fa,3) = 2024 ; how much more bytes to read
	;mem_write(0x000103f8,3) = 0106
	;mem_write(0x000103f6,3) = 0000
	;mem_write(0x000103f4,3) = a700 ; start reading stack from here

	;; hack
	;mem_write(0x000103fe,3) = 0104
	;mem_write(0x000103fc,3) = 0000
	;mem_write(0x000103fa,3) = 2024
	;mem_write(0x000103f8,3) = 0106
	;mem_write(0x000103f6,3) = 0000
	;mem_write(0x000103f4,3) = a700
	
	;; tg68k 68020:     ; four word stack frame format 0
	;mem_write(0x000103fe,3) = 0024 ;
	;mem_write(0x000103fc,3) = 0106
	;mem_write(0x000103fa,3) = 0000 ; pc
	;mem_write(0x000103f8,3) = a700 ; sr

        move    #$a700,sr             ; Enter trace mode t0
        nop                          ;

	bra	cont

trace_trap:
	rte

cont:	
