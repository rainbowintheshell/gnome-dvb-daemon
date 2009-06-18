# -*- coding: utf-8 -*-
# Copyright (C) 2008,2009 Sebastian Pölsterl
#
# This file is part of GNOME DVB Daemon.
#
# GNOME DVB Daemon is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GNOME DVB Daemon is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.

import gobject
import gnomedvb
import gtk
from gnomedvb.DVBModel import DVBModel
from gettext import gettext as _
from gnomedvb.ui.wizard.pages.BasePage import BasePage

DVB_TYPE_TO_DESC = {
    "DVB-C": _("digital cable"),
    "DVB-S": _("digital satellite"),
    "DVB-T": _("digital terrestrial")
}

class AdaptersPage(BasePage):
    
    __gsignals__ = {
        "finished": (gobject.SIGNAL_RUN_LAST, gobject.TYPE_NONE, [bool]),
    }

    def __init__(self):
        BasePage.__init__(self)
        
        self.__adapter_info = None
        
        label = gtk.Label()
        label.set_line_wrap(True)
        self.pack_start(label)
        
        # Name, Type Name, Type, adapter, frontend
        self.deviceslist = gtk.ListStore(str, str, str, int, int)
        self.get_dvb_devices()
        
        if len(self.deviceslist) == 0:
            text = _('<big><span weight="bold">No devices have been found.</span></big>')
            text += "\n\n"
            text += _('Either no DVB cards are installed or all cards are busy. In the latter case make sure you close all programs such as video players that access your DVB card.')
            label.set_markup (text)
            
            self.emit("finished", False)
        else:
            text = _("Select device you want to search channels for.")
            label.set_markup (text)
        
            self.devicesview = gtk.TreeView(self.deviceslist)
            self.devicesview.get_selection().connect("changed",
                self.on_device_selection_changed)
        
            cell_name = gtk.CellRendererText()
            col_name = gtk.TreeViewColumn(_("Name"))
            col_name.pack_start(cell_name)
            col_name.add_attribute(cell_name, "text", 0)
            self.devicesview.append_column(col_name)
        
            cell_type = gtk.CellRendererText()
            col_type = gtk.TreeViewColumn(_("Type"))
            col_type.pack_start(cell_type)
            col_type.add_attribute(cell_type, "text", 1)
            self.devicesview.append_column(col_type)
        
            scrolledview = gtk.ScrolledWindow()
            scrolledview.set_shadow_type(gtk.SHADOW_ETCHED_IN)
            scrolledview.set_policy(gtk.POLICY_AUTOMATIC, gtk.POLICY_AUTOMATIC)
            scrolledview.add(self.devicesview)
        
            self.pack_start(scrolledview)
            
            self.emit("finished", True)
        
    def get_page_title(self):
        return _("Device selection")
    
    def get_selected_device(self):
        model, aiter = self.devicesview.get_selection().get_selected()
        if aiter != None:
            return None
        else:
            return model[aiter]
        
    def get_adapter_info(self):
        if self.__adapter_info == None and len(self.deviceslist) == 1:
            aiter = self.deviceslist.get_iter_first()
            self.__adapter_info = {"name": self.deviceslist[aiter][0],
                                   "type": self.deviceslist[aiter][2],
                                   "adapter": self.deviceslist[aiter][3],
                                   "frontend": self.deviceslist[aiter][4]}
        return self.__adapter_info
        
    def get_devices_count(self):
        return len(self.deviceslist)
        
    def get_dvb_devices(self):
        model = DVBModel()
        
        devs = set()
        
        devgroups = model.get_registered_device_groups()
        for group in devgroups:
            for dev in group["devices"]:
                dev.type_name = DVB_TYPE_TO_DESC[dev.type]
                devs.add(dev)
        
        for dev in model.get_all_devices():
            if dev not in devs:
                info = gnomedvb.get_adapter_info(dev.adapter)
                dev.name = info["name"]
                dev.type = info["type"]
                dev.type_name = DVB_TYPE_TO_DESC[info["type"]]
                devs.add(dev)
                    
        for dev in devs:
            self.deviceslist.append([dev.name, dev.type_name,
                dev.type, dev.adapter, dev.frontend])
    
    def on_device_selection_changed(self, treeselection):
        model, aiter = treeselection.get_selected()
        if aiter != None:
            self.__adapter_info = {"name": model[aiter][0],
                                   "type": model[aiter][2],
                                   "adapter": model[aiter][3],
                                   "frontend": model[aiter][4]}
            self.emit("finished", True)
        else:
            self.emit("finished", False)
        
