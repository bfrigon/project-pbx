;******************************************************************************
;*   Project:      PBX Front panel lcd                                        *
;*   Version:      0.1.1                                                      *
;*                                                                            *
;*   Filename:     macro.asm                                                  *
;*   Description:  Macro                                                      *
;*   Last mod:     16 sept. 2012                                              *
;*                                                                            *
;*   Author:       Benoit Frigon                                              *
;*   Email:        <bfrigon@gmail.com>                                        *
;*                                                                            *
;******************************************************************************



;******************************************************************************
; jmpif : Test register, branch to label if equal to value
;
; Arguments 
;	- reg : Register to test
;	- value : value to compare the register with
;	- label : Jump to label if equal

;******************************************************************************
jmpif	MACRO	reg, value, label
		
		movf	reg, W
		xorlw	value
		btfsc	STATUS, Z
		goto	label

		ENDM


;******************************************************************************
; ltblptr : Move literal to table pointer
;
; Arguments 
;	- address : 21-bit address

;******************************************************************************
ltblptr	MACRO	address
		movlw		low(address)
		movwf		TBLPTRL
		movlw		high(address)
		movwf		TBLPTRH
		movlw		upper(address)
		movwf		TBLPTRU		

		ENDM


;******************************************************************************
; addff16 : 16-bit add operation, the result of the addition is stored in
;		    the file register X1 and Y1
;
; Arguments 
;	- x0 : Lower 8 bit multiplicator
;	- y0 : Lower 8 bit base
;	- x1 : Higer 8 bit multiplicator
;	- y1 : Higer 8 bit base

;******************************************************************************
addff16	MACRO	x0, x1, y0, y1
		movf	x0, W
		addwf	y0, F
		movf	x1, W
		btfsc	STATUS, C
		incfsz	x1, W
		addwf	y1, F
		
		ENDM

