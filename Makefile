NASM  = nasm
NFLAGS = -f elf64 -g -F dwarf
LDFLAGS = -no-pie
# SDL2를 붙일 때 아래 줄의 주석을 해제
# LIBS = $(shell sdl2-config --libs)

chip8: main.o
	gcc $(LDFLAGS) $< -o $@ $(LIBS)

main.o: main.asm
	$(NASM) $(NFLAGS) $< -o $@

run: chip8
	./chip8 pong.ch8

clean:
	rm -f main.o chip8

.PHONY: run clean
