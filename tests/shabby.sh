mkdir -p /root/.haxe/proj/hii_hl/ &&\
gcc -O3 -o /root/.haxe/proj/hii_hl/debug -std=c11 -I out out/main.c -lhl -lm