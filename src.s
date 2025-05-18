section .rodata
kernel:
    db 1, 2, 1
    db 2, 4, 2
    db 1, 2, 1

section .text
global gaussian_blur_asm

gaussian_blur_asm:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r10

    mov r10, rsi        ; output buffer
    mov rsi, rdx        ; temp_width
    mov r11, rdi        ; temp buffer
    mov rdi, r8         ; width
    mov r8, r9          ; height
    mov r9, rcx         ; temp_height

    xor ebx, ebx        ; c = 0

loop_c:
    cmp ebx, 3
    jge end_loop_c

    xor r12, r12        ; y = 0

loop_y:
    cmp r12, r8
    jge end_loop_y

    xor r13, r13        ; x = 0

loop_x:
    cmp r13, rdi
    jge end_loop_x

    xor r14d, r14d      ; sum = 0

    mov r15d, -1        ; ky = -1

loop_ky:
    cmp r15d, 1
    jg end_loop_ky

    mov eax, -1         ; kx = -1

loop_kx:
    cmp eax, 1
    jg end_loop_kx

    ; pos_temp_y = (y + 1) + ky
    lea ecx, [r12 + 1]
    add ecx, r15d
    cmp ecx, 0
    jge .y_ok1
    xor ecx, ecx
.y_ok1:
    cmp ecx, r9d
    jl .y_ok2
    mov ecx, r9d
    dec ecx
.y_ok2:

    ; pos_temp_x = (x + 1) + kx
    lea edx, [r13 + 1]
    add edx, eax
    cmp edx, 0
    jge .x_ok1
    xor edx, edx
.x_ok1:
    cmp edx, esi
    jl .x_ok2
    mov edx, esi
    dec edx
.x_ok2:

    ; Адрес во временном буфере
    imul ecx, esi
    add ecx, edx
    imul ecx, 3
    add ecx, ebx
    movzx edx, byte [r11 + rcx]

    ; Коэффициент ядра
    mov ecx, r15d
    add ecx, 1
    imul ecx, 3
    add ecx, eax
    add ecx, 1
    movzx ecx, byte [kernel + rcx]

    imul edx, ecx
    add r14d, edx

    inc eax
    jmp loop_kx

end_loop_kx:
    inc r15d
    jmp loop_ky

end_loop_ky:
    ; Округление
    add r14d, 8
    shr r14d, 4

    ; Адрес в выходном буфере
    mov ecx, r12d
    imul ecx, edi
    add ecx, r13d
    imul ecx, 3
    add ecx, ebx

    ; Запись результата
    mov byte [r10 + rcx], r14b

    inc r13
    jmp loop_x

end_loop_x:
    inc r12
    jmp loop_y

end_loop_y:
    inc ebx
    jmp loop_c

end_loop_c:
    pop r10
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret