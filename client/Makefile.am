SUBDIRS = \
	gnomedvb

if ENABLE_GRILO
SUBDIRS += grilo-plugin
endif

gnomedvbbindir = $(bindir)
gnomedvbbin_SCRIPTS = \
	gnome-dvb-control \
	gnome-dvb-setup

EXTRA_DIST = \
	gnome-dvb-control.in \
	gnome-dvb-setup.in
