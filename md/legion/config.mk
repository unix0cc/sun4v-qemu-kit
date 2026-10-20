# Coupling for TARGET=legion -- -include'd by config.mk. What this machine
# is: md/README, md/legion/README.
#
# A legion MD needs SUNW,legion-disk in OBP, which only niagara/t1_fpga has.
MD_LEGION_IO ?= yes
MD_PCI       ?= no
OBP_PLATFORM ?= niagara
OBP_TARGET   ?= t1_fpga
