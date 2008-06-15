using GLib;

public class Main {

    private static DVB.Manager manager;

    private static void start_manager () {
    
        try {
            var conn = DBus.Bus.get (DBus.BusType.SESSION);
            
            dynamic DBus.Object bus = conn.get_object (
                    "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus");
            
            // try to register service in session bus
            uint request_name_result = bus.RequestName (DVB.Constants.DBUS_SERVICE, (uint) 0);

            if (request_name_result == DBus.RequestNameReply.PRIMARY_OWNER) {
                debug("Creating new Manager D-Bus service");
            
                manager = new DVB.Manager ();
                                
                conn.register_object (
                    DVB.Constants.DBUS_MANAGER_PATH,
                    manager);
            } else {
                debug("Manager D-Bus service is already running");
            }

        } catch (Error e) {
            error("Oops %s", e.message);
        }
    }
    
    private static void recording_finished (DVB.Recorder recorder, uint32 id) {
        stdout.printf ("Recording %u finished\n", id);
        
        weak DVB.RecordingsStore rec = DVB.RecordingsStore.get_instance();
        
        foreach (uint32 rid in rec.GetRecordings()) {
            stdout.printf ("ID: %u\n", rid);
            stdout.printf ("Location: %s\n", rec.GetLocation (rid));
            stdout.printf ("Length: %lli\n", rec.GetLength (rid));
            uint[] start = rec.GetStartTime (rid);
            stdout.printf ("Start: %u-%u-%u %u:%u\n", start[0], start[1],
                start[2], start[3], start[4]);
        }
    }

    public static void main (string[] args) {
        MainLoop loop;
    
        // Creating a GLib main loop with a default context
        loop = new MainLoop (null, false);

        // Initializing GStreamer
        Gst.init (ref args);
        
        File channelsfile = File.new_for_path ("/home/sepb/.gstreamer-0.10/dvb-channels.conf");
        
        var reader = new DVB.ChannelListReader (channelsfile, DVB.AdapterType.DVB_T);
        try {
            reader.read ();
        } catch (Error e) {
            error (e.message);
        }

        File recdir = File.new_for_path ("/home/sebp/TV");

        DVB.Device device = DVB.Device.new_full (0, 0,
            reader.Channels, recdir);
        var rec = new DVB.TerrestrialRecorder (device);
        rec.recording_finished += recording_finished;
        
        //DVB.RecordingsStore.get_instance ().Delete ((uint32)1);
        
        rec.AddTimer (17501, 2008, 6, 14, 17, 52, 2);
        rec.AddTimer (32, 2008, 6, 9, 21, 39, 3);
        rec.AddTimer (32, 2008, 6, 5, 10, 25, 3);
        rec.AddTimer (99999, 2008, 6, 20, 10, 55, 9);
        rec.AddTimer (16418, 2006, 6, 6, 6, 6, 99);

        //start_manager();
        
        Gst.Structure ter_pro7 = new Gst.Structure ("pro7",
                "hierarchy", typeof(uint), 0,
                "bandwidth", typeof(uint), 8,
                "frequency", typeof(uint), 690000000,
                "transmission-mode", typeof(string), "8k",
                "code-rate-hp", typeof(string), "2/3",
                "code-rate-lp", typeof(string), "1/2",
                "constellation", typeof(string), "QAM16",
                "guard-interval", typeof(uint), 4);
        /*
        Gst.Structure sat_pro7 = new Gst.Structure ("pro7",
            "frequency", typeof(uint), 12544000,
            "symbol-rate", typeof(uint), 22000,
            "polarization", typeof(string), "h");
        */  
        
        DVB.Scanner scanner = new DVB.TerrestrialScanner (device);
        scanner.add_structure_to_scan (#ter_pro7);
        scanner.Run ();
        
        // Start GLib mainloop
        loop.run ();
    }

}
