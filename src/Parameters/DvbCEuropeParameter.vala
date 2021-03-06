/*
 * DvbCEuropeParameter.vala
 *
 * Copyright (C) 2014 Stefan Ringel
 *
 * GNOME DVB Daemon is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * GNOME DVB Daemon is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.
 */

using GLib;
using GstMpegts;
using DVB.Logging;

namespace DVB {
    public class DvbCEuropeParameter : Parameter {
        private static Logger log = LogManager.getLogManager().getDefaultLogger();

        public uint SymbolRate { get; private set; }

        public ModulationType Modulation { get; private set; }

        public DVBCodeRate InnerFEC { get; private set; }

        // Constructor
        public DvbCEuropeParameter () {
            base (DvbSrcDelsys.SYS_DVBC_ANNEX_A);
        }

        public DvbCEuropeParameter.with_parameter (uint frequency, uint symbol_rate,
                ModulationType modulation, DVBCodeRate inner_fec) {
            base (DvbSrcDelsys.SYS_DVBC_ANNEX_A);
            this.Frequency = frequency;
            this.SymbolRate = symbol_rate;
            this.Modulation = modulation;
            this.InnerFEC = inner_fec;
        }

        public override bool add_scanning_data (HashTable<string, Variant> data) {
            unowned Variant _var;

            _var = data.lookup ("frequency");
            if (_var == null)
                return false;
            this.Frequency = _var.get_uint32 ();

            _var = data.lookup ("symbol-rate");
            if (_var == null)
                return false;
            this.SymbolRate = _var.get_uint32 ();

            _var = data.lookup ("inner-fec");
            if (_var == null)
                return false;
            this.InnerFEC = getCodeRateEnum (_var.get_string ());

            _var = data.lookup ("modulation");
            if (_var == null)
                return false;
            this.Modulation = getModulationEnum (_var.get_string ());

            return true;
        }

        public override bool equal (Parameter param) {
            if (param == null)
                return false;

            if (param.Delsys != this.Delsys)
                return false;

            DvbCEuropeParameter cparam = (DvbCEuropeParameter)param;

            if (cparam.Frequency == this.Frequency &&
                cparam.SymbolRate == this.SymbolRate &&
                cparam.InnerFEC == this.InnerFEC &&
                cparam.Modulation == this.Modulation)
                return true;

            return false;
        }

        public override void prepare (Gst.Element source) {
            log.debug ("Prepare DVB-C Scanning Parameter");
            source.set ("frequency", this.Frequency);
            source.set ("symbol-rate", this.SymbolRate / 1000);
            source.set ("modulation", this.Modulation);
            source.set ("code-rate-hp", this.InnerFEC);
            source.set ("delsys", this.Delsys);
        }

        public override string to_string () {
            return "DVBC/ANNEX_A:%u:%u:%s:%s".printf (this.Frequency, this.SymbolRate / 1000,
                getModulationString (this.Modulation), getCodeRateString (this.InnerFEC));
        }
    }
}
