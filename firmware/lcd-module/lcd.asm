;******************************************************************************
;*   Project:      PBX Front panel lcd                                        *
;*   Version:      0.1.1                                                      *
;*                                                                            *
;*   Filename:     lcd.asm                                                    *
;*   Description:  LCD interface communication                                *
;*   Last mod:     15 july 2013                                               *
;*                                                                            *
;*   Author:       Benoit Frigon                                              *
;*   Email:        <bfrigon@gmail.com>                                        *
;*                                                                            *
;******************************************************************************
include <p18f2520.inc>
include "macro.inc"


; *** Pin assignment ***
#define PIN_ENABLE          LATC,   LATC1
#define TRIS_ENABLE         TRISC,  TRISC1
#define PIN_RW              LATC,   LATC4
#define TRIS_RW             TRISC,  TRISC4
#define PIN_RS              LATC,   LATC0
#define TRIS_RS             TRISC,  TRISC0
#define PORT_DATA           PORTA
#define TRIS_DATA           TRISA

; *** LCD op codes ***
#define OP_CLEAR            0x01
#define OP_RTNHOME          0x02
#define OP_MODE             0x04
#define OP_DISPLAY          0x08
#define OP_CURSOR           0x10
#define OP_FUNCTION         0x20
#define OP_CGRAM            0x40
#define OP_DDRAM            0x80

; *** Transition types ***
#define TRANS_CUR           0x00
#define TRANS_SLIDE_RIGHT   0x10
#define TRANS_SLIDE_LEFT    0x11



;==============================================================================
;==============================================================================
;
;                                   Symbols 
;------------------------------------------------------------------------------
; *** Subroutines ***
GLOBAL  lcd_clear                           ; Clear LCD
GLOBAL  lcd_clear_to                        ; Clear LCD from cursor to pos x
GLOBAL  lcd_clear_pages                     ; Clear all pages
GLOBAL  lcd_goto                            ; Move cursor to position x
GLOBAL  lcd_init                            ; Initialize LCD
GLOBAL  lcd_write                           ; Write character to buffer
GLOBAL  lcd_set_page                        ; Set buffer page pointer
GLOBAL  lcd_show_page                       ; Set visible page
GLOBAL  lcd_offset_pos                      ; Offset cursor position
GLOBAL  lcd_set_display                     ; Set display mode
GLOBAL  lcd_save_pos                        ; Save current cursor position
GLOBAL  lcd_restore_pos                     ; Restore previous cursor position
GLOBAL  lcd_write_page                      ; Write to buffer page
GLOBAL  lcd_read_page                       ; Read from buffer page
GLOBAL  lcd_write_cgram                     ; Write custom character to CGRAM
GLOBAL  lcd_save_cgram_table                ; Save custom characters table
                                            ; to EEPROM
GLOBAL  lcd_load_cgram_table                ; Load custom characters table
                                            ; from EEPROM

; *** Variables ***
GLOBAL  lcd_trans_type                      ; Transition type
GLOBAL  lcd_trans_speed                     ; Transition speed
GLOBAL  lcd_bptr                            ; Current buffer position
        
; *** External symbols import ***        
EXTERN  delay100tcy
EXTERN  delay10tcy
EXTERN  delay1ktcy
EXTERN  delay10ktcy

EXTERN  read_eeprom
EXTERN  write_eeprom



;==============================================================================
;==============================================================================
;
;                                     Data   
;------------------------------------------------------------------------------
; Access bank
.a_lcd          UDATA_ACS
lcd_trans_type  RES     0x01                ; Transiton type
lcd_trans_speed RES     0x01                ; Transition speed
saved_pos       RES     0x01                ; Saved cursor position
cur_page        RES     0x01                ; Current visible page
lcd_bptr        RES     0x01                ; Current buffer ptr
prev_bptr       RES     0x01                ; Previous buffer ptr
cur_mode        RES     0x01                ; Current display mode
char            RES     0x01                ; Character buffer
i               RES     0x01                ; Iteration counter
temp            RES     0x01                ; Temporary data

; Bank
.b_lcd          UDATA
lcd_buffer      RES     0x100               ; LCD buffer



;==============================================================================
;==============================================================================
;
;                                Subroutines 
;------------------------------------------------------------------------------
.c_lcd          CODE
                
;******************************************************************************
; lcd_goto : Move cursor to position X.
;
; Arguments : W= position ; (Row1=0x00-0x0F, Row2=0x10-0x1F)
; Return    : None
;******************************************************************************
lcd_goto:


        ;--------------------------------
        ; Buffer pointer bits :
        ; [ppp][r][cccc]
        ; p = page id (0-7)
        ; r = row number (0-1)
        ; c = column number (0-15)
        ;--------------------------------
        
        movff   lcd_bptr, prev_bptr         ; Save previous buffer ptr
        
        andlw   0x1F                        ; Mask out page id from the
        movwf   lcd_bptr                    ; new buffer pointer
        
        movf    prev_bptr, W                ; Get page id from the previous
        andlw   0xE0                        ; buffer pointer
        
        addwf   lcd_bptr                    ; Add prev. page id to new pointer
        

        cpfseq  cur_page                    ; if current page is not visible,
        return                              ; return
        
        ;--------------------------------
        ; Set new cursor position on LCD        
        ;--------------------------------
        movlw   0x1F                        ; Mask page id from new buffer
        andwf   lcd_bptr, W                 ; pointer
        
        btfsc   WREG, 4                     ; if address = 16,
        addlw   0x30                        ; set DDRAM on second row

        addlw   OP_DDRAM                    ; Set DDRAM command (0x80)
        rcall   lcd_send_cmd                ; Send command to LCD
        
        return


;******************************************************************************
; lcd_offset_pos : Offset cursor position by X.
;
; Arguments : W= Number of characters (> 0 : move right, < 0 : Left)
; Return    : None
;******************************************************************************
lcd_offset_pos:
        addwf   lcd_bptr, W                 ; Add WREG to current buffer ptr
        andlw   0x1F

        rcall   lcd_goto                    ; Set new position
        
        return


;******************************************************************************
; lcd_set_page : Set buffer page.
;
; Arguments : W= Page ID
; Return    : None
;******************************************************************************
lcd_set_page:
        mullw   D'32'                       ; Set buffer ptr to page X
        movff   PRODL, lcd_bptr             ; boundary
        
        movlw   D'0'                        ; Set position to 0,0
        rcall   lcd_goto
        return



;******************************************************************************
; lcd_set_page : Set visible page.
;
; Arguments : W= Page ID
;             lcd_trans_type= Type of transition to use
;             lcd_trans_speed= Delay between transition step
;
; Return    : None
;******************************************************************************
lcd_show_page:
        mullw   D'32'                       ; Set current page
        movff   PRODL, cur_page
        movff   PRODL, lcd_bptr
        
        movlw   OP_DISPLAY + 0x04           ; Hide cursor during the
        rcall   lcd_send_cmd                ; transition
        
        jmpif   lcd_trans_type, TRANS_SLIDE_RIGHT, trans_slide
        jmpif   lcd_trans_type, TRANS_SLIDE_LEFT, trans_slide
        bra     trans_cut


trans_done:
        movlw   OP_DDRAM + 0x00             ; Move LCD cursor back to 0,0
        rcall   lcd_send_cmd

        movf    cur_mode, W                 ; Restore previous display mode
        addlw   OP_DISPLAY
        rcall   lcd_send_cmd
        
        return

;------------------------------------------------------------------------------
; Transition : Cut
;------------------------------------------------------------------------------
trans_cut:
        movlw   0x00                        ; Copy new buffer page in place
        rcall   lcd_dump_buffer 

        bra     trans_done

;------------------------------------------------------------------------------
; Transition : Slide
;------------------------------------------------------------------------------
trans_slide:
        ;--------------------------------
        ; Visible address range on LCD is 
        ; 00-0F (first row) and 40-4F 
        ; (second row). To acheive the 
        ; slide effect, we dump the new 
        ; page outside the visible range
        ; and then shift the display 16 
        ; times.
        ;--------------------------------       

        movlw   0x10                        ; Set DDRAM address at 0x10 (right
                                            ; of visible range)

        btfsc   lcd_trans_type, 0           ; if direction is right, set DDRAM 
        addlw   0x08                        ; at 0x18 (left of visible range)

        rcall   lcd_dump_buffer             ; Copy the new page to this address


        movlw   D'16'                       ; Shift the display 16 times
        movwf   i

loop_shift:
        movlw   OP_CURSOR                   ; Cursor opcode (0x10)
        bsf     WREG, 3                     ; Set display shift=on (bit 3)
                                            ; shift to left by default

        btfsc   lcd_trans_type, 0           ; if direction is right, set shift
        bsf     WREG, 2                     ; to right bit (2).

        rcall   lcd_send_cmd                ; Shift the display

        movf    lcd_trans_speed, W          ; if speed = 0, set speed to 5
        btfsc   STATUS, Z

        movlw   D'5'                        ; delay : speed x 5ms
        call    delay10ktcy
        
        decfsz  i
        bra     loop_shift
        
        ;--------------------------------       
        ; Once the transition is over, 
        ; the entire display has been 
        ; shifted and previous page is 
        ; now hidden. We then copy the 
        ; new page over the previous one 
        ; at the origin (0x00) and then 
        ; shift the display back to it's 
        ; original position.
        ;--------------------------------       
        
        movlw   0x00                        ; Copy new page to origin
        rcall   lcd_dump_buffer
        
        movlw   OP_RTNHOME                  ; Reset the LCD shift position
        rcall   lcd_send_cmd                
        
        movlw   D'50'                       ; 2.5ms delay to allow last
        rcall   delay100tcy                 ; instruction to complete.
        
        bra     trans_done


;******************************************************************************
; lcd_dump_buffer : Transfert page from buffer to LCD.
;
; Arguments : W= Address of LCD DDRAM where to dump the buffer.
; Return    : None
;******************************************************************************
lcd_dump_buffer:
        movwf   temp                        ; Save start address

        addlw   OP_DDRAM                    ; Set DDRAM address on LCD
        rcall   lcd_send_cmd
        
        lfsr    FSR1, lcd_buffer+0          ; Point FSR1 to buffer base
        movff   lcd_bptr, FSR1L             ; Point FSR1 to new page
        
        movlw   D'32'                       ; 32 characters to transfer
        movwf   i   

loop_write_char:
        movf    POSTINC1, W                 ; Read next character from buffer
        rcall   lcd_send_data               ; Send the character to LCD

        movlw   0xF                         ; check if buffer is on a new row
        andwf   FSR1L, W
        btfss   STATUS, Z
        bra     no_line_change
        
        movf    temp, W                     ; Set DDRAM address on LCD to 
        addlw   0x40                        ; start + 0x40 (next row)
        andlw   0x7F
        addlw   OP_DDRAM
        rcall   lcd_send_cmd

no_line_change:
        decfsz  i                           
        bra     loop_write_char             ; loop until all characters are
                                            ; written
        return



;******************************************************************************
; lcd_clear : Clear all pages
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_clear_pages:
        lfsr    FSR1, lcd_buffer+0          ; Set FSR1 ptr to buffer

        clrf    i                           ; 256 characters to clear
                
loop_clear_buffer:
        movlw   0x20                        ; Fill buffer with spaces (0x20)
        movwf   POSTINC1
        
        decfsz  i
        bra     loop_clear_buffer           ; loop until buffer is cleared
        

        clrf    cur_page                    ; Reset current page and 
        clrf    lcd_bptr                    ; buffer pointer
        
        movlw   OP_CLEAR                    ; Send clear instruction to LCD
        rcall   lcd_send_cmd

        movlw   D'50'                       ; 2.5ms delay to allow last
        rcall   delay100tcy                 ; instruction to complete.
        
        return

        




;******************************************************************************
; lcd_clear : Fill the current buffer page with spaces (0x20) and clear the lcd
;             if the page is visible.
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_clear:
        movlw   0xE0                        ; Set buffer pointer to the origin
        andwf   lcd_bptr                    ; of the current page
        
        lfsr    FSR1, lcd_buffer+0          ; Point FSR1 to buffer base
        movff   lcd_bptr, FSR1L             ; Point FSR1 to current page

        movlw   D'32'                       ; 32 characters to send
        movwf   i
        
loop_clear_char:
        movlw   0x20                        ; Write a space character (0x20)
        movwf   POSTINC1                    ; to the buffer

        decfsz  i
        bra     loop_clear_char             ; loop until all character are
                                            ; cleared

        movf    lcd_bptr, W
        cpfseq  cur_page                    ; if current page is not visible,
        return                              ; return

        movlw   OP_CLEAR                    ; Send Clear instruction to LCD
        rcall   lcd_send_cmd
        
        movlw   D'50'                       ; 2.5ms delay to allow last
        rcall   delay100tcy                 ; instruction to complete.
        
        return


;******************************************************************************
; lcd_clear_to: Clear the lcd from cursor to specified position
;
; Arguments : W= Position
; Return    : None
;******************************************************************************
lcd_clear_to:
        andlw   0x1F
        movwf   i
        
        movlw   0xE0                        
        andwf   lcd_bptr, W
        addwf   i
        
        movf    i, W
        cpfslt  lcd_bptr
        bra     clr_left
        bra     clr_right
        
clr_left:
        movlw   D'-1'
        movwf   temp

        movlw   OP_MODE + 0x00              ; Set decrement cursor pos
        rcall   lcd_send_cmd
        
        bra     loop_clr

clr_right:
        movlw   D'1'
        movwf   temp

loop_clr:
        movlw   0x20
        rcall   lcd_send_data

        movf    temp, W                     ; increment or decrement buffer pos
        addwf   lcd_bptr
        
        swapf   temp, W                     
        xorwf   lcd_bptr, W
        andlw   0xF
        btfsc   STATUS, Z
        rcall   lcd_update_cursor

        movf    i, W
        cpfseq  lcd_bptr
        bra     loop_clr

        movlw   0x20
        rcall   lcd_send_data

        movff   i, lcd_bptr
        rcall   lcd_goto

        movlw   OP_MODE + 0x02              ; Restore default entry mode
        rcall   lcd_send_cmd                ; (increment cursor)

        return  


;******************************************************************************
; lcd_update_cursor : Set the position on the LCD that correspond to the 
;                     current buffer position
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_update_cursor:

        movlw   0xE0                        ; Check if the buffer is on a
        andwf   lcd_bptr, W                 ; visible page
        cpfseq  cur_page
        return                              ; if not, no need to update LCD

        movf    lcd_bptr, W
        andlw   0x1F
        
        rcall   lcd_goto

        return


;******************************************************************************
; lcd_write : Write a character to the current buffer page and send it to 
;             the lcd if the page is visible.
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_write:
        movwf   char
        
        jmpif   char, "\b", chr_backspace   
        jmpif   char, 0x7F, chr_backspace   
        jmpif   char, "\n", chr_newline     
        jmpif   char, "\r", chr_return
        jmpif   char, "\f", chr_formfeed


        lfsr    FSR1, lcd_buffer+0          ; Set FSR1 ptr to buffer
        movff   lcd_bptr, FSR1L             
        movff   char, INDF1                 ; Write character to the buffer
        
        
        movff   lcd_bptr, prev_bptr         ; Save previous buffer ptr

        incf    lcd_bptr, W                 ; Increment buffer ptr
        andlw   0x1F                        ; Make sure the buffer ptr remains
        movwf   lcd_bptr                    ; in the current page
        
        movf    prev_bptr, W                ; Get page id from previous ptr
        andlw   0xE0
        addwf   lcd_bptr                    ; Add to the new buffer ptr
        
        
        cpfseq  cur_page                    ; if current page is not visible,
        return                              ; return        
        
        movf    char, W                     ; Send character to the lcd
        rcall   lcd_send_data
        
        movf    lcd_bptr, W                 ; If the new buffer ptr is located
        andlw   0xF                         ; on the same row, return
        btfss   STATUS, Z
        return                              
        
        movf    lcd_bptr, W                 ; Move the LCD cursor to the new
        rcall   lcd_goto                    ; line
        return

;------------------------------------------------------------------------------
; Backspace character
;------------------------------------------------------------------------------
chr_backspace:
        movlw   D'-1'                       ; Move cursor to the left
        rcall   lcd_offset_pos
        
        movlw   0x20                        ; Clear the character at this
        rcall   lcd_write                   ; position

        movlw   D'-1'                       ; Move cursor to the left again
        rcall   lcd_offset_pos          
        
        return
        
;------------------------------------------------------------------------------
; New line (\n)
;------------------------------------------------------------------------------
chr_newline:
        movlw   D'16'                       ; Move buffer pointer down one row
        rcall   lcd_offset_pos
        return

;------------------------------------------------------------------------------
; Carriage return (\r)
;------------------------------------------------------------------------------
chr_return:
        movlw   0xF0                        ; move buffer pointer to the
        andwf   lcd_bptr, W                 ; start of the current row
        rcall   lcd_goto
        return

;------------------------------------------------------------------------------
; Form feed (\f)
;------------------------------------------------------------------------------
chr_formfeed:
        rcall   lcd_clear                   ; Clear the current buffer page
        return      


;******************************************************************************
; lcd_send  : Send command or data to the LCD.
;
; Arguments : W= Data to send
; Return    : None
;******************************************************************************
lcd_send:
        bsf     PIN_ENABLE                  ; Reset enable
        nop                                 ; Wait 0.5us
        
        movwf   PORT_DATA
        nop                                 ; Wait 0.5us
        
        bcf     PIN_ENABLE                  ; Set Enable (high-to-low)
        
        movlw   D'10'
        rcall   delay10tcy                  ; 50us delay
        
        return


;******************************************************************************
; lcd_send_data : Send data to the LCD.
;
; Arguments : W= Data to send
; Return    : None
;******************************************************************************
lcd_send_data:
        bsf     PIN_RS                      ; Set RS pin high (data mode)
        rcall   lcd_send
        
        return


;******************************************************************************
; lcd_send_cmd : Send instruction to the LCD.
;
; Arguments : W= Instruction to send
; Return    : None
;******************************************************************************
lcd_send_cmd:
        bcf     PIN_RS                      ; Set RS pin low (instruction mode)
        rcall   lcd_send
        
        return


;******************************************************************************
; lcd_rcv_data : Receive data from the LCD.
;
; Arguments : None
; Return    : W= Character read.
;******************************************************************************
lcd_rcv_data:
        bsf     PIN_RS                      ; Set RS pin high (data mode)
        nop
        
        bsf     PIN_ENABLE                  ; Reset enable
        
        movlw   D'10'                       ; 50uS delay
        rcall   delay10tcy
        
        movf    PORT_DATA, W
        
        bcf     PIN_ENABLE

        return


;******************************************************************************
; lcd_set_display : Set LCD display mode.
;
; Arguments : W= Display mode ;
;             B0: Cursor Blink, B1: Cursor on/off, B2: Display on/off
; Return    : None
;******************************************************************************
lcd_set_display:
        andlw   0x07                        ; Only keep the first 3 bits
        movwf   cur_mode                    ; Save new display mode
        
        addlw   OP_DISPLAY
        rcall   lcd_send_cmd                ; Send DISPLAY instruction to LCD

        return        


;******************************************************************************
; lcd_save_pos : Save current cursor position.
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_save_pos:
        movff   lcd_bptr, saved_pos
        
        movlw   0x1F
        andwf   saved_pos
        
        return


;******************************************************************************
; lcd_restore_pos : Restore previously saved cursor position.
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_restore_pos:
        movf    saved_pos, W
        rcall   lcd_goto

        return


;******************************************************************************
; lcd_write_page : Write to buffer page
;
; Arguments : FSR0 must point to the location where page data will be read from.
; Return    : None
;******************************************************************************
lcd_write_page:

        movlw   D'32'
        movwf   i
        
        lfsr    FSR1, lcd_buffer+0
        movff   lcd_bptr, FSR1L
        
        movlw   0xE0
        andwf   FSR1L

loop_write_page:
        movff   POSTINC0, POSTINC1

        decfsz  i
        bra     loop_write_page
        
        movlw   0x00
        rcall   lcd_dump_buffer

        return


;******************************************************************************
; lcd_read_page : Read from buffer page
;
; Arguments : FSR0 must point to the location where page data will be stored.
; Return    : None
;******************************************************************************
lcd_read_page:

        movlw   D'32'
        movwf   i
        
        lfsr    FSR1, lcd_buffer+0
        movff   lcd_bptr, FSR1L
        
        movlw   0xE0
        andwf   FSR1L

loop_read_page:
        movff   POSTINC1, POSTINC0

        decfsz  i
        bra     loop_read_page
        
        return


;******************************************************************************
; lcd_write_cgram: Write custom characters on LCD
;
; Arguments : W= Character ID (0-7), FSR0 must point to an 8 byte buffer that
;             contains the custom character data
; Return    : None
;******************************************************************************
lcd_write_cgram:
        andlw   0x07
        swapf   WREG
        bcf     STATUS, C
        rrcf    WREG
        addlw   OP_CGRAM
        rcall   lcd_send_cmd
        
        movlw   D'8'
        movwf   i
        
loop_write_cgram:
        movf    POSTINC0, W
        rcall   lcd_send_data
        
        decfsz  i
        bra     loop_write_cgram
        
        movf    lcd_bptr, W
        rcall   lcd_goto        

        return


;******************************************************************************
; lcd_save_cgram_table
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_save_cgram_table:
        movlw   OP_CGRAM + 0x00
        rcall   lcd_send_cmd

        bsf     PIN_RW                      ; Set LCD in read mode

        movlw   0xFF
        movwf   TRIS_DATA       

        movlw   D'64'
        movwf   i
        
loop_read_cgram_table:

        rcall   lcd_rcv_data
        movwf   EEDATA
        
        call    write_eeprom
        
        incf    EEADR
        
        decfsz  i
        bra     loop_read_cgram_table

        bcf     PIN_RW                      ; Set LCD back to write mode
        nop
        clrf    TRIS_DATA

        movf    lcd_bptr, W
        rcall   lcd_goto

        return


;******************************************************************************
; lcd_load_cgram_table
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_load_cgram_table:

        movlw   OP_CGRAM + 0x00
        rcall   lcd_send_cmd
        
        movlw   D'64'
        movwf   i
        
loop_write_cgram_table:
        movf    EEADR, W
        rcall   read_eeprom
        
        rcall   lcd_send_data
        
        incf    EEADR
        
        decfsz  i
        bra     loop_write_cgram_table

        movf    lcd_bptr, W
        rcall   lcd_goto

        return


;******************************************************************************
; lcd_init : Initialize LCD display.
;
; Arguments : None
; Return    : None
;******************************************************************************
lcd_init:
        clrf    lcd_trans_type
        clrf    lcd_trans_speed
        clrf    lcd_bptr
        clrf    cur_page
        
        clrf    PORT_DATA
        
        bcf     PIN_ENABLE
        bcf     PIN_RW
        bcf     PIN_RS

        movlw   D'100'
        rcall   delay1ktcy                 ; 50ms delay.
        
        ;-----------------------------------------
        ; Send init sequence X 2
        ;-----------------------------------------
        
        movlw   D'2'
        movwf   i

loop_init:      
        movlw   OP_FUNCTION + 0x18          ; Set Function 
        rcall   lcd_send_cmd                ; (bits=8, lines=2, dots=7)

        movlw   D'100'                      
        rcall   delay100tcy                 ; 5ms delay
        
        decfsz  i
        bra     loop_init
        

        ;-----------------------------------------
        ; Clear lcd buffer (8 pages)
        ;-----------------------------------------
        call    lcd_clear_pages     
        
        movlw   0x04                        ; Set default display mode
        rcall   lcd_set_display
        
        return


;==============================================================================
;==============================================================================
        END
