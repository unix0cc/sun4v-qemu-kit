\ Sun-style hookable host interpreter for cforth (fm/kernel/interp.fth:105-200). Installed by patching the bodies of the existing
\ compile-word, [ and ] (token-threaded, so every already-compiled caller follows). cforth's : and ; are C primitives that set
\ `state` directly, so $compile re-selects the hooks when it sees state go 0 <-> nonzero behind its back; any other value (the
\ metacompiler's own `metacompiling`) leaves the hooks as ]-t set them.
decimal
: patch-to  ( new-xt old-xt -- )  >body dup >r token!  ['] exit r> /token + token!  ;
defer do-defined       ( xt +-1 -- ?? )
defer $do-undefined    ( adr len -- )
defer do-literal       ( n 1 | d 2 -- )
defer $handle-literal? ( adr len -- handled? )
: $dnumber?  ( adr len -- n 1 | d 2 | 0 )   \ cforth's $number? is ( adr len -- d true | false )
   $number?  if  dpl @  if  drop 1  else  2  then  else  0  then  ;
: (do-literal)  ( n 1 | d 2 -- n | d | )
   state @  if  2 =  if  [compile] 2literal  else  [compile] literal  then  else  drop  then  ;
' (do-literal) is do-literal
: ($handle-literal?)  ( adr len -- handled? )  $dnumber?  dup  if  do-literal true  then  ;
' ($handle-literal?) is $handle-literal?
: interpret-do-defined  ( xt +-1 -- )  drop execute  ;
: compile-do-defined    ( xt +-1 -- )  0>  if  execute  else  compile,  then  ;
: $interpret-do-undefined  ( adr len -- )  .not-found  -13 throw  ;
: $compile-do-undefined    ( adr len -- )  .not-found  compile lose  ;
variable hook-state  0 hook-state !
: interpret-hooks  ['] interpret-do-defined is do-defined  ['] $interpret-do-undefined is $do-undefined  0 hook-state !  ;
: compile-hooks    ['] compile-do-defined   is do-defined  ['] $compile-do-undefined   is $do-undefined  -1 hook-state !  ;
: sync-hooks  ( -- )
   state @  hook-state @ <>  if
      state @  0=  if  interpret-hooks  else
         state @ -1 = state @ 1 = or  if
            state @ 1 =  if  -1 state !  then
            compile-hooks
         then
      then
   then  ;
: ([)  interpret-hooks  0 state !  ;
: (])  compile-hooks  -1 state !  ;
: $compile  ( adr len -- ?? )
   sync-hooks
   state @ -1 =  if  here 3 and  if  align  then  then
   2dup 2>r  $find  dup  if  2r> 2drop  do-defined
   else  3drop  2r@ $handle-literal?  0=  if  2r@ $do-undefined  then  2r> 2drop  then  ;
([)
' ([)       ' [             patch-to
' (])       ' ]             patch-to
' $compile  ' compile-word  patch-to
