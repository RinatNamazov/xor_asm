;	Copyright (c) 2021 Rinat Namazov <rinat.namazov@rinwares.com>
;
;	This program is free software: you can redistribute it and/or modify
;	it under the terms of the GNU General Public License as published by
;	the Free Software Foundation, either version 3 of the License, or
;	(at your option) any later version.
;
;	This program is distributed in the hope that it will be useful,
;	but WITHOUT ANY WARRANTY; without even the implied warranty of
;	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;	GNU General Public License for more details.
;
;	You should have received a copy of the GNU General Public License
;	along with this program.  If not, see <https://www.gnu.org/licenses/>.

%ifdef XOR_KEY
	%if XOR_KEY < 0x0 || XOR_KEY > 0xFF
		%fatal "XOR_KEY must be in the range 0x0-0xFF"
	%endif
%else
	%assign XOR_KEY		0xFF
%endif

%ifdef BUFFER_SIZE
	%if BUFFER_SIZE % 8 != 0
		%fatal "BUFFER_SIZE must be a multiple of 8"
	%endif
%else
	%assign BUFFER_SIZE	2048
%endif

%assign SYS_READ		0
%assign SYS_WRITE		1
%assign SYS_OPEN		2
%assign SYS_CLOSE		3
%assign SYS_EXIT		60

%assign STDERR	2

%assign O_WRONLY	00000001o
%assign O_CREAT		00000100o
%assign O_TRUNC		00001000o

%macro optimized_xor 2
	%if %2 == 0xFF
		not %1
	%elif %2 == 0
		; Do nothing.
	%else
		xor %1, %2
	%endif
%endmacro

%macro declare_string_with_line_feed 2
	%1 db %2, `\n`, 0
	%1_length equ $-%1
%endmacro

section .data
	file_path db "gta3.img", 0, "xor", 0
	file_path_offset_to_first_zero equ 8

	declare_string_with_line_feed error_open_input_file_msg, "Failed to open input file."
	declare_string_with_line_feed error_open_output_file_msg, "Failed to open output file."

%if XOR_KEY != 0xFF
	%ifdef XOR_AVX512
		zmm_xor_key times 64 db XOR_KEY
	%elifdef XOR_AVX2
		ymm_xor_key times 32 db XOR_KEY
	%elifdef XOR_AVX512
		xmm_xor_key times 16 db XOR_KEY
	%endif
%endif

section .text
	global _start

_start:
	mov rdi, file_path
	mov rsi, 0
	mov rax, SYS_OPEN
	syscall

	test rax, rax
	js error_open_input_file
	mov rbx, rax

	mov byte [file_path+file_path_offset_to_first_zero], '-'

	mov rdi, file_path
	mov rsi, O_WRONLY|O_CREAT|O_TRUNC
	mov rdx, 0666o
	mov rax, SYS_OPEN
	syscall

	test rax, rax
	js error_open_output_file
	mov rbp, rax

	mov r8, rsp
%ifdef XOR_AVX512
	%if XOR_KEY == 0xFF
		vpternlogd zmm0, zmm0, zmm0, 0xFF
	%else
		vmovdqa64 zmm0, [zmm_xor_key]
	%endif
	and rsp, -64
%elifdef XOR_AVX2
	%if XOR_KEY == 0xFF
		vpcmpeqd ymm0, ymm0, ymm0
	%else
		vmovdqa ymm0, [ymm_xor_key]
	%endif
	and rsp, -32
%elifdef XOR_SSE2
	%if XOR_KEY == 0xFF
		pcmpeqd xmm0, xmm0
	%else
		movdqa xmm0, [xmm_xor_key]
	%endif
	and rsp, -16
%endif
	sub rsp, BUFFER_SIZE

	mov rsi, rsp ; Both for read and write.
file_loop:
	mov rdi, rbx
	mov rdx, BUFFER_SIZE
	mov rax, SYS_READ
	syscall

	test rax, rax
	jz exit_file_loop

	mov rdx, rax ; For write.

%ifdef UNROLL_LOOP
	%assign i 0
	%ifdef XOR_AVX512
		%rep BUFFER_SIZE / 64
			vpxorq zmm1, zmm0, [rsp+i*64]
			vmovdqa64 [rsp+i*64], zmm1
			%assign i i+1
		%endrep
	%elifdef XOR_AVX2
		%rep BUFFER_SIZE / 32
			vpxor ymm1, ymm0, [rsp+i*32]
			vmovdqa [rsp+i*32], ymm1
			%assign i i+1
		%endrep
	%elifdef XOR_SSE2
		%rep BUFFER_SIZE / 16
			movdqa xmm1, [rsp+i*16]
			pxor xmm1, xmm0
			movdqa [rsp+i*16], xmm1
			%assign i i+1
		%endrep
	%else
		%rep BUFFER_SIZE / 8
			optimized_xor qword [rsp+i*8], XOR_KEY
			%assign i i+1
		%endrep
	%endif
%else
	%ifdef XOR_AVX512
		mov rcx, rsp
		add rax, rsp
	xor_loop:
		vpxorq zmm1, zmm0, [rcx]
		vmovdqa64 [rcx], zmm1
		add rcx, 64
		cmp rax, rcx
		jge xor_loop
	%elifdef XOR_AVX2
		mov rcx, rsp
		add rax, rsp
	xor_loop:
		vpxor ymm1, ymm0, [rcx]
		vmovdqa [rcx], ymm1
		add rcx, 32
		cmp rax, rcx
		jge xor_loop
	%elifdef XOR_SSE2
		mov rcx, rsp
		add rax, rsp
	xor_loop:
		movdqa xmm1, [rcx]
		pxor xmm1, xmm0
		movdqa [rcx], xmm1
		add rcx, 16
		cmp rax, rcx
		jge xor_loop
	%else
		mov rcx, BUFFER_SIZE / 8
	xor_loop:
		optimized_xor qword [rsp+rcx*8-8], XOR_KEY
		loop xor_loop
	%endif
%endif

	mov rdi, rbp
	mov rax, SYS_WRITE
	syscall

	jmp file_loop

exit_file_loop:
	mov rsp, r8

	mov rdi, rbp
	mov rax, SYS_CLOSE
	syscall

	mov rdi, rbx
	mov rax, SYS_CLOSE
	syscall

exit:
	xor rdi, rdi
	mov rax, SYS_EXIT
	syscall

error_open_input_file:
	mov rdi, STDERR
	mov rsi, error_open_input_file_msg
	mov rdx, error_open_input_file_msg_length
	mov rax, SYS_WRITE
	syscall
	jmp exit

error_open_output_file:
	mov rdi, STDERR
	mov rsi, error_open_output_file_msg
	mov rdx, error_open_output_file_msg_length
	mov rax, SYS_WRITE
	syscall
	jmp exit
