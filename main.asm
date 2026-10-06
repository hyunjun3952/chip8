default rel
extern fopen, fread, fclose, printf

section .data
    mode_rb db "rb", 0
    fmt db "%04X", 10, 0

section .bss
    mem resb 4096 ; chip8 memory (= 4KB)
    pc resw 1     ; program counter

section .text
    global main

main:
    push rbx ; save rbx, align stack
    mov rdi, [rsi + 8] ; argv[1]
    call load_rom
    test eax, eax
    jnz .fail

    mov word [pc], 0x200 ; programs start at 0x200(= 512)
    
    ; return 0
    xor eax, eax
    pop rbx
.loop:
    ; fetch
    movzx rbx, word [pc]
    ; (movbe ax, [mem + rbx] does both lines in one)
    movzx eax, word [mem + rbx] ; read 2 bytes (little endian)
    rol ax, 8 ; swap bytes to big endian opcode

    add word [pc], 2

    ; print opcode
    lea rdi, [fmt]
    mov esi, eax
    xor eax, eax ; no vector args for printf
    call printf

    cmp word [pc], 0x200 + 20 ; check if pc has reached 0x214
    jb .loop

    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; rdi = path, eax = 0 ok / 1 fail
load_rom:
    push rbx
    lea rsi, [mode_rb]
    call fopen
    test rax, rax ; NULL = fail
    jz .fail
    mov rbx, rax ; FILE*

    lea rdi, [mem + 0x200] ; dest
    mov esi, 1 ; elem size
    mov edx, 4096 - 0x200 ; max cnt
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
