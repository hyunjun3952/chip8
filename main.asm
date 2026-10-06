default rel ; rip-relative addressing
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
    push rbx ; save rbx, align stack (kept until ret)
    cmp edi, 2 ; need argv[1]
    jl .fail
    mov rdi, [rsi + 8] ; argv[1]
    call load_rom
    test eax, eax
    jnz .fail

    mov word [pc], 0x200 ; programs start at 0x200(= 512)

.loop:
    ; fetch
    lea rdx, [mem] ; base address (rip-relative can't be combined with an index)
    movzx ebx, word [pc] ; zero extend to use as index
    movzx eax, word [rdx + rbx] ; read 2 bytes (little endian)
    rol ax, 8 ; swap bytes to big endian opcode

    add word [pc], 2 ; next opcode (2 bytes each)

    ; print opcode
    lea rdi, [fmt]
    mov esi, eax
    xor eax, eax ; no vector args for printf
    call printf wrt ..plt

    cmp word [pc], 0x200 + 20 ; check if pc has reached 0x214
    jb .loop ; only first 10 opcodes for now

    xor eax, eax ; return 0
    pop rbx ; restore rbx right before returning
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; rdi = path, eax = 0 ok / 1 fail
load_rom:
    push rbx ; callee-saved, align stack
    lea rsi, [mode_rb] ; rdi = path already
    call fopen wrt ..plt
    test rax, rax ; NULL = fail
    jz .fail
    mov rbx, rax ; FILE*

    lea rdi, [mem + 0x200] ; dest
    mov esi, 1 ; elem size
    mov edx, 4096 - 0x200 ; max cnt (= 3584)
    mov rcx, rbx
    call fread wrt ..plt

    mov rdi, rbx ; FILE*
    mov rbx, rax ; keep bytes read across fclose
    call fclose wrt ..plt

    xor eax, eax
    test rbx, rbx ; 0 bytes read (empty file / read error) = fail
    setz al
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret
