\ dict-dump.fth -- list every word in every vocabulary a stand.dic carries,
\ via the dictionary's own `words` (fm/lib/words.fth), not a hand-rolled
\ walker: a first attempt using follow/another?/.id directly crashed the
\ engine on the assembler vocabulary (its headers are not the ordinary NFA
\ chain -- Segmentation fault under qemu-sparc64, 2026-09-20); `words`
\ is what Sun's own dictionary already knows how to do this with, and does
\ it without incident.
\
\ Vocabularies hardcoded, not enumerated: confirmed present in stand.dic by
\ direct lookup (forth hidden keys-forth decompressor assembler root; meta/
\ symbols/labels/transition are metacompiler-only and not in the runtime
\ dictionary). A vocabulary added later needs a line added here.
." forth ::" cr        only forth also words previous
." hidden ::" cr        only hidden also words previous
." keys-forth ::" cr    only keys-forth also words previous
." decompressor ::" cr  only decompressor also words previous
." assembler ::" cr     only assembler also words previous
." root ::" cr          only root also words previous
bye
