using GLib;

namespace DVB {
    
    [DBus (name = "org.gnome.DVB.Scanner.Satellite")]
    public interface IDBusSatelliteScanner : GLib.Object {
    
        public abstract signal void frequency_scanned (uint frequency);
        public abstract signal void finished ();
        public abstract signal void channel_added (uint frequency, uint sid,
            string name, string network, string type);
        
        public abstract void Run ();
        public abstract void Destroy ();
        public abstract bool WriteChannelsToFile (string path);
        public abstract uint GetQueueSize ();
        
        public abstract void AddScanningData (uint frequency,
                                     string polarization, // "horizontal", "vertical"
                                     uint symbol_rate);
        
        /**
         * @path: Path to file containing scanning data
         * @returns: TRUE when the file has been parsed successfully
         *
         * Parses initial tuning data from a file as provided by dvb-apps
         */                            
        public abstract bool AddScanningDataFromFile (string path);
    }
    
    public class SatelliteScanner : Scanner, IDBusSatelliteScanner {
    
        public SatelliteScanner (DVB.Device device) {
            base.Device = device;
        }
     
        public void AddScanningData (uint frequency,
                string polarization, uint symbol_rate) {
            var tuning_params = new Gst.Structure ("tuning_params",
            "frequency", typeof(uint), frequency,
            "symbol-rate", typeof(uint), symbol_rate,
            "polarization", typeof(string), polarization);
            
            base.add_structure_to_scan (#tuning_params);
        }
        
        public bool AddScanningDataFromFile (string path) {
            File datafile = File.new_for_path(path);
            
            debug ("Reading scanning data from %s", path);
            
            string? contents = null;
            try {
                contents = Utils.read_file_contents (datafile);
            } catch (Error e) {
                critical (e.message);
            }
            
            if (contents == null) return false;
            
            // line looks like:
            // S freq pol sr fec
            foreach (string line in contents.split("\n")) {
                if (line.has_prefix ("#")) continue;
                
                string[] cols = Regex.split_simple (" ", line);
                
                int cols_length = 0;
                while (cols[cols_length] != null)
                    cols_length++;
                cols_length++;
                
                if (cols_length < 5) continue;
                
                uint freq = (uint)cols[1].to_int ();
                uint symbol_rate = (uint)cols[3].to_int () / 1000;
                
                string pol;
                string lower_pol = cols[2].down ();
                if (lower_pol == "h")
                    pol = "horizontal";
                else if (lower_pol == "v")
                    pol = "vertical";
                else
                    continue;
                
                // TODO what about fec?
                
                this.AddScanningData (freq, pol, symbol_rate);
            }
            
            return true;
        }
        
        protected override void prepare () {
            debug("Setting up pipeline for DVB-S scan");
        
            Gst.Element dvbsrc = ((Gst.Bin)base.pipeline).get_by_name ("dvbsrc");
           
            string[] uint_keys = new string[] {"frequency", "symbol-rate"};
            
            foreach (string key in uint_keys) {
                base.set_uint_property (dvbsrc, base.current_tuning_params, key);
            }
            
            string polarity =
                base.current_tuning_params.get_string ("polarization")
                .substring (0, 1);
            dvbsrc.set ("polarity", polarity);
            
            uint code_rate;
            base.current_tuning_params.get_uint ("inner-fec", out code_rate);
            dvbsrc.set ("code-rate-hp", code_rate);
        }
        
        protected override ScannedItem get_scanned_item (uint frequency) {
            weak string pol =
                base.current_tuning_params.get_string ("polarization");
            return new ScannedSatteliteItem (frequency, pol);
        }
        
        protected override Channel get_new_channel () {
            return new SatelliteChannel ();
        }
        
        protected override void add_values_from_structure_to_channel (
            Gst.Structure delivery, Channel channel) {
            if (!(channel is SatelliteChannel)) return;
            
            SatelliteChannel sc = (SatelliteChannel)channel;
            
            uint freq;
            delivery.get_uint ("frequency", out freq);
            sc.Frequency = freq;
            
            sc.Polarization = delivery.get_string ("polarization").substring (0, 1);

            uint srate;
            delivery.get_uint ("symbol-rate", out srate);            
            sc.SymbolRate = srate;
            
            // TODO
            sc.DiseqcSource = -1;
        }
    }
    
}
