# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# HV_OPTIONS (config.mk) renamed for the makefiles that consume it. Both
# toolchains take the same list once -- Sun's EXTRA_OPTIONS=, or HV_EXTRA_OPTS=
# to gnu/hv-opts.sh. Neither path copies it a second time.
#
# What each flag does and why, why -DT1_FPGA is absent, and why CONFIG_HVUART
# is off by default: README.options next to this file.

QEMU_EXTRA_OPTIONS := $(HV_OPTIONS)
PLATFORM := $(HV_PLATFORM)
VARIANT  := $(HV_VARIANT)
