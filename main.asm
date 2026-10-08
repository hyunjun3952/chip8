default rel
extern fopen, fread, fclose, fgetc, fprintf, stderr
global main

; all machine state is one block, memory first. r12 points at it
OFF_V       equ 4096
OFF_I       equ OFF_V + 16
OFF_STACK   equ OFF_I + 2
OFF_SPTR    equ OFF_STACK + 32          ; next free slot, 0 = empty
STATE_SZ    equ OFF_SPTR + 1

%macro GET_X 1
    movzx   %1, ah
    and     %1, 0xF
%endmacro

%macro GET_Y 1
    movzx   %1, al
    shr     %1, 4
%endmacro

%macro CMP_XY 0
    test    al, 0x0F                    ; low nibble must be 0
    jnz     op_unknown
    GET_X   ecx
    GET_Y   esi
    mov     dl, [r12 + OFF_V + rcx]     ; cmp can't take two memory operands
    cmp     dl, [r12 + OFF_V + rsi]
%endmacro

section .rodata
mode_rb:        db "rb", 0

err_unknown:    db "bad opcode %04X at %04X", 10, 0
err_usage:      db "usage: chip8 rom", 10, 0
err_pc:         db "bad pc %04X", 10, 0
err_overflow:   db "stack full at %04X", 10, 0
err_underflow:  db "stack empty at %04X", 10, 0
err_open:       db "can't open rom", 10, 0
err_toobig:     db "rom too big", 10, 0
err_empty:      db "rom empty", 10, 0

align 8
table:          dq op_0xxx,    op_1nnn,    op_2nnn,    op_3xnn
                dq op_4xnn,    op_5xy0,    op_6xnn,    op_7xnn
                dq op_unknown, op_9xy0,    op_annn,    op_unknown
                dq op_unknown, op_unknown, op_unknown, op_unknown

; indexed by load_rom's return value
rom_errs:       dq 0, err_open, err_toobig, err_empty

section .bss
state:          resb STATE_SZ

section .text

main:
    push    rbx
    push    r12
    sub     rsp, 8                      ; align stack to 16
    cmp     edi, 2
    jl      .usage
    mov     rdi, [rsi + 8]
    call    load_rom
    test    eax, eax
    jnz     .rom_fail

    mov     ebx, 0x200
    lea     r12, [state]

.loop:
    cmp     ebx, 0xFFE                  ; last valid pc, an opcode is 2 bytes
    ja      .bad_pc

    movzx   eax, word [r12 + rbx]
    rol     ax, 8                       ; big endian
    add     ebx, 2

    mov     ecx, eax
    shr     ecx, 12
    lea     rdx, [table]
    jmp     [rdx + rcx * 8]

.next:                                  ; handlers jump here, they don't ret
    jmp     .loop

.usage:
    lea     rsi, [err_usage]
    jmp     die
.rom_fail:
    lea     rdx, [rom_errs]
    mov     rsi, [rdx + rax * 8]
    jmp     die
.bad_pc:
    lea     rsi, [err_pc]
    mov     edx, ebx
    jmp     die

.quit:
    xor     eax, eax
    jmp     .exit
.fail:
    mov     eax, 1
.exit:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; handlers: eax = opcode
op_0xxx:
    cmp     ax, 0x00EE
    jne     op_unknown
    movzx   ecx, byte [r12 + OFF_SPTR]
    test    ecx, ecx
    jz      stack_underflow
    dec     ecx
    mov     [r12 + OFF_SPTR], cl
    movzx   ebx, word [r12 + OFF_STACK + rcx * 2]
    jmp     main.next

op_1nnn:
    and     eax, 0x0FFF
    mov     ebx, eax
    jmp     main.next

op_2nnn:
    movzx   ecx, byte [r12 + OFF_SPTR]
    cmp     ecx, 16
    jae     stack_overflow
    mov     [r12 + OFF_STACK + rcx * 2], bx ; pc is already past the call
    inc     ecx
    mov     [r12 + OFF_SPTR], cl
    jmp     op_1nnn

op_3xnn:
    GET_X   ecx
    cmp     [r12 + OFF_V + rcx], al
    je      skip_next
    jmp     main.next

op_4xnn:
    GET_X   ecx
    cmp     [r12 + OFF_V + rcx], al
    jne     skip_next
    jmp     main.next

op_5xy0:
    CMP_XY
    je      skip_next
    jmp     main.next

op_6xnn:
    GET_X   ecx
    mov     [r12 + OFF_V + rcx], al
    jmp     main.next

op_7xnn:
    GET_X   ecx
    add     [r12 + OFF_V + rcx], al
    jmp     main.next

op_9xy0:
    CMP_XY
    jne     skip_next
    jmp     main.next

op_annn:
    and     eax, 0x0FFF
    mov     [r12 + OFF_I], ax
    jmp     main.next

skip_next:
    add     ebx, 2
    jmp     main.next

stack_overflow:
    lea     rsi, [err_overflow]
    lea     edx, [rbx - 2]              ; pc was already advanced
    jmp     die

stack_underflow:
    lea     rsi, [err_underflow]
    lea     edx, [rbx - 2]
    jmp     die

op_unknown:
    mov     edx, eax
    lea     ecx, [rbx - 2]
    lea     rsi, [err_unknown]
    jmp     die

; rsi = format, edx / ecx = its args
die:
    mov     rdi, [stderr wrt ..got]
    mov     rdi, [rdi]
    xor     eax, eax
    call    fprintf wrt ..plt
    jmp     main.fail

; rdi = path, eax = 0 ok / 1 can't open / 2 too big / 3 empty
load_rom:
    push    rbx
    sub     rsp, 16                     ; [rsp] = bytes read, [rsp + 8] = fgetc result
    lea     rsi, [mode_rb]
    call    fopen wrt ..plt
    test    rax, rax
    jz      .open_fail
    mov     rbx, rax

    lea     rdi, [state + 0x200]
    mov     esi, 1
    mov     edx, 4096 - 0x200
    mov     rcx, rbx
    call    fread wrt ..plt
    mov     [rsp], rax

    mov     rdi, rbx
    call    fgetc wrt ..plt             ; one more byte, eof (-1) means the rom fit
    mov     [rsp + 8], eax

    mov     rdi, rbx
    call    fclose wrt ..plt

    cmp     dword [rsp + 8], -1
    jne     .too_big
    cmp     qword [rsp], 0
    je      .empty

    xor     eax, eax
    jmp     .done
.open_fail:
    mov     eax, 1
    jmp     .done
.too_big:
    mov     eax, 2
    jmp     .done
.empty:
    mov     eax, 3
.done:
    add     rsp, 16
    pop     rbx
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
