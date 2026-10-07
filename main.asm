default rel ; rip-relative addressing
extern fopen, fread, fclose, printf

%macro GET_X 1 ; %1 = dest reg, X = bits 8..11 of the opcode (eax)
    mov %1, eax
    shr %1, 8
    and %1, 0xF
%endmacro

%macro GET_Y 1 ; %1 = dest reg, Y = bits 4..7 of the opcode (eax)
    mov %1, eax
    shr %1, 4
    and %1, 0xF
%endmacro

section .data
    mode_rb db "rb", 0
    fmt db "%04X", 10, 0
    ; handler per upper nibble of the opcode (index = upper nibble)
    table dq op_0xxx,    op_1nnn,    op_2nnn,    op_3xnn    ; 0 1 2 3
          dq op_4xnn,    op_5xy0,    op_6xnn,    op_7xnn    ; 4 5 6 7
          dq op_unknown, op_9xy0,    op_annn,    op_unknown ; 8 9 A B
          dq op_unknown, op_unknown, op_unknown, op_unknown ; C D E F

section .bss
    mem resb 4096 ; chip8 memory (= 4KB)
    pc  resw 1    ; program counter
    v   resb 16   ; V0 ~ VF registers
    i   resw 1    ; I register
    stack resw 16 ; call stack: 16 return addresses (2 byte each)
    sptr resb 1   ; stack pointer (idx into stack, 0 = empty)

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

    ; decode: branch to the upper nibble
    mov ecx, eax
    shr ecx, 12 ; upper 4 bits -> 0 ~ 15
    lea rdx, [table]
    jmp [rdx + rcx * 8] ; each table entry is 8 bytes

.next: ; handlers jump back here
    cmp word [pc], 0x200 + 20 ; only the first 10 opcodes for now
    jb .loop

    xor eax, eax ; return 0
    pop rbx ; restore rbx right before returning
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; opcode handlers: eax = opcode, jump (not ret) back to main.next
op_0xxx: ; ret (0x00EE) only for now, 00E0 falls to op_unknown
    cmp ax, 0x00EE
    jne op_unknown
    movzx ecx, byte [sptr]
    dec ecx ; sptr points to the next free slot, so step back first
    mov [sptr], cl
    lea rdx, [stack]
    movzx eax, word [rdx + rcx * 2] ; 2 bytes per entry
    mov [pc], ax ; return address -> pc
    jmp main.next

op_1nnn: ; pc = NNN
    and eax, 0x0FFF
    mov [pc], ax
    jmp main.next

op_2nnn: ; call: push pc, pc = NNN
    movzx ecx, byte [sptr]
    lea rdx, [stack]
    movzx esi, word [pc] ; already points to the next opcode
    mov [rdx + rcx * 2], si
    inc ecx
    mov [sptr], cl
    and eax, 0x0FFF
    mov [pc], ax
    jmp main.next

op_3xnn: ; skip next if V[X] == NN
    GET_X ecx
    lea rdx, [v]
    cmp [rdx + rcx], al ; al = NN
    je skip_next
    jmp main.next

op_4xnn: ; skip next if V[X] != NN
    GET_X ecx
    lea rdx, [v]
    cmp [rdx + rcx], al
    jne skip_next
    jmp main.next

op_5xy0: ; skip next if V[X] == V[Y]
    test al, 0x0F ; lowest nibble must be 0
    jnz op_unknown
    GET_X ecx
    GET_Y esi
    lea rdx, [v]
    mov r8b, [rdx + rcx] ; cmp can't take two mem operands
    cmp r8b, [rdx + rsi]
    je skip_next
    jmp main.next

op_6xnn: ; V[X] = NN
    GET_X ecx
    lea rdx, [v]
    mov [rdx + rcx], al ; al = lower byte = NN
    jmp main.next

op_7xnn: ; V[X] += NN (byte add wraps at 256, VF untouched)
    GET_X ecx
    lea rdx, [v]
    add [rdx + rcx], al ; al = NN
    jmp main.next

op_9xy0: ; skip next if V[X] != V[Y]
    test al, 0x0F ; lowest nibble must be 0
    jnz op_unknown
    GET_X ecx
    GET_Y esi
    lea rdx, [v]
    mov r8b, [rdx + rcx] ; cmp can't take two mem operands
    cmp r8b, [rdx + rsi]
    jne skip_next
    jmp main.next

op_annn: ; I = NNN
    and eax, 0x0FFF
    mov [i], ax
    jmp main.next

skip_next: ; shared by the skip ops: pc += 2 (skip one opcode)
    add word [pc], 2
    jmp main.next

; not implemented yet (or invalid opcode), print it for now
; once every group is implemented, this should report invalid opcodes and stop
; 00E0 8XY? BNNN CXNN DXYN EX9E EXA1 FX??
op_unknown:
    lea rdi, [fmt]
    mov esi, eax
    xor eax, eax ; no vector args for printf
    call printf wrt ..plt
    jmp main.next

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
