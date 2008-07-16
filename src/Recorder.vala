using GLib;
using Gst;
using Gee;

namespace DVB {

    public class RecordingThread : GLib.Object {
    
        public Timer active_timer {get; construct;}
        public Device device {get; construct;}
        
        protected Element? pipeline;
        protected Recording active_recording;
        
        public signal void recording_stopped (Recording rec);
    
        public RecordingThread (Timer timer, Device device) {
            this.active_timer = timer;
            this.device = device;
        }
        
        protected void reset () {
            if (this.pipeline != null)
                this.pipeline.set_state (State.NULL);
            this.pipeline = null;
        }
        
        public void stop_current_recording () {
            this.active_recording.Length = Utils.difftime (Time.local (time_t ()),
                this.active_recording.StartTime);
        
            debug ("Stopping recording of channel %u after %lli seconds",
                this.active_recording.ChannelSid, this.active_recording.Length);
            
            try {
                this.active_recording.save_to_disk ();
            } catch (Error e) {
                critical ("Could not save recording: %s", e.message);
            }
            
            RecordingsStore.get_instance().add (this.active_recording);
            
            this.recording_stopped (this.active_recording);
            this.reset ();
        }
        
        public void start_recording () {
            debug ("Starting recording of channel %u",
                this.active_timer.ChannelSid);
        
            Gst.Element dvbbasebin = ElementFactory.make ("dvbbasebin",
                "dvbbasebin");
            DVB.Channel channel = this.device.Channels.get (
                this.active_timer.ChannelSid);
            channel.setup_dvb_source (dvbbasebin);
            
            this.active_recording = new Recording ();
            this.active_recording.Id = this.active_timer.Id;
            this.active_recording.ChannelSid = this.active_timer.ChannelSid;
            this.active_recording.StartTime =
                this.active_timer.get_start_time_time ();
            this.active_recording.Length = this.active_timer.Duration;
            
            if (!this.create_recording_dirs (channel)) return;
            
            this.pipeline = new Pipeline (
                "recording_%u".printf(this.active_recording.ChannelSid));
            
            weak Gst.Bus bus = this.pipeline.get_bus();
            bus.add_signal_watch();
            bus.message += this.bus_watch_func;
                
            dvbbasebin.pad_added += this.on_dvbbasebin_pad_added;
            dvbbasebin.set ("program-numbers",
                            this.active_recording.ChannelSid.to_string());
            dvbbasebin.set ("adapter", this.device.Adapter);
            dvbbasebin.set ("frontend", this.device.Frontend);
            
            Element filesink = ElementFactory.make ("filesink", "sink");
            filesink.set ("location",
                this.active_recording.Location.get_path ());
            // don't use add_many because of problems with ownership transfer
            ((Bin) this.pipeline).add (dvbbasebin);
            ((Bin) this.pipeline).add (filesink);
            
            this.pipeline.set_state (State.PLAYING);
        }
        
        /**
         * Create directories and set location of recording
         *
         * @returns: TRUE on success
         */
        private bool create_recording_dirs (Channel channel) {
            Recording rec = this.active_recording;
            uint[] start = rec.get_start ();
            
            string channel_name = Utils.remove_nonalphanums (channel.Name);
            string time = "%u-%u-%u_%u-%u".printf (start[0], start[1],
                start[2], start[3], start[4]);
            
            File dir = this.device.RecordingsDirectory.get_child (
                channel_name).get_child (time);
            
            if (!dir.query_exists (null)) {
                try {
                    Utils.mkdirs (dir);
                } catch (Error e) {
                    error (e.message);
                    return false;
                }
            }
            
            string attributes = "%s,%s".printf (FILE_ATTRIBUTE_STANDARD_TYPE,
                                                FILE_ATTRIBUTE_ACCESS_CAN_WRITE);
            FileInfo info;
            try {
                info = dir.query_info (attributes, 0, null);
            } catch (Error e) {
                critical (e.message);
                return false;
            }
            
            if (info.get_attribute_uint32 (FILE_ATTRIBUTE_STANDARD_TYPE)
                != FileType.DIRECTORY) {
                critical ("%s is not a directory", dir.get_path ());
                return false;
            }
            
            if (!info.get_attribute_boolean (FILE_ATTRIBUTE_ACCESS_CAN_WRITE)) {
                critical ("Cannot write to %s", dir.get_path ());
                return false;
            }
            
            this.active_recording.Location = dir.get_child ("001.ts");
            
            return true;
        }
        
        private void on_dvbbasebin_pad_added (Gst.Element elem, Gst.Pad pad) {
            debug ("Pad %s added", pad.get_name());
        
            string sid = this.active_recording.ChannelSid.to_string();
            string program = "program_%s".printf(sid);
            if (pad.get_name() == program) {
                Element sink = ((Bin) this.pipeline).get_by_name ("sink");
                Pad sinkpad = sink.get_pad ("sink");
                
                pad.link (sinkpad);
            }
        }
        
        private void bus_watch_func (Gst.Bus bus, Gst.Message message) {
            switch (message.type) {
                case Gst.MessageType.ELEMENT:
                    if (message.structure.get_name() == "dvb-read-failure") {
                        critical ("Could not read from DVB device");
                        this.stop_current_recording ();
                    }
                break;
                
                case Gst.MessageType.ERROR:
                    Error gerror;
                    string debug_text;
                    message.parse_error (out gerror, out debug_text);
                    
                    critical (gerror.message);
                    critical (debug_text);
                        
                    this.stop_current_recording ();
                break;
                
                default:
                break;
            }
        }
        
    }

    /**
     * This class is responsible for managing upcoming recordings and
     * already recorded items for a single device
     */
    public class Recorder : GLib.Object, IDBusRecorder {
    
        /* Set in constructor of sub-classes */
        public DVB.DeviceGroup DeviceGroup { get; construct; }
        
        // Map timer id to recording thread
        protected Map<uint32, RecordingThread> active_recordings;
        
        private bool have_check_timers_timeout;
        private HashMap<uint32, Timer> timers;
        private static const int CHECK_TIMERS_INTERVAL = 5;
        
        construct {
            this.active_recordings = new HashMap<uint32, RecordingThread> ();
            this.timers = new HashMap<uint, Timer> ();
            this.have_check_timers_timeout = false;
            RecordingsStore.get_instance ().restore_from_dir (
                this.DeviceGroup.RecordingsDirectory);
        }
        
        public Recorder (DVB.DeviceGroup dev) {
            this.DeviceGroup = dev;
        }
        
        /**
         * @channel: Channel number
         * @start_year: The year when the recording should start
         * @start_month: The month when recording should start
         * @start_day: The day when recording should start
         * @start_hour: The hour when recording should start
         * @start_minute: The minute when recording should start
         * @duration: How long the channel should be recorded (in minutes)
         * @returns: The new timer's id on success, or 0 if timer couldn't
         * be created
         * 
         * Add a new timer
         */
        public uint32 AddTimer (uint channel,
            int start_year, int start_month, int start_day,
            int start_hour, int start_minute, uint duration) {
            debug ("Adding new timer: channel: %u, start: %d-%d-%d %d:%d, duration: %u",
                channel, start_year, start_month, start_day,
                start_hour, start_minute, duration);
                
            if (!this.DeviceGroup.Channels.contains (channel)) {
                debug ("No channel %u for device group %u", channel,
                    this.DeviceGroup.Id);
                return 0;
            }
            
            uint32 timer_id = RecordingsStore.get_instance ().get_next_id ();
                
            // TODO Get name for timer
            var new_timer = new Timer (timer_id,
                                       this.DeviceGroup.Channels.get(channel).Sid,
                                       start_year, start_month, start_day,
                                       start_hour, start_minute, duration,
                                       null);
            return this.add_timer (new_timer);
        }
        
        public uint32 add_timer (Timer new_timer) {
            if (new_timer.has_expired()) return 0;
            
            uint32 timer_id = 0;
            lock (this.timers) {
                bool has_conflict = false;
                int conflict_count = 0;
                
                // Check for conflicts
                foreach (uint32 key in this.timers.get_keys()) {
                    if (this.timers.get(key).conflicts_with (new_timer)) {
                        conflict_count++;
                        
                        if (conflict_count >= this.DeviceGroup.size) {
                            debug ("Timer is conflicting with another timer: %s",
                                this.timers.get(key).to_string ());
                            has_conflict = true;
                            break;
                        }
                    }
                }
                
                if (!has_conflict) {
                    this.timers.set (new_timer.Id, new_timer);
                    GConfStore.get_instance ().add_timer_to_device_group (new_timer,
                        this.DeviceGroup);
                    this.changed (new_timer.Id, ChangeType.ADDED);
                                   
                    if (this.timers.size == 1 && !this.have_check_timers_timeout) {
                        debug ("Creating new check timers");
                        Timeout.add_seconds (
                            CHECK_TIMERS_INTERVAL, this.check_timers
                        );
                        this.have_check_timers_timeout = true;
                    }
                    
                    timer_id = new_timer.Id;
                }
            }
            
            return timer_id;
        }
        
        /**
         * @timer_id: The id of the timer you want to delete
         * @returns: TRUE on success
         *
         * Delete timer. If the id belongs to the currently
         * active timer recording is aborted.
         */
        public bool DeleteTimer (uint32 timer_id) {
            if (this.IsTimerActive (timer_id)) {
                this.stop_recording (
                    this.active_recordings.get(timer_id));
                return true;
            }
            
            bool val;
            lock (this.timers) {
                if (this.timers.contains (timer_id)) {
                    this.timers.remove (timer_id);
                    GConfStore.get_instance ().remove_timer_from_device_group (
                        timer_id, this.DeviceGroup);
                    this.changed (timer_id, ChangeType.DELETED);
                    val = true;
                } else {
                    val = false;
                }
            }
            return val;
        }
        
        /**
         * dvb_recorder_GetTimers
         * @returns: A list of all timer ids
         */
        public uint32[] GetTimers () {
            uint32[] timer_arr;
            lock (this.timers) {
                timer_arr = new uint32[this.timers.size];
                
                int i=0;
                foreach (uint32 key in this.timers.get_keys()) {
                    timer_arr[i] = this.timers.get(key).Id;
                    i++;
                }
            }
        
            return timer_arr;
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: An array of length 5, where index 0 = year, 1 = month,
         * 2 = day, 3 = hour and 4 = minute.
         */
        public uint32[] GetStartTime (uint32 timer_id) {
            uint32[] val;
            lock (this.timers) {
                if (this.timers.contains (timer_id))
                    val = this.timers.get(timer_id).get_start_time ();
                else
                    val = new uint[] {};
            }
            return val;
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: Same as dvb_recorder_GetStartTime()
         */
        public uint[] GetEndTime (uint32 timer_id) {
            uint[] val;
            lock (this.timers) {
                if (this.timers.contains (timer_id))
                    val = this.timers.get(timer_id).get_end_time ();
                else
                    val = new uint[] {};
            }
            return val;
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: Duration in seconds or 0 if there's no timer with
         * the given id
         */
        public uint GetDuration (uint32 timer_id) {
            uint val = 0;
            lock (this.timers) {
                if (this.timers.contains (timer_id))
                    val = this.timers.get(timer_id).Duration;
            }
            return val;
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: The name of the channel the timer belongs to or an
         * empty string when a timer with the given id doesn't exist
         */
        public string GetChannelName (uint32 timer_id) {
            string name = "";
            lock (this.timers) {
                if (this.timers.contains (timer_id)) {
                    Timer t = this.timers.get (timer_id);
                    name = this.DeviceGroup.Channels.get (t.ChannelSid).Name;
                }
            }
            return name;
        }
        
        /**
         * @returns: The currently active timers
         */
        public uint32[] GetActiveTimers () {
            uint32[] val = new uint32[this.active_recordings.size];
            
            int i=0;
            foreach (uint32 timer_id in this.active_recordings.get_keys ()) {
                RecordingThread recthread =
                    this.active_recordings.get (timer_id);
                val[i] = recthread.active_timer.Id;
                i++;
            }
            return val;
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: TRUE if timer is currently active
         */
        public bool IsTimerActive (uint32 timer_id) {

            return this.active_recordings.contains (timer_id);
        }
        
        /**
         * @returns: TRUE if a timer is already scheduled in the given
         * period of time
         */
        public bool HasTimer (uint start_year, uint start_month,
        uint start_day, uint start_hour, uint start_minute, uint duration) {
            bool val = false;
            lock (this.timers) {
                foreach (uint32 key in this.timers.get_keys()) {
                    if (this.timers.get(key).is_in_range (start_year, start_month,
                    start_day, start_hour, start_minute, duration))
                        val = true;
                        break;
                }
            }
        
            return val;
        }
        
        protected void start_recording (Timer timer) {
            DVB.Device? free_device = this.DeviceGroup.get_next_free_device ();
            if (free_device == null) {
                critical ("All devices are busy");
                return;
            }
        
            RecordingThread recthread = new RecordingThread (timer, free_device);
            recthread.recording_stopped += on_recording_stopped;
            recthread.start_recording ();
            
            this.active_recordings.set (timer.Id, recthread);
            
            this.recording_started (timer.Id);
        }
        
        protected void stop_recording (RecordingThread recthread) {
            recthread.stop_current_recording ();
        }
        
        private bool check_timers () {
            debug ("Checking timers");
            
            SList<RecordingThread> ended_recordings =
                new SList<RecordingThread> ();
            foreach (uint32 timer_id in this.active_recordings.get_keys ()) {
                RecordingThread recthread =
                    this.active_recordings.get (timer_id);
                Timer timer = recthread.active_timer;
                if (timer.is_end_due())
                    ended_recordings.prepend (recthread);
            }
            
            for (int i=0; i<ended_recordings.length(); i++) {
                this.stop_recording (ended_recordings.nth_data (i));
            }
            
            bool val;
            // Store items we want to delete in here
            SList<uint32> deleteable_items = new SList<uint32> ();
            // Don't use this.DeleteTimer for them
            SList<uint32> removeable_items = new SList<uint32> ();
            lock (this.timers) {
                foreach (uint32 key in this.timers.get_keys()) {
                    Timer timer = this.timers.get (key);
                    
                    debug ("Checking timer: %s", timer.to_string());
                    
                    if (timer.is_start_due()) {
                        this.start_recording (timer);
                        removeable_items.prepend (key);
                    } else if (timer.has_expired()) {
                        debug ("Removing expired timer: %s", timer.to_string());
                        deleteable_items.prepend (key);
                    }
                }
                
                // Delete items from this.timers using this.DeleteTimer
                for (int i=0; i<deleteable_items.length(); i++) {
                    this.DeleteTimer (deleteable_items.nth_data (i));
                }
                
                for (int i=0; i<removeable_items.length(); i++) {
                    this.timers.remove (removeable_items.nth_data (i));
                }
                
                if (this.timers.size == 0 && this.active_recordings.size == 0) {
                    // We don't have any timers and no recording is in progress
                    debug ("No timers left and no recording in progress");
                    this.have_check_timers_timeout = false;
                    val = false;
                } else {
                    // We still have timers
                    debug ("%d timers and %d active recordings left",
                        this.timers.size,
                        this.active_recordings.size);
                    val = true;
                }
                
            }
            return val;
        }
        
        private void on_recording_stopped (RecordingThread recthread,
                Recording recording) {
            this.recording_finished (recording.Id);
            this.active_recordings.remove (recthread.active_timer.Id);
        }
        
    }

}
