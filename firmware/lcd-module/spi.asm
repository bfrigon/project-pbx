;******************************************************************************
;*   Project:      PBX Front panel lcd                                        *
;*   Version:      0.1.1                                                      *
;*                                                                            *
;*   Filename:     spi.asm                                                    *
;*   Description:  SPI bus communication                                      *
;*   Last mod:     28 July 2012                                               *
;*                                                                            *
;*   Author:       Benoit Frigon                                              *
;*   Email:        <bfrigon@gmail.com>                                        *
;*                                                                            *
;******************************************************************************
include <p18f2520.inc>

#define PIN_SCK         LATC,  LATC3
#define PIN_SDO         LATC,  LATC5
#define PIN_SPI_CS0     LATB,  LATB3



;==============================================================================
;==============================================================================
;
;                                   Symbols 
;------------------------------------------------------------------------------
; *** Subroutines ***
GLOBAL  spi_init							; Initialize SPI bus
GLOBAL  spi_write							; Write to SPI bus
GLOBAL  mcp410xx_write						; Send command to MCP410xx

; *** External symbols import ***		
EXTERN  delay10tcy
EXTERN  delay1ktcy
		


;==============================================================================
;==============================================================================
;
;                                     Data   
;------------------------------------------------------------------------------
; *** Access bank ****
.a_spi			UDATA_ACS
char    		RES     0x01             	; Character buffer
value   		RES     0x01
i       		RES     0x01               	; Iteration counter



;==============================================================================
;==============================================================================
;
;                                Subroutines 
;------------------------------------------------------------------------------
.c_spi        	CODE

;******************************************************************************
; spi_init : Initialize SPI bus
;
; Arguments : None
; Return	: None
;******************************************************************************        
spi_init:

        bcf     PIN_SCK
        nop
        
        bcf     PIN_SDO
        bsf     PIN_SPI_CS0					; Disable device 0 select
        
        clrf    SSPCON1
    
        return
        

;******************************************************************************
; spi_init : Send data over SPI bus
;
; Arguments : W= Data to send
; Return	: None
;******************************************************************************        
spi_write:
        movwf   char						; Move W to character buffer

        movlw   D'8'						; 8 bits to send
        movwf   i

loop_spi_write:
        bcf     PIN_SCK						; Reset clock
        nop
        
        bcf     PIN_SDO						; Reset DATA OUT pin

        bcf     STATUS, C					; Clear carry flag
        
        rlcf    char, F						; Shift 1 bit out to the right

        btfsc   STATUS, C					; Set DATA OUT pin high if bit=1
        bsf     PIN_SDO
        
        movlw   D'1'						; Wait 5us
        rcall   delay10tcy

        bsf     PIN_SCK						; Trigger clock (low-to-high)
        
        movlw   D'1'						; Wait 5us
        rcall   delay10tcy
        
        decfsz  i, f	
        bra     loop_spi_write				; loop until all bits are sent
        
        return        


;******************************************************************************
; mcp410xx_write : Send command to MCP410xx device
;
; Arguments : None
; Return	: None
;******************************************************************************        
mcp410xx_write:
        movwf   value

        bcf     PIN_SPI_CS0 				; Enable device 0 select
        
        movlw   D'1'						; wait 0.5ms
        rcall   delay1ktcy
        
        movlw   0x11						; Write command 0x11
        									; C=01 (Write data)
        									; P=01 (Potentiometer 0)
        rcall   spi_write
        
        movf    value, W					; Write potentiometer value
        rcall   spi_write

        movlw   D'2'						; wait 1ms
        rcall   delay1ktcy
        
        bsf     PIN_SPI_CS0 				; Disable device 0 select

        return


;==============================================================================
;==============================================================================
        END
		
		
