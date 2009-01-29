# -*- coding: utf-8 -*-
import gtk
import gobject
from gettext import gettext as _
from gnomedvb.Device import Device

__all__ = ["UnassignedDevicesStore", "DeviceGroupsStore", "DeviceGroupsView"]

class UnassignedDevicesStore (gtk.ListStore):

    (COL_DEVICE,) = range(1)
    
    def __init__(self):
        gtk.ListStore.__init__(self, gobject.TYPE_PYOBJECT)


class DeviceGroupsStore (gtk.TreeStore):

    (COL_ID,COL_DEVICE,) = range(2)

    def __init__(self):
        gtk.TreeStore.__init__(self, int, gobject.TYPE_PYOBJECT)
        
    def get_groups(self):
        groups = []
        for row in self:
            if not isinstance(row, Device):
                groups.append((row[self.COL_ID], row.iter))
        return groups
 
    
class DeviceGroupsView (gtk.TreeView):

    def __init__(self, model):
        gtk.TreeView.__init__(self, model)
        self.set_headers_visible(False)
        #self.set_reorderable(True)
        
        cell_description = gtk.CellRendererText ()
        column_description = gtk.TreeViewColumn (_("Devices"), cell_description)
        column_description.set_cell_data_func(cell_description, self.get_description_data)
        self.append_column(column_description)
        
    def get_description_data(self, column, cell, model, aiter):
        device = model[aiter][model.COL_DEVICE]
        
        if isinstance(device, Device):
            # translators: first is device's name, second its type
            text = _("<b>%s (%s)</b>\n") % (device.name, device.type)
            text += _("<small>Adapter: %d, Frontend: %d</small>") % (device.adapter,
                device.frontend)
        else:
            if device == "":
                group_id = model[aiter][model.COL_ID]
                text = _("Group %d") % group_id
            else:
                text = device
            
        cell.set_property("markup", text)

