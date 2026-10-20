\ cforth host shim for Sun's OBP metacompiler (probe): Sun engine fsyscall(45) services + missing words
decimal
: $=  ( a1 l1 a2 l2 -- flag )  compare 0=  ;
: lconstant  constant  ;
: ascii  ( "c" -- c )  parse-word drop c@  state @ if postpone literal then  ; immediate
: copyright:  postpone \  ; immediate
: id:  postpone \  ; immediate
: purpose:  postpone \  ; immediate
variable syms  0 syms !
create nullval 0 c,
: sym-find  ( name$ -- e|0 )
   syms @  begin  dup  while
      >r 2dup r@ 1 cells + @ r@ 2 cells + @ $= if 2drop r> exit then
      r> @
   repeat  nip nip ;
: keep$  ( adr len -- adr' len )  dup 1+ alloc-mem swap 2dup 2>r move 2r> ;
: sym-set  ( val$ name$ -- )
   keep$ 2swap  dup 0= if  2drop nullval 0  else  keep$  then  2swap
   5 cells alloc-mem >r
   syms @ r@ !  swap r@ 1 cells + !  r@ 2 cells + !  swap r@ 3 cells + !  r@ 4 cells + !  r> syms ! ;
: sym-get  ( name$ -- val$ | 0 0 )
   sym-find ?dup if  dup 3 cells + @ swap 4 cells + @  else  0 0  then ;
: sym-undef ( name$ -- )  2drop ;
: fsyscall  ( ... n 45 -- ... )
   drop case
      55 of  sym-get  endof
      53 of  if  sym-set  else  sym-undef  then  endof
      57 of  endof
      50 of  drop  endof
      49 of  dup 2 = over 3 = or if drop else 2drop then  endof
      51 of  -1 = if true then  endof
      58 of  endof
      59 of  endof
      ( n ) ." fsyscall? " dup . cr
   endcase ;
variable ofd
: new-file  ( cstr -- )  count r/w create-file abort" can't create" ofd !  ;
: fputs  ( adr len fd -- )  write-file drop  ;
: fclose  ( fd -- )  close-file drop  ;
defer xref-header-hook   ' noop is xref-header-hook
defer xref-find-hook     ' noop is xref-find-hook
defer xref-hide-hook     ' noop is xref-hide-hook
defer xref-reveal-hook   ' noop is xref-reveal-hook
defer xref-string-hook   ' noop is xref-string-hook
: struct  ( -- 0 )  0  ;
: field   ( off size "name" -- off' )  create over , +  does> @ +  ;
: $vfind  ( adr len voc -- adr len false | xt +-1 )
   >r $canonical 2dup r> search-wordlist ?dup if 2swap 2drop else 0 then ;
: instruction!  ( n adr -- )  l!  ;
vocabulary assembler
: label  ( "name" -- )  create  ;
\ Sun's name-field address (anf) is modelled as cforth's code-field address: cforth's another? returns an acf.
: name>    ;
: >name    ;
: .id      .name  ;
: link>    ( alf -- acf )  /token +  ;
: l>name   ( alf -- anf )  /token +  ;
: n>flags  ( anf -- aff )  >flags  ;
: toggle  ( adr mask -- )  over c@ xor swap c!  ;
: name>string  ( anf -- adr len )  >name$  ;
: [""]  parse-word dup 2 + alloc-mem pack  postpone literal  ; immediate
: find  ( cstr -- cfa +-1 | cstr 0 )  dup >r count $find  dup if r> drop else drop 2drop r> 0 then  ;
create wordbuf 260 allot
: word  ( char -- cstr )
   >r  begin  >in @ source nip <  source drop >in @ + c@ r@ =  and  while  1 >in +!  repeat
   r> parse  wordbuf pack  ;
create temp-bufs 1024 allot
variable tb#
: "temp  ( -- adr )  tb# @ 1+ 3 and dup tb# !  256 * temp-bufs +  ;
: $cat  ( adr len pstr -- )   \ append adr,len to the counted string at pstr
   >r  r@ count +  swap  dup r@ c@ + r@ c!  move  r> drop  ;
: 3dup  ( a b c -- a b c a b c )  2 pick 2 pick 2 pick  ;
: lvariable  variable  ;
\ Sun's metacompiler does `is` on words declared with `0 constant` (Forthmacs allows it); in cforth only values take `is`/`to`.
: constant  ( n "name" -- )  value  ;
: lconstant  ( n "name" -- )  value  ;

: file-line  ( -- n )  0  ;

\ Sun's $create/create align the new header; cforth's don't, and Sun code leaves `here` odd after "0 c," (e.g. $makesym).
\ A misaligned body makes token! fault with SIGBUS on a big-endian strict-alignment host.
: $create  ( adr len -- )  align  $create  ;
: create   ( "name" -- )   align  create   ;
\ ... and does> must start on a token boundary too ($makesym ends its body with "0 c," before does>).
: does>  ( -- )  align  postpone does>  ; immediate

variable alias-flag
\ Sun's alias: the new word behaves exactly like the old one *when executed*, and inherits its precedence.
\ cforth's own alias decides compile-vs-execute by looking at STATE, which is wrong under the metacompiler (STATE=128):
\ it compiled the target's token into the host dictionary instead of running it.
: alias  ( "new" "old" -- )
   parse-word 2>r  parse-word  $find
   dup 0=  abort" alias: old word not found"
   alias-flag !  2r>  align  $header  colon-cf  compile,  ['] exit compile,
   alias-flag @ 1 =  if  immediate  then
;

\ the nheads dictionary is not produced on this host (only the kernel image is compared first)
: save-forth  ( str -- )  drop  ;
