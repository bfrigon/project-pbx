;******************************************************************************
;*   Project:      PBX Front panel lcd                                        *
;*   Version:      0.1.1                                                      *
;*                                                                            *
;*   Filename:     usart.asm                                                  *
;*   Description:  USART module                                               *
;*   Last mod:     28 July 2012                                               *
;*                                                                            *
;*   Author:       Benoit Frigon                                              *
;*   Email:        <bfrigon@gmail.com>                                        *
;*                                                                            *
;******************************************************************************
include <p18f2520.inc>
        

;==============================================================================
;==============================================================================
;
;                                   Symbols 
;------------------------------------------------------------------------------
; *** subroutines ***
GLOBAL  usart_init                          ; Initialize USART module
GLOBAL  usart_isr                           ; ISR routine
GLOBAL  usart_read_buffer                   ; Read next char from RX buffer
GLOBAL  usart_write_byte                    ; Send character
GLOBAL  usart_buffer_len                    ; Get buffer length



;==============================================================================
;==============================================================================
;
;                                    Data
;------------------------------------------------------------------------------
; *** Access bank ***
.a_usart        UDATA_ACS
w_ptr           RES     0x01                ; Buffer write ptr
r_ptr           RES     0x01                ; Buffer read ptr
rx_chr          RES     0x01                ; Character (temp)
prev_FSR2L      RES     0x01                ; Previous FSR2L value on int.

; *** RAM ***
.b_usart        UDATA
rx_buffer       RES     0x100               ; Buffer



;==============================================================================
;==============================================================================
;
;                                Subroutines 
;------------------------------------------------------------------------------
.c_usart        CODE
        


;******************************************************************************
; usart_init : Initialize the USART module
;
; Arguments : None
; Return    : None
;******************************************************************************
usart_init:

        clrf    BAUDCON                     ; TX idle high
        bsf     BAUDCON, BRG16              ; 16-bit baud rate generator

        movlw   D'12'                       ; 38400 bps 
        movwf   SPBRG                       ; 8Mhz/(16(12+1)) = 38461.538461538
        clrf    SPBRGH                      ; (+0.2% error)

        bsf     PIE1, RCIE                  ; Enable Receive interrupt

        clrf    TXSTA                       ; 8-bit, async mode, low speed
        bsf     TXSTA, TXEN                 ; Enable transmitter
        
        clrf    RCSTA                       ; 8-bit
        bsf     RCSTA, CREN                 ; Continous receive enabled
        bsf     RCSTA, SPEN                 ; Enable serial port


        lfsr    FSR2, rx_buffer+0           ; 
        clrf    w_ptr
        clrf    r_ptr
        

        return


;******************************************************************************
; usart_write_byte : Send character over USART
;
; Arguments : W= Character to write
; Return    : None
;******************************************************************************
usart_write_byte:
        btfss   PIR1, TXIF                  ; Wait for xmit buffer to empty
        bra     usart_write_byte
        movwf   TXREG                       ; Send the byte

        return        


;******************************************************************************
; usart_read_buffer : Read the next available character in the buffer
;
; Arguments : None
; Return    : W= Character read
;******************************************************************************
usart_read_buffer:
        movf    r_ptr,  W                   ; Block until a character is
        xorwf   w_ptr,  W                   ; available
        btfsc   STATUS, Z
        bra     usart_read_buffer

        movff   r_ptr, FSR2L                
        movf    INDF2, W                    ; Read the character from the 
                                            ; buffer
        
        incf    r_ptr, F                    ; Increment read pointer

        return
        

;******************************************************************************
; usart_buffer_len : Return the length of the buffer
;
; Arguments : None
; Return    : W= Buffer length
;******************************************************************************
usart_buffer_len:
        movf    w_ptr,  W                   ; Subtract write ptr from read ptr
        subwf   r_ptr,  W
        return
                        


;******************************************************************************
; usart_isr : Interrupt service routine for USART receive 
;
; Arguments : None
; Return    : None
;******************************************************************************
usart_isr:
        movff   FSR2L, prev_FSR2L           ; Save FSR2L in case it was in
                                            ; use before the interrupt was
                                            ; raised.

        movff   RCREG, rx_chr
        
        incf    w_ptr, W                    ; Check if w_ptr+1 = r_ptr
        xorwf   r_ptr, W
        btfsc   STATUS, Z                   ; If so, the buffer is full
        retfie  S                           ; ignore the character
        
        movff   w_ptr, FSR2L                ; Write character to buffer
        movff   rx_chr, INDF2
        incf    w_ptr, F                    ; Increment write pointer

        movff   prev_FSR2L, FSR2L           ; Restore FSR2L
        
        return
        
        
;==============================================================================
;==============================================================================
        END
        
