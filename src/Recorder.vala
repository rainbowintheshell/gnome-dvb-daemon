using GLib;
using Gst;
using Gee;

namespace DVB {

    /**
     * This class is responsible for managing upcoming recordings and
     * already recorded items for a single device
     */
    public abstract class Recorder : GLib.Object {
    
        public signal void recording_started (uint timer_id);
        public signal void recording_finished (uint recording_id);
        
        public DVB.Device Device { get; construct; }
        public ChannelList Channels { get; construct; }
        
        protected Element? pipeline;
        protected Recording active_recording;
        protected Timer? active_timer;
        
        private HashMap<uint, Timer> timers;
        private uint timer_counter;
        private string basedir;
        
        private static const int CHECK_TIMERS_INTERVAL = 5;
        
        construct {
            this.timers = new HashMap<uint, Timer> ();
            this.reset ();
            this.basedir = "/home/sebp/TV/";
        }
        
        /**
         * Setup dvbbasebin element with name "dvbbasebin"
         */
        protected abstract weak Element? get_dvbbasebin (Channel channel);
        
        /**
         * @channel: Channel number
         * @start_year: The year when the recording should start
         * @start_month: The month when recording should start
         * @start_day: The day when recording should start
         * @start_hour: The hour when recording should start
         * @start_minute: The minute when recording should start
         * @duration: How long the channel should be recorded (in minutes)
         * @returns: The new timer's id on success
         * 
         * Add a new timer
         */
        public uint AddTimer (uint channel,
            int start_year, int start_month, int start_day,
            int start_hour, int start_minute, uint duration) {
            debug ("Adding new timer: channel: %d, start: %d-%d-%d %d:%d, duration: %d",
                channel, start_year, start_month, start_day,
                start_hour, start_minute, duration);
            // FIXME thread-safety
            this.timer_counter++;
            this.timers.set (this.timer_counter,
                new Timer (this.timer_counter, this.Channels.get(channel),
                           null, null,
                           start_year, start_month, start_day,
                           start_hour, start_minute, duration));
                           
            if (this.timers.size == 1) {
                debug ("Creating new check timers");
                Timeout.add_seconds (
                    CHECK_TIMERS_INTERVAL, this.check_timers
                );
            }
            
            return this.timer_counter;
        }
        
        /**
         * @timer_id: The id of the timer you want to delete
         * @returns: TRUE on success
         *
         * Delete timer
         */
        public bool DeleteTimer (uint timer_id) {
            // TODO: Check if timer is active
            // FIXME thread-safety
            if (this.timers.contains (timer_id)) {
                this.timers.remove (timer_id);
                return true;
            } else {
                return false;
            }
        }
        
        /**
         * dvb_recorder_GetTimers
         * @returns: A list of all timer ids
         */
        public uint[] GetTimers () {
            uint[] timer_arr = new uint[this.timers.size];
            // FIXME thread-safety
            int i=0;
            foreach (uint key in this.timers.get_keys()) {
                timer_arr[i] = this.timers.get(key).Id;
                i++;
            }
        
            return timer_arr;
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: An array of length 5, where index 0 = year, 1 = month,
         * 2 = day, 3 = hour and 4 = minute.
         */
        public uint[]? GetStartTime (uint timer_id) {
            // FIXME thread-safety
            if (!this.timers.contains (timer_id)) return null;
        
            return this.timers.get(timer_id).get_start_time ();
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: Same as dvb_recorder_GetStartTime()
         */
        public uint[]? GetEndTime (uint timer_id) {
            // FIXME thread-safety
            if (!this.timers.contains (timer_id)) return null;
        
            return this.timers.get(timer_id).get_end_time ();
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: Duration in seconds
         */
        public uint? GetDuration (uint timer_id) {
            // FIXME thread-safety
            if (!this.timers.contains (timer_id)) return null;
        
            return this.timers.get(timer_id).Duration;
        }
        
        /**
         * @returns: A list of ids for the currently active timers
         * (i.e.currently active recordings)
         */
        public uint[] GetActiveTimers () {
            // TODO: Move to other class
            return new uint[] {0};
        }
        
        /**
         * @timer_id: Timer's id
         * @returns: TRUE if timer is currently active
         */
        public bool IsTimerActive (uint timer_id) {

            return (timer_id == this.active_recording.id);
        }
        
        /**
         * @returns: TRUE if a timer is already scheduled in the given
         * period of time
         */
        public bool HasTimer (uint start_year, uint start_month,
        uint start_day, uint start_hour, uint start_minute, uint duration) {
        
            return true;
        }
        
        protected void reset () {
            if (this.pipeline != null)
                this.pipeline.set_state (State.NULL);
            this.pipeline = null;
            this.active_timer = null;
        }
        
        protected void stop_current_recording () {
            debug ("Stoping recording of channel %d", this.active_recording.channel_sid);
        
            this.reset ();
            this.recording_finished (this.active_recording.id);
        }
        
        protected void start_recording (Timer timer) {
            debug ("Starting recording of channel %d", timer.Channel.Sid);
        
            Element dvbbasebin = this.get_dvbbasebin (timer.Channel);
            
            if (dvbbasebin == null) return;
            
            this.active_timer = timer;
            
            this.active_recording = Recording ();
            this.active_recording.id = timer.Id;
            this.active_recording.channel_sid = timer.Channel.Sid;
            this.active_recording.start = timer.get_start_time ();
            this.active_recording.length = timer.Duration;
            this.active_recording.location = this.basedir+"dump.ts";
            
            this.pipeline = new Pipeline (
                "recording_%d".printf(this.active_recording.channel_sid));
            
            weak Gst.Bus bus = this.pipeline.get_bus();
            bus.add_signal_watch();
            bus.message += this.bus_watch_func;
                
            dvbbasebin.pad_added += this.on_dvbbasebin_pad_added;
            dvbbasebin.set ("program-numbers",
                            this.active_recording.channel_sid.to_string());
            dvbbasebin.set ("adapter", this.Device.Adapter);
            dvbbasebin.set ("frontend", this.Device.Frontend);
            
            Element filesink = ElementFactory.make ("filesink", "sink");
            filesink.set ("location", this.active_recording.location);
            ((Bin) this.pipeline).add_many (dvbbasebin, filesink);
            
            this.pipeline.set_state (State.PLAYING);
        }
        
        private void on_dvbbasebin_pad_added (Gst.Element elem, Gst.Pad pad) {
            debug ("Pad %s added", pad.get_name());
        
            string sid = this.active_recording.channel_sid.to_string();
            string program = "program_%s".printf(sid);
            if (pad.get_name() == program) {
                Element sink = ((Bin) this.pipeline).get_by_name ("sink");
                Pad sinkpad = sink.get_pad ("sink");
                
                pad.link (sinkpad);
            }
        }
        
        private void bus_watch_func (Gst.Bus bus, Gst.Message message) {
            if (message.type == Gst.MessageType.ELEMENT) {
                if (message.structure.get_name() == "dvb-read-failure") {
                    error ("Could not read from DVB device");
                    this.reset ();
                }
            }
        }
        
        private bool check_timers () {
            debug ("Checking timers");
            
            if (this.active_timer != null && this.active_timer.is_end_due()) {
                this.stop_current_recording ();
            }
            
            // FIXME thread-safety
            foreach (uint key in this.timers.get_keys()) {
                Timer timer = this.timers.get (key);
                
                debug ("Checking timer: %s", timer.to_string());
                
                if (timer.is_start_due()) {
                    this.start_recording (timer);
                    this.timers.remove (key);
                } else if (timer.has_expired()) {
                    debug ("Removing expired timer: %s", timer.to_string());
                    this.timers.remove (key);
                }
            }
            
            if (this.timers.size == 0 && this.active_timer == null) {
                // We don't have any timers and no recording is in progress
                debug ("No timers left and no recording in progress");
                return false;
            } else {
                // We still have timers
                debug ("%d timers left", this.timers.size);
                return true;
            }
        }
    }

}
