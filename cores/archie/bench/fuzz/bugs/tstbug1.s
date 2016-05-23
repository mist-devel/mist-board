	AREA    |main|, CODE, READONLY
        EXPORT  _start

	ORG	&1000
_start
	; set the carry up 
	MOV R1,#0xFFFFFFFF 
	ADDS R1,R1,#1 
	; do the test 
	MOV R1,#0x00800000 
	TST R1,#0x00FF0000 

	MOVCC R0,#0 
	MOVCS R0,#1 
	
	NOP
	NOP
	
	SWI	&FFFFFF

	NOP
	NOP

	END
