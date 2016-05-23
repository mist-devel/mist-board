	AREA    |main|, CODE, READONLY
        EXPORT  _start

	ORG	&1000
_start
	;; setup the carry for the test
	;; could do this in program.cpp but
	;; doing this makes the test repeatable
	;; on a real Archie from BASIC V.
	MOV	R0,#0
	SUB	R1,R0,#1
	ADDS	R1,R1,#1
	;;Do the test
	MOV	R4,#&90000000
	MOV     R5,#&20000000
	CMP	R4,R5,RRX
	;; flag a result to BASIC/Program.cpp
	MOVCC	R0,#1
	MOVCS	R0,#0
EXIT
	;; clean exit path so that R15 will match up
	NOP	
	NOP	
	
	SWI	&FFFFFF

	NOP
	NOP
		
	END
