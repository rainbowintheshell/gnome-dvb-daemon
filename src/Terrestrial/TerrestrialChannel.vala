using GLib;

namespace DVB {

    public class TerrestrialChannel : Channel {
    
        public DvbSrcInversion Inversion {get; set;}
        public DvbSrcBandwidth Bandwith {get; set;}
        public DvbSrcCodeRate CodeRateHP {get; set;}
        public DvbSrcCodeRate CodeRateLP {get; set;}
        public string Constellation {get; set;}
        public DvbSrcTransmissionMode TransmissionMode {get; set;}
        public DvbSrcGuard GuardInterval {get; set;}
        public DvbSrcHierarchy Hierarchy {get; set;}
        
        public string to_string () {
            return "%s:%d:%s:%s:%s:%s:%s:%s:%s:%s:%d:%d:%d".printf(base.Name, base.Frequency,
                Utils.get_nick_from_enum (typeof(DvbSrcInversion),
                                          this.Inversion),
                Utils.get_nick_from_enum (typeof(DvbSrcBandwidth),
                                          this.Bandwith),
                Utils.get_nick_from_enum (typeof(DvbSrcCodeRate),
                                          this.CodeRateHP),
                Utils.get_nick_from_enum (typeof(DvbSrcCodeRate),
                                          this.CodeRateLP),
                this.Constellation,
                Utils.get_nick_from_enum (typeof(DvbSrcTransmissionMode),
                                          this.TransmissionMode),
                Utils.get_nick_from_enum (typeof(DvbSrcGuard),
                                          this.GuardInterval),
                Utils.get_nick_from_enum (typeof(DvbSrcHierarchy),
                                          this.Hierarchy),
                base.VideoPID, base.AudioPID, base.Sid);
        }
    
    }

}