#!/usr/bin/perl
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
#
# dwarf2genassym.pl -- offsets.h from DWARF, for compilers that cannot write stabs.
#
# Sun's hypervisor build makes offsets.h like this (greatlakes/*/Makefile.platform):
#
#     grep '^#' offsets.in                 > offsets-n1.c
#     cc -xdebugformat=stabs -g -S -o offsets-n1.s offsets-n1.c
#     grep -v '^#' offsets.in              > offsets.tmp
#     stabs -t genassym -m lp64 offsets.tmp < offsets-n1.s | egrep -v '[0-f]+ c-enum' > offsets.h
#
# Oracle Developer Studio 12.6 has no stabs (cc(1): "-xdebugformat=dwarf ... is the default.
# The option is obsolete"), and `stabs` reads nothing else. This script replaces the second
# and fourth steps, and reproduces `stabs -t genassym` -- same offsets.in language, same
# output, same quirks -- reading the DWARF that `dwarfdump` prints.
#
#   dwarf2genassym.pl stub offsets.in offsets-n1.i  >> offsets-n1.c
#       offsets-n1.i is `cc -E` of offsets-n1.c. DWARF carries a struct only when some
#       variable refers to it (cc -xdebuginfo=tagtype: "referenced from param and variable
#       datasets"), and offsets-n1.c is nothing but #includes, so this prints one
#       `struct X *__ofs_N;` per type offsets.in names. Whether a name is a struct, union,
#       enum or typedef is read off the preprocessed text.
#
#   cc -g -c -o offsets-n1.o offsets-n1.c
#   dwarfdump offsets-n1.o | dwarf2genassym.pl gen [-m lp64|ilp32] offsets.in - > offsets.h
#
# The same script serves the GNU path. gcc writes DWARF too (use -gdwarf-4: its data member
# locations are plain constants), and `readelf --debug-dump=info` prints it in a different
# text form; the dump's format is detected, or forced with `gen -f dwarfdump|readelf`:
#
#   readelf --debug-dump=info offsets-n1.o | dwarf2genassym.pl gen offsets.in - > offsets.h
#
# `gen -t asmcheck` reproduces `stabs -t asmcheck` (offsets.chk, which aschk checks the
# assembler sources against); the default is `-t genassym` (offsets.h).
#
# Perl 5.8 (Solaris 10's /usr/bin/perl) and later; nothing outside the core.

use strict;
use warnings;

my $rc = 0;
sub warnx { print STDERR "dwarf2genassym: @_\n"; $rc = 1 }

sub usage {
    print STDERR "usage: dwarf2genassym.pl stub offsets.in preprocessed.i\n",
                 "       dwarf2genassym.pl gen [-m lp64|ilp32] offsets.in dwarfdump-output|-\n";
    exit 2;
}

my $mode = shift @ARGV;
usage() unless defined $mode;
if    ($mode eq 'stub') { usage() unless @ARGV == 2; stub(@ARGV) }
elsif ($mode eq 'gen')  { gen(@ARGV) }
else                    { usage() }
exit $rc;

# ---------------------------------------------------------------------------
# offsets.in, parsed exactly as stabs' parse_dbg() does.
#
# Returns a list of items, in file order:
#   { text => "..." }                        printed verbatim
#   { name => N, format => F, format2 => F2, child => [ [name, format], ... ] }
#
# Quirks kept on purpose: a `\#` line is printed even inside a model_start section
# that does not match; a blank line is printed only inside verbatim_begin/forth_start.
# ---------------------------------------------------------------------------
sub parse_offsets {
    my ($file, $model) = @_;
    open(my $fh, '<', $file) or die "dwarf2genassym: cannot open $file: $!\n";
    my @lines = <$fh>;
    close $fh;

    my (@items, $copy, $ignore);
    my $i = 0;
    while ($i < @lines) {
        my $l = $lines[$i++];
        next if $l =~ /^#/;               # the Makefile feeds stabs offsets.in minus these
        if ($l =~ /^\n/) {
            push @items, { text => "\n" } if $copy;
            next;
        }
        if ($l =~ /^\\/) {
            push @items, { text => substr($l, 1) } if substr($l, 1, 1) eq '#';
            next;
        }
        if ($l eq "model_end\n") { $ignore = 0; next }
        next if $ignore;
        if ($l =~ /^model_start /) {
            my $m = substr($l, length("model_start "));
            $ignore = ($m eq "$model\n") ? 0 : 1;
            next;
        }
        if ($l eq "verbatim_begin\n" || $l eq "forth_start\n") { $copy = 1; next }
        if ($l eq "verbatim_end\n"   || $l eq "forth_end\n")   { $copy = 0; next }
        if ($copy) { push @items, { text => $l }; next }

        my @w = split(' ', $l);
        if (!@w) { warnx("blank-looking line " . $i); next }
        # stabs reads a second format only when the first is there
        my $node = { name => $w[0], format => $w[1], format2 => (defined $w[1] ? $w[2] : undef), child => [] };
        while ($i < @lines && $lines[$i] !~ /^\n/) {
            my @c = split(' ', $lines[$i++]);
            if (!@c) { warnx("empty child line after $node->{name}"); next }
            push @{ $node->{child} }, [ $c[0], defined($c[1]) ? $c[1] : uc($c[0]) ];
        }
        push @items, $node;
    }
    return @items;
}

# ---------------------------------------------------------------------------
# stub: the variables that make cc emit the types.
# ---------------------------------------------------------------------------
sub stub {
    my ($oin, $pp) = @_;
    my @items = parse_offsets($oin, 'lp64');
    my (@names, %seen);
    for my $it (@items) {
        next unless defined $it->{name};
        my ($base) = split(/\./, $it->{name}, 2);
        push @names, $base unless $seen{$base}++;
    }

    open(my $fh, '<', $pp) or die "dwarf2genassym: cannot open $pp: $!\n";
    my $text = '';
    while (<$fh>) { next if /^\s*#/; $text .= $_ }
    close $fh;
    $text =~ s{/\*.*?\*/}{ }gs;

    my @tok = $text =~ /([A-Za-z_]\w*|\d\w*|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\S)/g;
    my (%tag, %tdef);
    my $depth = 0;
    for (my $i = 0; $i < @tok; $i++) {
        my $t = $tok[$i];
        if    ($t eq '{') { $depth++ }
        elsif ($t eq '}') { $depth-- }
        elsif ($t eq 'struct' || $t eq 'union' || $t eq 'enum') {
            my $n = $tok[$i + 1];
            if (defined $n && $n =~ /^[A-Za-z_]/ && defined $tok[$i + 2] && $tok[$i + 2] eq '{') {
                $tag{$n} = "$t $n";
            }
        }
        elsif ($t eq 'typedef') {
            # Declarators are what lies outside braces up to the `;` at brace depth 0.
            my ($d, @seg) = (0);
            for (my $j = $i + 1; $j < @tok; $j++) {
                my $x = $tok[$j];
                if    ($x eq '{') { $d++; next }
                elsif ($x eq '}') { $d--; next }
                last if $x eq ';' && $d == 0;
                push @seg, $x if $d == 0;
            }
            my @decl = ([]);
            my $pd = 0;
            for my $x (@seg) {
                $pd++ if $x eq '(';
                $pd-- if $x eq ')';
                if ($x eq ',' && $pd == 0) { push @decl, [] } else { push @{ $decl[-1] }, $x }
            }
            for my $dd (@decl) {
                my @x = @$dd;
                my $n;
                for (my $k = 0; $k < @x - 2; $k++) {      # ( * name )  -- function pointer
                    if ($x[$k] eq '(' && $x[$k + 1] eq '*' && $x[$k + 2] =~ /^[A-Za-z_]\w*$/) { $n = $x[$k + 2]; last }
                }
                if (!defined $n) {
                    my @y;
                    for my $z (@x) { last if $z eq '['; push @y, $z }
                    for (my $k = $#y; $k >= 0; $k--) { if ($y[$k] =~ /^[A-Za-z_]\w*$/) { $n = $y[$k]; last } }
                }
                $tdef{$n} = 1 if defined $n;
            }
        }
    }

    my $k = 0;
    for my $n (@names) {
        my $sp = exists $tag{$n} ? $tag{$n} : (exists $tdef{$n} ? $n : undef);
        if (!defined $sp) { warnx("no struct/union/enum/typedef named '$n' in $pp"); next }
        printf "%s *__ofs_%d;\n", $sp, $k++;
    }
}

# ---------------------------------------------------------------------------
# DWARF, from `dwarfdump` text.
# ---------------------------------------------------------------------------
my (%die, %by_tag_name, %by_typedef, %by_base);
my $PTRSZ = 8;

sub nval {
    my $v = shift;
    return undef unless defined $v;
    # dwarfdump: "DW_OP_plus_uconst 8"; readelf: "8", or "N byte block: .. (DW_OP_plus_uconst: 8)"
    $v = $1 if $v =~ /\(DW_OP_plus_uconst:\s*(\d+)\)/;
    return hex($1)  if $v =~ /^(?:DW_OP_plus_uconst\s+)?0x([0-9a-fA-F]+)(?:\s|$)/;
    return $1 + 0   if $v =~ /^(?:DW_OP_plus_uconst\s+)?(-?\d+)(?:\s|$)/;
    return undef;
}
sub sval {
    my $v = shift;
    return undef unless defined $v;
    return $1 if $v =~ /^"(.*)"$/;
    return $v;
}
sub rval {
    my $v = shift;
    return undef unless defined $v && $v =~ /^<0x([0-9a-fA-F]+)>/;
    return sprintf("%x", hex($1));
}

sub index_dies {
    for my $id (keys %die) {
        my $d = $die{$id};
        my $n = sval($d->{at}{DW_AT_name});
        next unless defined $n;
        my $t = $d->{tag};
        if    ($t =~ /^DW_TAG_(structure|union|enumeration)_type$/) { $by_tag_name{$n} = $d }
        elsif ($t eq 'DW_TAG_base_type')                            { $by_base{$n}     = $d }
        elsif ($t eq 'DW_TAG_typedef')                              { $by_typedef{$n}  = $d }
    }
}

sub load_dwarf {
    my ($fh, $fmt) = @_;
    my @lines = <$fh>;
    if ($fmt eq 'auto') {
        $fmt = 'dwarfdump';
        for my $l (@lines) {
            if ($l =~ /^Contents of the \.debug_info section/ || $l =~ /Abbrev Number:/) { $fmt = 'readelf'; last }
            last if $l =~ /^\.debug_info:/;
        }
    }
    if    ($fmt eq 'dwarfdump') { load_dwarfdump(\@lines) }
    elsif ($fmt eq 'readelf')   { load_readelf(\@lines) }
    else                        { die "dwarf2genassym: unknown dump format '$fmt'\n" }
    index_dies();
}

# Sun's dwarfdump:
#   < 1><0x000000f3>    DW_TAG_enumeration_type
#                         DW_AT_name                  "col"
sub load_dwarfdump {
    my $lines = shift;
    my (@stack, $cur, $in);
    for my $l (@$lines) {
        if ($l =~ /^\.debug_info:/) { $in = 1; next }
        next unless $in;
        last if $l =~ /^File table:/ || $l =~ /^\.debug_(?!info)/;
        if ($l =~ /^<\s*(\d+)><0x([0-9a-fA-F]+)>\s+(DW_TAG_\w+)/) {
            my ($d, $id, $tag) = ($1, sprintf("%x", hex($2)), $3);
            my $die = { id => $id, tag => $tag, at => {}, kids => [] };
            $die{$id} = $die;
            $stack[$d] = $die;
            push @{ $stack[$d - 1]{kids} }, $die if $d > 0;
            $cur = $die;
            next;
        }
        if ($cur && $l =~ /^\s+(DW_AT_\w+)\s+(.*?)\s*$/) { $cur->{at}{$1} = $2 }
    }
}

# GNU readelf --debug-dump=info:
#  <1><1d>: Abbrev Number: 2 (DW_TAG_typedef)
#     <1e>   DW_AT_name        : (indirect string, offset: 0x2a): uint64_t
#     <52>   DW_AT_data_member_location: 4
sub load_readelf {
    my $lines = shift;
    my (@stack, $cur);
    for my $l (@$lines) {
        if ($l =~ /^\s*<(\d+)><([0-9a-fA-F]+)>:\s+Abbrev Number:\s+(\d+)\s+\((DW_TAG_\w+)\)/) {
            my ($d, $id, $tag) = ($1, sprintf("%x", hex($2)), $4);
            my $die = { id => $id, tag => $tag, at => {}, kids => [] };
            $die{$id} = $die;
            $stack[$d] = $die;
            push @{ $stack[$d - 1]{kids} }, $die if $d > 0;
            $cur = $die;
            next;
        }
        if ($cur && $l =~ /^\s+<[0-9a-fA-F]+>\s+(DW_AT_\w+)\s*:\s*(.*?)\s*$/) {
            my ($a, $v) = ($1, $2);
            if ($a eq 'DW_AT_name') {
                $v =~ s/^\((?:indirect(?: line)? string|alt indirect string)[^)]*\):\s*//;
                $v = "\"$v\"";            # same spelling dwarfdump uses
            }
            $cur->{at}{$a} = $v;
        }
    }
}

sub type_of { my $d = shift; my $r = rval($d->{at}{DW_AT_type}); return defined $r ? $die{$r} : undef }

# typedef/const/volatile are transparent, as TYPEOF/VOLATILE are in stabs
sub strip {
    my $d = shift;
    while (defined $d && $d->{tag} =~ /^DW_TAG_(typedef|const_type|volatile_type|restrict_type)$/) {
        $d = type_of($d);
    }
    return $d;
}

# stabs' lookupname(): a tag or a base type beats a typedef of the same name
sub lookup_name {
    my $n = shift;
    return $by_tag_name{$n} if exists $by_tag_name{$n};
    return $by_base{$n}     if exists $by_base{$n};
    return $by_typedef{$n}  if exists $by_typedef{$n};
    return undef;
}

sub sizeof_die {
    my $d = strip(shift);
    return 0 unless defined $d;
    my $n = nval($d->{at}{DW_AT_byte_size});
    return $n if defined $n;
    return $PTRSZ if $d->{tag} eq 'DW_TAG_pointer_type';
    if ($d->{tag} eq 'DW_TAG_array_type') {
        # no byte_size (gcc): element size times every dimension; gcc keeps all
        # dimensions of int a[2][3] as subranges of ONE array type
        my $total = sizeof_die(type_of($d));
        for my $sub (grep { $_->{tag} eq 'DW_TAG_subrange_type' } @{ $d->{kids} }) {
            my $ub  = nval($sub->{at}{DW_AT_upper_bound});
            my $cnt = nval($sub->{at}{DW_AT_count});
            my $n   = defined $ub ? $ub + 1 : (defined $cnt ? $cnt : 0);
            $total *= $n;
        }
        return $total;
    }
    return 0;
}

sub members { my $d = shift; return grep { $_->{tag} eq 'DW_TAG_member' } @{ $d->{kids} } }

sub find_member {
    my ($d, $name) = @_;
    $d = strip($d);
    return undef unless defined $d && $d->{tag} =~ /^DW_TAG_(structure|union)_type$/;
    for my $m (members($d)) {
        my $n = sval($m->{at}{DW_AT_name});
        return type_of($m) if defined $n && $n eq $name;
    }
    return undef;
}

# ---------------------------------------------------------------------------
# gen: stabs' genassym back end
# ---------------------------------------------------------------------------
sub hx { return sprintf("%x", $_[0] & 0xffffffff) }

sub do_member {
    my ($m, $format) = @_;
    my $name = sval($m->{at}{DW_AT_name});
    my $mt   = type_of($m);
    return unless defined $mt;
    $format = uc($name) if !defined $format;
    return unless defined $format;

    my $loc  = nval($m->{at}{DW_AT_data_member_location});
    $loc = 0 unless defined $loc;
    my $boff = nval($m->{at}{DW_AT_bit_offset});
    $boff = 0 unless defined $boff;
    my $bsz  = nval($m->{at}{DW_AT_bit_size});
    my $offset = $loc * 8 + $boff;                       # bits from the start of the struct
    my $dbo = nval($m->{at}{DW_AT_data_bit_offset});     # DWARF 5 spelling of the same thing
    $offset = $dbo if defined $dbo;
    my $size   = defined $bsz ? $bsz : sizeof_die($mt) * 8;

    my $t = strip($mt);
    my $tag = defined $t ? $t->{tag} : 'DW_TAG_unspecified_type';
    if ($tag eq 'DW_TAG_base_type') {
        if ($size != 0 && (($size % 8) != 0 || ($offset % $size) != 0)) {
            my $o     = int($offset / 32) * 4;
            my $shift = 32 - (($offset % 32) + $size);
            my $mask  = (((1 << $size) - 1) << $shift) & 0xffffffff;
            print "#define\t${format}_SHIFT 0x", hx($shift), "\n";
            print "#define\t${format}_MASK 0x",  hx($mask),  "\n";
            print "#define\t${format}_OFFSET 0x", hx($o),    "\n";
        } else {
            print "#define\t$format 0x", hx($offset / 8), "\n";
        }
    }
    elsif ($tag eq 'DW_TAG_array_type') {
        my ($sub) = grep { $_->{tag} eq 'DW_TAG_subrange_type' } @{ $t->{kids} };
        my $ub = defined $sub ? nval($sub->{at}{DW_AT_upper_bound}) : undef;
        my $cnt = defined $sub ? nval($sub->{at}{DW_AT_count}) : undef;
        my $items = defined $ub ? $ub + 1 : (defined $cnt ? $cnt : 0);
        if ($items <= 0) { warnx("array member '$name' has no bounds"); return }
        my $inc = int(($size / $items) / 8);
        print "#define\t$format 0x", hx($offset / 8), "\n";
        print "#define\t${format}_INCR 0x", hx($inc), "\n";
    }
    elsif ($tag eq 'DW_TAG_subroutine_type') {
        warnx("function in struct (member '$name')");
    }
    elsif ($tag =~ /^DW_TAG_(pointer|structure|union|enumeration)_type$/) {
        print "#define\t$format 0x", hx($offset / 8), "\n";
    }
    else {
        warnx("member '$name': unknown type $tag");
    }
}

sub do_node {
    my ($np, $t) = @_;
    $t = strip($t);
    if (!defined $t) { warnx("$np->{name} isn't aggregate"); return }
    my $tag = $t->{tag};

    if ($tag =~ /^DW_TAG_(structure|union)_type$/) {
        my $size = nval($t->{at}{DW_AT_byte_size});
        $size = 0 unless defined $size;
        if (defined $np->{format}) {
            print "#define\t", uc($np->{format}), " 0x", hx($size), "\n";
            if (defined $np->{format2}) {
                for my $l (0 .. 31) {
                    if ((1 << $l) == $size) { print "#define\t$np->{format2} 0x", hx($l), "\n"; last }
                }
            }
        }
        my %want = map { $_->[0] => $_->[1] } @{ $np->{child} };
        for my $m (members($t)) {
            my $mn = sval($m->{at}{DW_AT_name});
            my $format;
            if (@{ $np->{child} }) {
                next unless defined $mn && exists $want{$mn};
                $format = uc($want{$mn});
            }
            do_member($m, $format);
        }
    }
    elsif ($tag eq 'DW_TAG_enumeration_type') {
        print "\n";
        for my $e (grep { $_->{tag} eq 'DW_TAG_enumerator' } @{ $t->{kids} }) {
            my $v = nval($e->{at}{DW_AT_const_value});
            print "#define\tENUM_", sval($e->{at}{DW_AT_name}), " 0x", hx(defined $v ? $v : 0), "\n";
        }
        # stabs prints "<n> c-enum .<name>" here and the Makefile filters it out again
    }
    elsif ($tag eq 'DW_TAG_base_type') {
        print "#define\t", uc($np->{format}), " 0x", hx(sizeof_die($t)), "\n" if defined $np->{format};
    }
    else {
        warnx("$np->{name} isn't aggregate");
    }
}

# ---------------------------------------------------------------------------
# asmcheck: stabs' asmcheck back end (offsets.chk, read by aschk)
# ---------------------------------------------------------------------------
sub enc_code {
    my $d = shift;
    my $e = $d->{at}{DW_AT_encoding};
    return 'X' unless defined $e;
    return 's'  if $e =~ /^(DW_ATE_signed|5)(?:\s|$)/;
    return 'u'  if $e =~ /^(DW_ATE_unsigned|7)(?:\s|$)/;
    return 'sc' if $e =~ /^(DW_ATE_signed_char|6)(?:\s|$)/;
    return 'uc' if $e =~ /^(DW_ATE_unsigned_char|8)(?:\s|$)/;
    return 'X';
}

sub subranges { my $d = shift; return grep { $_->{tag} eq 'DW_TAG_subrange_type' } @{ $d->{kids} } }
sub sub_count {
    my $sub = shift;
    my $ub  = nval($sub->{at}{DW_AT_upper_bound});
    my $cnt = nval($sub->{at}{DW_AT_count});
    return defined $ub ? $ub + 1 : (defined $cnt ? $cnt : 0);
}

# switch_on_type(): $offset and $size are the member's, in bits, as stabs keeps them
sub chk_switch {
    my ($offset, $size, $die, $dim, $format) = @_;
    my $t = strip($die);
    my $tag = defined $t ? $t->{tag} : 'DW_TAG_unspecified_type';
    if ($tag eq 'DW_TAG_base_type') {
        my $tsz = sizeof_die($t);
        if ($size != 0 && (($size % 8) != 0 || ($offset % (8 * $tsz)) != 0)) {
            printf "!\tbitfield: @ 0x%s : size = 0x%s\n", hx($offset), hx($size);
        } else {
            printf "%s\t0x%s\t0x%s\t%s\n", enc_code($t), hx($offset / 8), hx($tsz), $format;
        }
    }
    elsif ($tag eq 'DW_TAG_pointer_type') {
        printf "p\t0x%s\t0x%s\t%s\n", hx($offset / 8), hx($size / 8), $format;
    }
    elsif ($tag eq 'DW_TAG_array_type') {
        my @subs = subranges($t);
        $dim = 0 unless defined $dim;
        my $items = @subs ? sub_count($subs[$dim]) : 0;
        if ($items <= 0) { warnx("array '$format' has no bounds"); return }
        my $inc = int(($size / $items) / 8);
        printf "!\tarray %s @ 0x%s size 0x%s : element size 0x%s\n", $format, hx($offset / 8), hx($size), hx($inc);
        # gcc keeps int a[2][3] as one array type with two subranges, Sun as an array of arrays
        if ($dim + 1 < @subs) { chk_switch($offset, $size, $t, $dim + 1, $format) }
        else                  { chk_switch($offset, $size, type_of($t), 0, $format) }
    }
    elsif ($tag eq 'DW_TAG_structure_type') {
        printf "!\tstruct %s @ 0x%s has size 0x%s\n", $format, hx($offset / 8), hx($size / 8);
    }
    elsif ($tag eq 'DW_TAG_union_type') {
        printf "!\tunion %s @ 0x%s has size 0x%s\n", $format, hx($offset / 8), hx($size / 8);
    }
    elsif ($tag eq 'DW_TAG_enumeration_type') {
        print "#define\t$format 0x", hx($offset / 8), "\n";
    }
    elsif ($tag eq 'DW_TAG_subroutine_type') {
        warnx("function in struct (member '$format')");
    }
    else {
        warnx("member '$format': unknown type $tag");
    }
}

sub chk_node {
    my ($np, $t) = @_;
    $t = strip($t);
    if (!defined $t) { warnx("$np->{name} isn't aggregate"); return }
    my $tag = $t->{tag};
    if ($tag =~ /^DW_TAG_(structure|union)_type$/) {
        my $size = nval($t->{at}{DW_AT_byte_size});
        $size = 0 unless defined $size;
        printf "!\tstruct/union %s size 0x%s\n", uc($np->{format}), hx($size) if defined $np->{format};
        my %want = map { $_->[0] => $_->[1] } @{ $np->{child} };
        for my $m (members($t)) {
            my $mn = sval($m->{at}{DW_AT_name});
            my $format;
            if (@{ $np->{child} }) {
                next unless defined $mn && exists $want{$mn};
                $format = uc($want{$mn});
            } else {
                $format = uc($mn);
            }
            my $mt = type_of($m);
            next unless defined $mt;
            my $loc  = nval($m->{at}{DW_AT_data_member_location}); $loc = 0 unless defined $loc;
            my $boff = nval($m->{at}{DW_AT_bit_offset});           $boff = 0 unless defined $boff;
            my $bsz  = nval($m->{at}{DW_AT_bit_size});
            my $offset = $loc * 8 + $boff;
            my $dbo = nval($m->{at}{DW_AT_data_bit_offset});
            $offset = $dbo if defined $dbo;
            my $size = defined $bsz ? $bsz : sizeof_die($mt) * 8;
            chk_switch($offset, $size, $mt, 0, $format);
        }
    }
    elsif ($tag eq 'DW_TAG_enumeration_type') {
        print "\n";
        for my $e (grep { $_->{tag} eq 'DW_TAG_enumerator' } @{ $t->{kids} }) {
            my $v = nval($e->{at}{DW_AT_const_value});
            print "#define\tENUM_", sval($e->{at}{DW_AT_name}), " 0x", hx(defined $v ? $v : 0), "\n";
        }
    }
    elsif ($tag eq 'DW_TAG_base_type') {
        printf "\t/* %s 0x%s */\n", uc($np->{format}), hx(sizeof_die($t)) if defined $np->{format};
    }
    else {
        warnx("$np->{name} isn't aggregate");
    }
}

sub gen {
    my ($model, $fmt, $type) = ('lp64', 'auto', 'genassym');
    while (@ARGV && $ARGV[0] =~ /^-[mft]$/) {
        my $o = shift @ARGV;
        if    ($o eq '-m') { $model = shift @ARGV }
        elsif ($o eq '-f') { $fmt   = shift @ARGV }
        else               { $type  = shift @ARGV }
    }
    usage() unless $type eq 'genassym' || $type eq 'asmcheck';
    usage() unless @ARGV == 2 && defined $model && defined $fmt;
    my ($oin, $dump) = @ARGV;
    $PTRSZ = $model eq 'ilp32' ? 4 : 8;

    my $fh;
    if ($dump eq '-') { $fh = \*STDIN } else { open($fh, '<', $dump) or die "dwarf2genassym: cannot open $dump: $!\n" }
    load_dwarf($fh, $fmt);
    die "dwarf2genassym: no .debug_info in the dwarfdump output\n" unless %die;

    for my $it (parse_offsets($oin, $model)) {
        if (!defined $it->{name}) { print $it->{text}; next }
        my $t = lookup_name($it->{name});
        if (!defined $t && $it->{name} =~ /^([^.]*)\.(.*)$/) {
            my $p = lookup_name($1);
            $t = find_member($p, $2) if defined $p;
        }
        if (!defined $t) { warnx("Can't find $it->{name}"); next }
        if ($type eq 'asmcheck') { chk_node($it, $t) } else { do_node($it, $t) }
    }
}
