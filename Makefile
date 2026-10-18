CC      := cc
CFLAGS  := -std=c11 -Wall -Wextra -Wpedantic -g -O0 -Iinclude \
           -fsanitize=address,undefined
LDFLAGS := -fsanitize=address,undefined

SRC := $(wildcard src/*.c)
OBJ := $(patsubst src/%.c,build/%.o,$(SRC))

build/server: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $^

build/%.o: src/%.c | build
	$(CC) $(CFLAGS) -c -o $@ $<

build:
	mkdir -p build

run: build/server
	./build/server

clean:
	rm -rf build

.PHONY: run clean
