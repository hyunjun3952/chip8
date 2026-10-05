default rel
extern fopen, fread, fclose, printf

section .data
    mode_rb db "rb", 0
    fmt db "%04X", 10, 0

section .bss
    mem resb 4096
    pc resw 1

section .text
    global main

main:
    push rbx
    mov rdi, [rsi + 8]
    call load_rom
    test eax, eax
    jnz .fail

    mov word [pc], 0x200
    
    ; fetch
    movzx rbx, word [pc]
    movzx eax, word [mem + rbx]
    rol ax, 8
    
    lea rdi, [fmt]
    mov esi, eax
    xor eax, eax
    call printf

    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret 

load_rom:
    push rbx
    lea rsi, [mode_rb]
    call fopen
    test rax, rax
    jz .fail
    mov rbx, rax

    lea rdi, [mem + 0x200]
    mov esi, 1
    mov edx, 4096 - 0x200
    mov rcx, rbx
    call fread

    mov rdi, rbx
    call fclose

    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret