/*
 * Copyright (C) 2009 Sebastian Pölsterl
 *
 * This file is part of GNOME DVB Daemon.
 *
 * GNOME DVB Daemon is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * GNOME DVB Daemon is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with GNOME DVB Daemon.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace DVB.database {

    /* from http://sqlite.org/c3ref/c_abort.html */
    public errordomain SqlError {
        ERROR,
        INTERNAL,
        PERM,
        ABORT,
        BUSY,
        LOCKED,
        NOMEM,
        READONLY,
        INTERRUPT,
        IOERR,
        CORRUPT,
        NOTFOUND,
        FULL,
        CANTOPEN,
        PROTOCOL,
        EMPTY,
        SCHEMA,
        TOOBIG,
        CONSTRAINT,
        MISMATCH,
        MISUSE,
        NOLFS,
        AUTH,
        FORMAT,
        RANGE,
        NOTADB
    }

}
