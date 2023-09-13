# XOR ASM

An example of amd64 (x86-64) assembly language code on Linux to encrypt a file using a simple xor algorithm.

I originally coded this program for friends who were comparing the speed of executing a simple algorithm in different programming languages. And I decided to bring out the big guns.

## Build instructions

You can use these parameters when assembling:
* `-dUNROLL_LOOP` // Unrolls the loop to increase the execution speed by increasing the binary size.
* `-dBUFFER_SIZE=2048` // Reading buffer size. Be aware of the stack size limit.
* `-dXOR_KEY=0xFF` // One-byte xor key value.

And one of the types of instructions:
* `-dXOR_SSE2`
* `-dXOR_AVX2`
* `-dXOR_AVX512`

#### Building
```
nasm -f elf64 xor.asm
ld xor.o -s -o xor
```

## License
The source code is published under GPLv3, the license is available [here](LICENSE).
