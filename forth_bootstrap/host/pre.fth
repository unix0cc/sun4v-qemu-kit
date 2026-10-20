0 0 " KERNEL" sym-set
0 0 " XREF" sym-set
" nheads.unused" " nheads-dic-name" sym-set
fload ${BP}/fm/lib/brackif.fth

\ Sun's host Forth provides the line-prefix conditionals (DTC build); cforth does not.
: \itc  [compile] \  ; immediate
: \dtc  ; immediate
: \ttc  [compile] \  ; immediate
: \t8   [compile] \  ; immediate
: \t16  [compile] \  ; immediate
: \t32  ; immediate
