# Coupling for TARGET=pci -- -include'd by config.mk. What this machine
# is: md/README, md/pci/README.
#
# A PCI MD needs the sun4v-vpci dropin, which only niagara1-hw/release has.
MD_LEGION_IO ?= no
MD_PCI       ?= yes
OBP_PLATFORM ?= niagara1-hw
OBP_TARGET   ?= release
# 4096 MB: these run on our patched QEMU (with the TTE page-size patch, see
# md/legion/README), so the 2048 MB default of config.mk (the stock-QEMU limit)
# does not apply.
MD_MEM       ?= 4096
